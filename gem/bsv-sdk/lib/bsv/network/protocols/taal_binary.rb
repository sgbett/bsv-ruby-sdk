# frozen_string_literal: true

module BSV
  module Network
    module Protocols
      # TAALBinary implements the TAAL broadcast API using raw binary transaction
      # submission over HTTP.
      #
      # TAAL quirks handled here:
      # - Content-Type is +application/octet-stream+ (not JSON)
      # - Authorization header uses the API key directly with no "Bearer" prefix
      # - A response containing +txn-already-known+ in the error field is treated
      #   as success (the transaction is already in the mempool — idempotent)
      #
      # == Example
      #
      #   protocol = BSV::Network::Protocols::TAALBinary.new(
      #     base_url: 'https://api.taal.com',
      #     api_key: 'mainnet_your_key_here'
      #   )
      #   result = protocol.call(:broadcast, tx)
      #   puts result.data[:txid] if result.success?
      class TAALBinary < BSV::Network::Protocol
        endpoint :broadcast, :post, '/api/v1/broadcast', response: :json

        private

        # Escape hatch for broadcast: sends raw binary transaction bytes with
        # TAAL-specific headers and applies TAAL-specific response quirk handling.
        #
        # @param tx [#to_binary, String] transaction object or raw binary string
        # @return [Result::Success, Result::Error]
        def call_broadcast(tx)
          body = tx.respond_to?(:to_binary) ? tx.to_binary : tx

          uri     = URI("#{@base_url}/api/v1/broadcast")
          request = Net::HTTP::Post.new(uri)
          request['Content-Type']  = 'application/octet-stream'
          request['Authorization'] = @api_key if @api_key

          request.body = body

          response = execute(uri, request)
          parse_broadcast_response(response)
        end

        # Maps the HTTP response from TAAL broadcast to a Result, applying the
        # +txn-already-known+ idempotency quirk.
        #
        # @param response [Net::HTTPResponse]
        # @return [Result::Success, Result::Error]
        def parse_broadcast_response(response)
          code = response.code.to_i
          body = parse_json_body(response.body)

          return Result::Success.new(data: { txid: body['txid'] }) if already_known?(body) && body['txid']

          retryable = code == 429 || (500..599).cover?(code)

          if (200..299).cover?(code)
            return Result::Error.new(message: 'TAAL returned a malformed 2xx response', retryable: false) unless body['txid']

            Result::Success.new(data: { txid: body['txid'] })
          else
            message = (body.is_a?(Hash) && body['error']) || "HTTP #{code}"
            Result::Error.new(message: message, retryable: retryable)
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
