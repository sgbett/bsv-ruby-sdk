# frozen_string_literal: true

require 'uri'
require 'json'
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
    # Thread safety: the +@peers+ hash is protected by a mutex. Each in-flight
    # request uses its own +Queue+ to receive exactly the matching response.
    #
    # @example
    #   client = BSV::Auth::AuthFetch.new(wallet: my_wallet)
    #   response = client.fetch('https://api.example.com/resource')
    #   puts response.status   # => 200
    #   puts response.body     # => "..."
    class AuthFetch
      DEFAULT_TIMEOUT = 30

      # @param wallet [BSV::Wallet::Interface] wallet for crypto operations
      # @param requested_certificates [Hash, nil] certificate set to request from peers
      # @param session_manager [SessionManager, nil] optional shared session store
      def initialize(wallet:, requested_certificates: nil, session_manager: nil)
        @wallet                 = wallet
        @requested_certificates = requested_certificates
        @session_manager        = session_manager
        @peers                  = {}
        @peers_mutex            = Mutex.new
      end

      # Sends an authenticated HTTP request to +url+.
      #
      # The first request to a new base URL performs a BRC-103 mutual-auth
      # handshake automatically. Subsequent requests reuse the cached peer.
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
      def fetch(url, method: 'GET', headers: {}, body: nil, timeout: DEFAULT_TIMEOUT)
        do_fetch(url, method: method, headers: headers, body: body, timeout: timeout, retry_count: 0)
      end

      private

      def do_fetch(url, method:, headers:, body:, timeout:, retry_count:)
        uri      = URI.parse(url)
        base_url = extract_base_url(uri)
        path     = uri.path.empty? ? '/' : uri.path
        query    = uri.query ? "?#{uri.query}" : nil

        peer = get_or_create_peer(base_url)

        # Validate and filter headers (raises ArgumentError for unsupported headers)
        filtered_headers = AuthHeaders.filter_request_headers(headers)

        # Normalise body: Hash → JSON string, set content-type if not already set
        effective_body, filtered_headers = normalise_body(body, method, filtered_headers)

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
                                 timeout: timeout, retry_count: retry_count + 1)
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
        AuthResponse.new(
          status: data[:status],
          headers: pairs_to_hash(data[:headers]),
          body: data[:body] || '',
          identity_key: result[:identity_key]
        )
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
      # - nil body + body-carrying method + JSON content-type → defaults to '{}'
      # - String body → used as-is
      #
      # Returns [normalised_body, updated_filtered_headers].
      def normalise_body(body, _method, filtered_headers)
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
