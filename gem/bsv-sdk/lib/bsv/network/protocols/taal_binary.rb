# frozen_string_literal: true

module BSV
  module Network
    module Protocols
      # TAALBinary implements the TAAL broadcast API using raw binary transaction
      # submission over HTTP.
      #
      # TAAL quirks handled here:
      # - Content-Type is +application/octet-stream+ (not JSON)
      # - Authorization header is applied via the standard +apply_auth+ mechanism
      # - A response containing +txn-already-known+ in the error field is treated
      #   as success (the transaction is already in the mempool — idempotent)
      #
      # == Example
      #
      #   protocol = BSV::Network::Protocols::TAALBinary.new(
      #     base_url: 'https://api.taal.com',
      #     auth: { api_key: 'mainnet_your_key_here' }
      #   )
      #   result = protocol.call(:broadcast, tx)
      #   puts result.data[:txid] if result.http_success?
      #
      # @see https://docs.taal.com TAAL API documentation
      class TAALBinary < BSV::Network::Protocol
        endpoint :broadcast, :post, '/api/v1/broadcast', response: :json

        # @param base_url    [String] base URL for the TAAL binary API
        # @param api_key     [String, nil] legacy API key shorthand (no Bearer prefix) — use +auth:+ for new code
        # @param auth        [Hash, Symbol, nil] auth config; takes precedence over +api_key:+
        # @param http_client [Object, nil] injectable HTTP client for testing
        def initialize(base_url:, api_key: nil, auth: nil, http_client: nil)
          # Translate legacy api_key: to auth: { api_key: } so the base class sends
          # the raw key without a Bearer prefix, matching TAAL's expected auth format.
          resolved_auth = auth || (api_key ? { api_key: api_key } : nil)
          super(base_url: base_url, auth: resolved_auth, http_client: http_client)
        end

        private

        # Escape hatch for broadcast: sends raw binary transaction bytes with
        # TAAL-specific headers and applies TAAL-specific response quirk handling.
        #
        # @param tx [#to_binary, String] transaction object or raw binary string
        # @return [ProtocolResponse]
        def call_broadcast(tx)
          body = tx.respond_to?(:to_binary) ? tx.to_binary : tx

          uri     = URI("#{@base_url}/api/v1/broadcast")
          request = Net::HTTP::Post.new(uri)
          request['Content-Type'] = 'application/octet-stream'
          apply_auth(request)

          request.body = body

          response = execute(uri, request)
          parse_broadcast_response(response)
        end

        # Maps the HTTP response from TAAL broadcast to a ProtocolResponse, applying
        # the +txn-already-known+ idempotency quirk.
        #
        # @param response [Net::HTTPResponse]
        # @return [ProtocolResponse]
        def parse_broadcast_response(response)
          code = response.code.to_i
          body = parse_json_body(response.body)

          # TAAL API boundary: display-order hex txid from the TAAL broadcast response.
          # The HTTP response class is non-2xx here, so we must pass http_success: true explicitly.
          return ProtocolResponse.new(response, data: { txid: body['txid'] }, http_success: true) if already_known?(body) && body['txid']

          if (200..299).cover?(code)
            return ProtocolResponse.new(response, http_success: false, error_message: 'TAAL returned a malformed 2xx response') unless body['txid']

            ProtocolResponse.new(response, data: { txid: body['txid'] })
          else
            message = (body.is_a?(Hash) && body['error']) || "HTTP #{code}"
            ProtocolResponse.new(response, http_success: false, error_message: message)
          end
        end

        # Returns true when the response body indicates the transaction is already
        # known to the network — TAAL treats this as a non-error.
        #
        # @param body [Hash, nil]
        # @return [Boolean]
        def already_known?(body)
          body.is_a?(Hash) &&
            body['error'].is_a?(String) &&
            body['error'].include?('txn-already-known')
        end

        # Parses a JSON response body, returning an empty Hash on failure or nil input.
        #
        # Always returns a Hash so callers can safely index the result without
        # a nil-guard.
        #
        # @param raw [String, nil]
        # @return [Hash]
        def parse_json_body(raw)
          return {} if raw.nil? || raw.empty?

          parsed = JSON.parse(raw)
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError
          {}
        end
      end
    end
  end
end
