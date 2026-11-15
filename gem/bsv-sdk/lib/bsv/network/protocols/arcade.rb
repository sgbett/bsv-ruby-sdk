# frozen_string_literal: true

require 'json'

module BSV
  module Network
    module Protocols
      # BSV Broadcaster (formerly Arcade) client for submitting Extended Format transactions and tracking their status.
      #
      # Written against BSV Broadcaster v0.21. The service was renamed from Arcade in v0.19.0; the Ruby class keeps
      # the old name. It is a sibling of {ARC} rather than a subclass: the response schema is now ARC-compatible, but
      # the request side differs. Paths sit at the root (no +/v1+), only Extended Format is accepted (never plain
      # hex or BEEF), the header set is smaller, errors are flat +{error, reason}+ objects, and 503 and 429 signal
      # backpressure. Sharing a base class would hide those differences behind conditionals.
      #
      # == Example
      #
      #   broadcaster = BSV::Network::Protocols::Arcade.new(
      #     base_url: 'https://arcade-v2-us-1.bsvblockchain.tech'
      #   )
      #   result = broadcaster.call(:broadcast, tx)
      #   result.http_success? # => true
      #   result.data['txStatus'] # => "RECEIVED"
      #
      # @see https://github.com/bsv-blockchain/broadcaster BSV Broadcaster repository
      class Arcade < Protocol
        endpoint :broadcast,     :post, '/tx',        response: :json
        endpoint :get_tx_status, :get,  '/tx/{txid}', response: :json
        endpoint :get_policy,    :get,  '/policy',    response: :json
        endpoint :health,        :get,  '/health',    response: :json

        RETRY_AFTER_SECONDS = /\A\d{1,6}\z/

        # @param base_url    [String]      BSV Broadcaster base URL
        # @param api_key     [String, nil] legacy bearer token shorthand
        # @param auth        [Hash, Symbol, nil] auth config; takes precedence over +api_key:+
        # @param network     [String, nil] network name for base URL interpolation
        # @param http_client [#request, nil] injectable HTTP client for testing
        # @param callback_url   [String, nil] optional X-CallbackUrl header value
        # @param callback_token [String, nil] optional X-CallbackToken header value
        def initialize(base_url:, api_key: nil, auth: nil, network: nil, http_client: nil,
                       callback_url: nil, callback_token: nil)
          super(base_url: base_url, api_key: api_key, auth: auth, network: network, http_client: http_client)
          @callback_url   = callback_url
          @callback_token = callback_token
        end

        private

        # Submits an Extended Format transaction, reporting backpressure, validation failures and rejections as failed responses.
        #
        # No trailing +**+: the former +skip_fee_validation:+ and +skip_script_validation:+ keywords are no longer
        # accepted by the service and raise +ArgumentError+ here.
        #
        # @param tx [#to_ef_hex, String] transaction object, Extended Format hex or binary Extended Format
        # @param callback_url          [String, nil] overrides the constructor value
        # @param callback_token        [String, nil] overrides the constructor value
        # @param full_status_updates   [Boolean, nil] request a callback for every status change
        # @return [ProtocolResponse]
        # @raise [ArgumentError] if +tx+ is not in Extended Format; nothing is sent
        def call_broadcast(tx, callback_url: nil, callback_token: nil, full_status_updates: nil)
          body = JSON.generate(rawTx: BSV::Network::Util.resolve_ef_hex(tx))

          extra_headers = build_broadcast_headers(
            callback_url: callback_url || @callback_url,
            callback_token: callback_token || @callback_token,
            full_status_updates: full_status_updates
          )

          uri     = URI("#{@base_url}#{self.class.endpoints[:broadcast][:path]}")
          request = build_request(:post, uri, body)
          extra_headers.each { |k, v| request[k] = v }

          parse_broadcast_response(execute(uri, request))
        end

        # Fetches a transaction's status, reporting rejected statuses and malformed bodies as failed responses.
        #
        # @param txid [String] display-order hex transaction ID
        # @return [ProtocolResponse]
        # @raise [ArgumentError] if +txid+ is not 64-char display-order hex
        def call_get_tx_status(txid)
          BSV::Primitives::Hex.validate_dtxid_hex!(txid, name: 'txid')
          response = default_call(:get_tx_status, txid)
          return response if response.code.nil?
          return response.with(error_message: status_error_message(response)) unless response.http_success?

          validate_accepted_body(response)
        end

        def build_broadcast_headers(callback_url:, callback_token:, full_status_updates:)
          headers = {}
          headers['X-CallbackUrl']       = callback_url   if callback_url
          headers['X-CallbackToken']     = callback_token if callback_token
          headers['X-FullStatusUpdates'] = 'true'         if full_status_updates
          headers
        end

        def parse_broadcast_response(response)
          code = response.code.to_i
          body = parse_json_object(response.body)

          return backpressure_response(response, code, body) if [429, 503].include?(code)

          unless (200..299).cover?(code)
            return ProtocolResponse.new(response, http_success: false,
                                                  error_message: http_error_message(code, body), data: body)
          end

          validate_accepted_body(ProtocolResponse.new(response, data: body))
        end

        def backpressure_response(response, code, body)
          message = code == 503 ? 'BSV Broadcaster backpressure (HTTP 503)' : 'BSV Broadcaster rate limit (HTTP 429)'
          retry_after = response['Retry-After'].to_s.strip
          message += "; retry after #{retry_after}s" if retry_after.match?(RETRY_AFTER_SECONDS)
          ProtocolResponse.new(response, http_success: false, error_message: message, data: body)
        end

        # Non-2xx bodies are +{error, reason}+ objects; anything else (an HTML error page, say) is never echoed.
        def http_error_message(code, body)
          return "HTTP #{code}" unless body

          service_text(body['error'], body['reason']) || service_text(body['detail']) ||
            service_text(body['title']) || "HTTP #{code}"
        end

        # Applies the checks shared by broadcast and status 2xx responses: an object with a txid, then rejection.
        #
        # ARC's +extraInfo+ orphan heuristic is deliberately not applied. The Broadcaster writes free-text upstream
        # errors into +extraInfo+ on retryable +PENDING_RETRY+ rows and uses reorg wording on +MINED+ rows, so
        # matching on it would report accepted transactions as rejected.
        def validate_accepted_body(response)
          body = response.data
          unless body.is_a?(Hash) && valid_txid?(body['txid'])
            return response.with(http_success: false, data: nil,
                                 error_message: 'BSV Broadcaster returned a malformed 2xx response')
          end

          return response unless ARC.rejected_tx_status?(body['txStatus'])

          response.with(http_success: false, error_message: ARC.rejection_message(body))
        end

        def status_error_message(response)
          http_error_message(response.code, parse_json_object(response.body))
        end

        def service_text(*parts)
          texts = parts.filter_map { |part| BSV::Network::Util.service_text(part) }
          texts.join(': ') unless texts.empty?
        end

        def valid_txid?(txid)
          txid.is_a?(String) && txid.match?(/\A\h{64}\z/)
        end

        def parse_json_object(raw)
          body = JSON.parse(raw.to_s)
          body.is_a?(Hash) ? body : nil
        rescue JSON::ParserError, EncodingError
          nil
        end
      end
    end
  end
end
