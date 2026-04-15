# frozen_string_literal: true

require 'uri'
require 'json'
require 'base64'
require 'securerandom'
require 'timeout'

module BSV
  module Auth
    # BRC-104 high-level client for authenticated HTTP requests.
    #
    # Manages a pool of {Peer} instances (one per base URL) and serialises
    # HTTP requests as BRC-104 binary payloads. The handshake is initiated
    # automatically on the first request to each base URL.
    #
    # When the server responds with HTTP 402 Payment Required, AuthFetch
    # automatically constructs a BSV payment transaction via the wallet and
    # retries the original request with an +x-bsv-payment+ header attached.
    #
    # Thread safety: the +@peers+ hash is protected by a mutex. Each in-flight
    # request uses its own +Queue+ to receive exactly the matching response.
    #
    # @example
    #   client = BSV::Auth::AuthFetch.new(wallet: my_wallet)
    #   response = client.fetch('https://api.example.com/resource')
    #   puts response.status   # => 200
    #   puts response.body     # => "..."
    class AuthFetch
      DEFAULT_TIMEOUT         = 30
      DEFAULT_PAYMENT_RETRIES = 3
      PAYMENT_RETRY_DELAY_MS  = 250
      PAYMENT_PROTOCOL_ID     = [2, '3241645161d8'].freeze
      SUPPORTED_PAYMENT_VERSION = '1.0'

      # @param wallet [BSV::Wallet::Interface] wallet for crypto operations
      # @param requested_certificates [Hash, nil] certificate set to request from peers
      # @param session_manager [SessionManager, nil] optional shared session store
      # @param payment_max_retries [Integer] maximum number of payment retry attempts (default 3)
      def initialize(wallet:, requested_certificates: nil, session_manager: nil, payment_max_retries: DEFAULT_PAYMENT_RETRIES)
        @wallet                 = wallet
        @requested_certificates = requested_certificates
        @session_manager        = session_manager
        @payment_max_retries    = payment_max_retries
        @peers                  = {}
        @peers_mutex            = Mutex.new
      end

      # Sends an authenticated HTTP request to +url+.
      #
      # The first request to a new base URL performs a BRC-103 mutual-auth
      # handshake automatically. Subsequent requests reuse the cached peer.
      #
      # If the server responds with 402, a BSV payment is created and the
      # request is retried with an +x-bsv-payment+ header (up to
      # +payment_max_retries+ times).
      #
      # @param url [String] full URL including scheme, host, optional port, path, and query
      # @param method [String] HTTP method (default 'GET')
      # @param headers [Hash] request headers; only +content-type+, +authorization+,
      #   and +x-bsv-*+ (excluding +x-bsv-auth-*+) are allowed
      # @param body [String, Hash, nil] request body
      # @param timeout [Integer] seconds to wait for the authenticated response (default 30)
      # @return [AuthResponse]
      # @raise [ArgumentError] if disallowed headers are provided
      # @raise [Timeout::Error] if no response arrives within +timeout+ seconds
      # @raise [AuthError] if 402 payment handling fails or max retries are exceeded
      def fetch(url, method: 'GET', headers: {}, body: nil, timeout: DEFAULT_TIMEOUT)
        do_fetch(url, method: method, headers: headers, body: body, timeout: timeout,
                      retry_count: 0, payment_context: nil)
      end

      private

      def do_fetch(url, method:, headers:, body:, timeout:, retry_count:, payment_context:)
        uri      = URI.parse(url)
        base_url = extract_base_url(uri)
        path     = uri.path.empty? ? '/' : uri.path
        query    = uri.query ? "?#{uri.query}" : nil

        peer = get_or_create_peer(base_url)

        # Validate and filter headers (raises ArgumentError for unsupported headers)
        filtered_headers = AuthHeaders.filter_request_headers(headers)

        # Normalise body: Hash → JSON string, set content-type if not already set
        effective_body, filtered_headers = normalise_body(body, filtered_headers)

        # Generate 32-byte request nonce
        request_nonce = SecureRandom.random_bytes(32)

        # Serialise request to binary payload
        payload_bytes = AuthPayload.serialize_request(
          request_nonce: request_nonce,
          method: method,
          path: path,
          query: query,
          headers: filtered_headers,
          body: effective_body
        )

        # Queue to block until the matching response arrives
        response_queue = Queue.new

        # Register a one-shot callback on the peer
        callback_id = peer.on_general_message do |sender_key, raw_payload|
          binary = array_to_binary(raw_payload)
          # Match by first 32 bytes of payload
          next unless binary.bytesize >= 32 && binary.byteslice(0, 32) == request_nonce

          begin
            deserialized = AuthPayload.deserialize_response(binary)
            response_queue.push({ ok: true, data: deserialized, identity_key: sender_key })
          rescue StandardError => e
            response_queue.push({ ok: false, error: e })
          end
        end

        begin
          peer.to_peer(payload_bytes.bytes)
        rescue AuthError => e
          peer.off_general_message(callback_id)
          if e.message.include?('Session not found') && retry_count < 3
            # Stale session — clear the cached peer and retry with a fresh one
            @peers_mutex.synchronize { @peers.delete(base_url) }
            return do_fetch(url, method: method, headers: headers, body: body,
                                 timeout: timeout, retry_count: retry_count + 1,
                                 payment_context: payment_context)
          end
          raise
        end

        begin
          result = Timeout.timeout(timeout) { response_queue.pop }
        rescue Timeout::Error
          peer.off_general_message(callback_id)
          raise Timeout::Error, "AuthFetch timed out waiting for response from #{base_url}"
        end

        peer.off_general_message(callback_id)

        raise result[:error] unless result[:ok]

        data = result[:data]
        response = AuthResponse.new(
          status: data[:status],
          headers: pairs_to_hash(data[:headers]),
          body: data[:body] || '',
          identity_key: result[:identity_key]
        )

        return response unless response.status == 402

        handle_payment_required(url, method, headers, body, timeout, response, payment_context)
      end

      # Handles a 402 Payment Required response by creating a BSV payment
      # transaction and retrying the original request.
      #
      # @param url [String] the original request URL
      # @param method [String] HTTP method
      # @param headers [Hash] original request headers
      # @param body original request body
      # @param timeout [Integer] request timeout in seconds
      # @param response [AuthResponse] the 402 response
      # @param payment_context [Hash, nil] existing payment context (for retries)
      # @return [AuthResponse] the response after payment
      # @raise [AuthError] if payment headers are invalid, wallet lacks capability,
      #   or maximum retries are exhausted
      def handle_payment_required(url, method, headers, body, timeout, response, payment_context)
        validated = validate_payment_headers(response.headers)

        satoshis_required    = validated[:satoshis_required]
        server_identity_key  = validated[:server_identity_key]
        derivation_prefix    = validated[:derivation_prefix]

        # Determine whether we can reuse an existing payment context or must create a new one
        new_context = if payment_context && compatible_payment_context?(payment_context, satoshis_required, server_identity_key, derivation_prefix)
                        payment_context
                      else
                        create_payment_context(url, satoshis_required, server_identity_key, derivation_prefix)
                      end

        attempt = new_context[:attempts] + 1

        if attempt > @payment_max_retries
          raise AuthError, "Payment for #{url} failed after #{@payment_max_retries} attempt(s): " \
                           "#{satoshis_required} satoshis required"
        end

        new_context[:attempts] = attempt

        payment_header_value = JSON.generate(
          'derivationPrefix' => new_context[:derivation_prefix],
          'derivationSuffix' => new_context[:derivation_suffix],
          'transaction' => new_context[:transaction_base64]
        )

        # Apply linear backoff for retries after the first attempt
        sleep(PAYMENT_RETRY_DELAY_MS * attempt / 1000.0) if attempt > 1

        retry_headers = headers.merge(AuthHeaders::PAYMENT => payment_header_value)

        do_fetch(url, method: method, headers: retry_headers, body: body, timeout: timeout,
                      retry_count: 0, payment_context: new_context)
      end

      # Validates the payment-related headers from a 402 response.
      #
      # @param response_headers [Hash] response headers (string keys)
      # @return [Hash] validated values: :satoshis_required, :server_identity_key, :derivation_prefix
      # @raise [AuthError] if any required header is missing or invalid
      def validate_payment_headers(response_headers)
        version = response_headers[AuthHeaders::PAYMENT_VERSION]
        unless version == SUPPORTED_PAYMENT_VERSION
          raise AuthError,
                "Unsupported #{AuthHeaders::PAYMENT_VERSION} response header. " \
                "Client version: #{SUPPORTED_PAYMENT_VERSION}, server version: #{version.inspect}"
        end

        satoshis_str = response_headers[AuthHeaders::PAYMENT_SATOSHIS_REQUIRED]
        raise AuthError, "Missing #{AuthHeaders::PAYMENT_SATOSHIS_REQUIRED} response header." unless satoshis_str

        satoshis = Integer(satoshis_str, 10)
        raise AuthError, "Invalid #{AuthHeaders::PAYMENT_SATOSHIS_REQUIRED} value: must be a positive integer." unless satoshis.positive?

        server_identity_key = response_headers[AuthHeaders::IDENTITY_KEY]
        unless server_identity_key.is_a?(String) && !server_identity_key.empty?
          raise AuthError,
                "Missing #{AuthHeaders::IDENTITY_KEY} response header."
        end

        derivation_prefix = response_headers[AuthHeaders::PAYMENT_DERIVATION_PREFIX]
        unless derivation_prefix.is_a?(String) && !derivation_prefix.empty?
          raise AuthError,
                "Missing #{AuthHeaders::PAYMENT_DERIVATION_PREFIX} response header."
        end

        {
          satoshis_required: satoshis,
          server_identity_key: server_identity_key,
          derivation_prefix: derivation_prefix
        }
      rescue ArgumentError
        raise AuthError, "Invalid #{AuthHeaders::PAYMENT_SATOSHIS_REQUIRED} value: must be a positive integer."
      end

      # Creates a new payment context by deriving a payment key and building a transaction.
      #
      # @param url [String] request URL (used in the transaction description)
      # @param satoshis_required [Integer] payment amount
      # @param server_identity_key [String] server's compressed public key hex
      # @param derivation_prefix [String] BIP-32 derivation prefix from the server
      # @return [Hash] payment context with keys :satoshis_required, :server_identity_key,
      #   :derivation_prefix, :derivation_suffix, :transaction_base64, :attempts
      # @raise [AuthError] if the wallet does not support payment methods
      def create_payment_context(url, satoshis_required, server_identity_key, derivation_prefix)
        unless @wallet.respond_to?(:get_public_key) && @wallet.respond_to?(:create_action)
          raise AuthError, '402 payment handling requires a wallet that supports create_action and get_public_key'
        end

        base_url = extract_base_url(URI.parse(url))

        derivation_suffix = Nonce.create(@wallet)

        key_result = @wallet.get_public_key(
          protocol_id: PAYMENT_PROTOCOL_ID,
          key_id: "#{derivation_prefix} #{derivation_suffix}",
          counterparty: server_identity_key
        )
        public_key_hex = key_result[:public_key]

        address = BSV::Primitives::PublicKey.from_hex(public_key_hex).address
        lock_script = BSV::Script::Script.p2pkh_lock(address)

        action_result = @wallet.create_action(
          description: "Payment for request to #{base_url}",
          outputs: [{
            satoshis: satoshis_required,
            locking_script: lock_script.to_hex,
            output_description: 'HTTP request payment'
          }]
        )

        tx_bytes = action_result[:tx] || action_result['tx']
        raise AuthError, 'wallet.create_action did not return a :tx byte array' unless tx_bytes.is_a?(Array)

        transaction_base64 = Base64.strict_encode64(tx_bytes.pack('C*'))

        {
          satoshis_required: satoshis_required,
          server_identity_key: server_identity_key,
          derivation_prefix: derivation_prefix,
          derivation_suffix: derivation_suffix,
          transaction_base64: transaction_base64,
          attempts: 0
        }
      end

      # Returns true if the existing payment context is compatible with the
      # current 402 response requirements (same satoshis, identity key, and prefix).
      def compatible_payment_context?(context, satoshis_required, server_identity_key, derivation_prefix)
        context[:satoshis_required] == satoshis_required &&
          context[:server_identity_key] == server_identity_key &&
          context[:derivation_prefix]   == derivation_prefix
      end

      # Returns an existing peer for +base_url+ or creates a new one.
      def get_or_create_peer(base_url)
        @peers_mutex.synchronize do
          @peers[base_url] ||= build_peer(base_url)
        end
      end

      def build_peer(base_url)
        transport = SimplifiedFetchTransport.new(base_url)
        Peer.new(
          wallet: @wallet,
          transport: transport,
          session_manager: @session_manager,
          certificates_to_request: @requested_certificates
        )
      end

      # Extracts scheme + host + port from a URI.
      #
      # For standard ports (80 for http, 443 for https), the port is omitted
      # to match browser +URL#origin+ behaviour used in the TS SDK.
      def extract_base_url(uri)
        default_port = uri.scheme == 'https' ? 443 : 80
        if uri.port == default_port
          "#{uri.scheme}://#{uri.host}"
        else
          "#{uri.scheme}://#{uri.host}:#{uri.port}"
        end
      end

      # Normalises the request body and updates headers accordingly.
      #
      # - Hash body → JSON.generate, sets content-type to application/json if absent
      # - String/nil body → used as-is (nil body defaults handled by AuthPayload)
      #
      # Returns [normalised_body, updated_filtered_headers].
      def normalise_body(body, filtered_headers)
        if body.is_a?(Hash)
          json_body = JSON.generate(body)
          # Add content-type: application/json if not already present
          has_ct = filtered_headers.any? { |k, _| k == 'content-type' }
          filtered_headers = (filtered_headers + [['content-type', 'application/json']]).sort_by { |k, _| k } unless has_ct
          [json_body, filtered_headers]
        else
          [body, filtered_headers]
        end
      end

      # Converts an Array<[key, value]> to a Hash with string keys.
      def pairs_to_hash(pairs)
        return {} unless pairs.is_a?(Array)

        pairs.each_with_object({}) { |(k, v), h| h[k.to_s] = v.to_s }
      end

      # Converts Array<Integer> or binary String to a binary String.
      def array_to_binary(payload)
        return payload if payload.is_a?(String)

        payload.map(&:chr).join.force_encoding('BINARY')
      end
    end

    # Immutable value object representing an authenticated HTTP response.
    class AuthResponse
      attr_reader :status, :headers, :body, :identity_key

      # @param status [Integer] HTTP status code
      # @param headers [Hash] response headers
      # @param body [String] response body
      # @param identity_key [String] server's compressed public key hex
      def initialize(status:, headers:, body:, identity_key:)
        @status       = status
        @headers      = headers
        @body         = body
        @identity_key = identity_key
      end
    end
  end
end
