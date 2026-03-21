# frozen_string_literal: true

require 'net/http'
require 'uri'

module BSV
  module X402
    # HTTP client wrapper that automatically handles x402 Payment Required
    # responses.
    #
    # When a request returns HTTP 402, the client:
    #   1. Decodes the +X402-Challenge+ header to obtain the payment challenge.
    #   2. Builds a payment transaction using {TransactionBuilder}.
    #   3. Broadcasts the transaction via the configured broadcaster (if any).
    #   4. Builds a {Proof} and encodes it as the +X402-Proof+ header.
    #   5. Retries the original request with the proof attached.
    #   6. Returns the response from the retry.
    #
    # == HTTP client injection
    #
    # The client is HTTP-library agnostic. By default it uses +Net::HTTP+. A
    # custom callable may be injected via the +http_client:+ parameter:
    #
    #   my_http = ->(method, url, headers, body) { [status, headers, body] }
    #   client = BSV::X402::Client.new(http_client: my_http, ...)
    #
    # == Funding UTXOs
    #
    # Each element in +funding_utxos+ must be a hash with:
    #   { txid:, vout:, satoshis:, locking_script_hex:, private_key: }
    #
    # == Nonce unlocker
    #
    # The nonce UTXO is server-issued and must be spent in the payment
    # transaction. The +nonce_unlocker+ parameter is a callable that returns
    # the unlocking script for the nonce input:
    #
    #   nonce_unlocker = ->(tx, idx) { BSV::Transaction::P2PKH.new(key).sign(tx, idx) }
    #
    # == Configuration
    #
    # The broadcaster is read from +BSV::X402.configuration.broadcaster+ unless
    # overridden in the constructor.
    class Client
      # Default maximum number of payment attempts per request.
      DEFAULT_MAX_RETRIES = 1

      # @return [Integer] configured maximum retry attempts
      attr_reader :max_retries

      # @return [Boolean] whether auto-pay is enabled
      attr_reader :auto_pay

      # @param funding_utxos [Array<Hash>] UTXOs for payment funding
      # @param nonce_unlocker [#call] callable that unlocks the nonce UTXO input
      # @param change_locking_script_hex [String, nil] change output script
      # @param broadcaster [#broadcast, nil] broadcaster to use (overrides config)
      # @param http_client [#call, nil] injectable HTTP callable; defaults to Net::HTTP
      # @param max_retries [Integer] maximum payment retries (default: 1)
      # @param auto_pay [Boolean] whether to auto-pay 402 responses (default: true)
      def initialize(
        funding_utxos:,
        nonce_unlocker:,
        change_locking_script_hex: nil,
        broadcaster: :use_config,
        http_client: nil,
        max_retries: DEFAULT_MAX_RETRIES,
        auto_pay: true
      )
        @funding_utxos             = funding_utxos
        @nonce_unlocker            = nonce_unlocker
        @change_locking_script_hex = change_locking_script_hex
        @broadcaster               = broadcaster == :use_config ? BSV::X402.configuration.broadcaster : broadcaster
        @http_client               = http_client || method(:default_http_request)
        @max_retries               = max_retries
        @auto_pay                  = auto_pay
      end

      # Make a GET request, automatically handling 402 responses.
      #
      # @param url [String] the URL to request
      # @param headers [Hash] additional request headers
      # @return [Array] +[status, headers, body]+
      def get(url, headers: {})
        request('GET', url, headers: headers)
      end

      # Make a POST request, automatically handling 402 responses.
      #
      # @param url [String] the URL to request
      # @param body [String, nil] request body
      # @param headers [Hash] additional request headers
      # @return [Array] +[status, headers, body]+
      def post(url, body: nil, headers: {})
        request('POST', url, headers: headers, body: body)
      end

      # Make an HTTP request, automatically handling 402 Payment Required.
      #
      # @param method [String] HTTP method (e.g. 'GET', 'POST')
      # @param url [String] full URL
      # @param headers [Hash] request headers
      # @param body [String, nil] request body
      # @return [Array] +[status, headers, body]+ from the final response
      # @raise [ChallengeExpiredError] if the challenge has already expired
      # @raise [InsufficientFundsError] if funding UTXOs cannot cover the payment
      def request(method, url, headers: {}, body: nil)
        status, resp_headers, resp_body = @http_client.call(method, url, headers, body)

        return [status, resp_headers, resp_body] unless status == 402
        return [status, resp_headers, resp_body] unless @auto_pay

        handle_payment(method, url, headers, body, resp_headers, attempts: 0)
      end

      private

      # Handle a 402 response by building a payment and retrying.
      #
      # @param method [String]
      # @param url [String]
      # @param req_headers [Hash] original request headers
      # @param body [String, nil] original request body
      # @param resp_headers [Hash] headers from the 402 response
      # @param attempts [Integer] number of payment attempts so far
      # @return [Array] +[status, headers, body]+
      def handle_payment(method, url, req_headers, body, resp_headers, attempts:)
        raise PaymentRetryExhaustedError, "max retries (#{@max_retries}) exceeded" if attempts >= @max_retries

        challenge_header = header_value(resp_headers, 'x402-challenge')
        raise ValidationError, 'server returned 402 without X402-Challenge header' if challenge_header.nil?

        challenge = Challenge.from_header(challenge_header)

        # Build the request-binding fields for the proof.
        request_info = build_request_info(method, url, req_headers, body)

        # Build and broadcast the payment transaction.
        tx = TransactionBuilder.build(
          challenge: challenge,
          funding_utxos: @funding_utxos,
          nonce_unlocker: @nonce_unlocker,
          change_locking_script_hex: @change_locking_script_hex
        )

        @broadcaster&.broadcast(tx)

        # Build the proof and encode it into the retry request headers.
        proof = ProofBuilder.build(
          challenge: challenge,
          transaction: tx,
          request: request_info
        )

        retry_headers = req_headers.merge('X402-Proof' => proof.to_header)
        status, resp_headers2, resp_body2 = @http_client.call(method, url, retry_headers, body)

        return [status, resp_headers2, resp_body2] unless status == 402

        # Another 402 — recurse with incremented attempt count.
        handle_payment(method, url, retry_headers, body, resp_headers2, attempts: attempts + 1)
      end

      # Build the request-binding hash for use in {ProofBuilder}.
      #
      # Computes the canonical hashes of the request headers and body that were
      # sent with the original request.
      #
      # @param method [String]
      # @param url [String]
      # @param headers [Hash]
      # @param body [String, nil]
      # @return [Hash]
      def build_request_info(method, url, headers, body)
        uri = URI.parse(url)
        {
          method: method.upcase,
          path: uri.path,
          query: uri.query.to_s,
          req_headers_sha256: RequestBinding.compute_headers_hash(headers),
          req_body_sha256: RequestBinding.compute_body_hash(body)
        }
      end

      # Retrieve a header value case-insensitively from a response header hash.
      #
      # @param headers [Hash] response headers
      # @param name [String] lowercase header name to look up
      # @return [String, nil] the header value, or nil if not present
      def header_value(headers, name)
        return nil if headers.nil?

        headers.each do |key, value|
          return value if key.to_s.downcase == name
        end
        nil
      end

      # Default HTTP request implementation using Ruby's +Net::HTTP+.
      #
      # @param method [String] HTTP method
      # @param url [String] full URL
      # @param headers [Hash] request headers
      # @param body [String, nil] request body
      # @return [Array] +[Integer, Hash, String]+ status, headers, body
      def default_http_request(method, url, headers, body)
        uri = URI.parse(url)

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
          req_class = Net::HTTP.const_get(method.capitalize)
          req = req_class.new(uri.request_uri)
          headers.each { |k, v| req[k] = v }
          req.body = body if body

          response = http.request(req)
          resp_headers = response.each_header.to_h
          [response.code.to_i, resp_headers, response.body]
        end
      end
    end
  end
end
