# frozen_string_literal: true

require 'json'

module BSV
  module Network
    module Protocols
      # Arcade protocol implementation for submitting transactions to the BSV network.
      #
      # Arcade is a sibling to ARC — both subclass Protocol directly. The request
      # and response shapes diverge enough to rule out a shared abstract base:
      # Arcade uses a narrower status taxonomy and a different broadcast response
      # structure (no txid on fresh submission; idempotent re-submit returns
      # status plus txid plus state).
      #
      # == Example
      #
      #   arcade = BSV::Network::Protocols::Arcade.new(
      #     base_url: 'https://arcade.gorillapool.io'
      #   )
      #   result = arcade.call(:broadcast, tx)
      #   result.http_success? # => true
      #   result.data['status'] # => "submitted"
      #
      # @see https://github.com/bsv-blockchain/arcade Arcade repository
      class Arcade < Protocol
        # Arcade response statuses that indicate a transaction was NOT accepted.
        # Narrower than ARC's taxonomy — Arcade has a single explicit rejection signal.
        REJECTED_STATUSES = %w[REJECTED].freeze

        endpoint :broadcast,     :post, '/tx',        response: :json
        endpoint :get_tx_status, :get,  '/tx/{txid}', response: :json
        endpoint :health,        :get,  '/health',    response: :json

        # @param base_url    [String]      Arcade base URL
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

        # Broadcast escape hatch: Arcade-specific headers and response shape.
        #
        # @param tx [#to_ef_hex, #to_hex, String] transaction object, hex string,
        #   or binary string
        # @param callback_url          [String, nil]
        # @param callback_token        [String, nil]
        # @param full_status_updates   [Boolean, nil]
        # @param skip_fee_validation   [Boolean, nil]
        # @param skip_script_validation [Boolean, nil]
        # @return [ProtocolResponse]
        def call_broadcast(tx, callback_url: nil, callback_token: nil,
                           full_status_updates: nil, skip_fee_validation: nil,
                           skip_script_validation: nil, **)
          hex  = BSV::Network::Util.resolve_tx_hex(tx)
          body = JSON.generate(rawTx: hex)

          extra_headers = build_broadcast_headers(
            callback_url: callback_url || @callback_url,
            callback_token: callback_token || @callback_token,
            full_status_updates: full_status_updates,
            skip_fee_validation: skip_fee_validation,
            skip_script_validation: skip_script_validation
          )

          path     = self.class.endpoints[:broadcast][:path]
          uri      = URI("#{@base_url}#{path}")
          request  = build_request(:post, uri, body)
          extra_headers.each { |k, v| request[k] = v }
          response = execute(uri, request)

          parse_broadcast_response(response)
        end

        # get_tx_status: pass-through to default_call plus rejection check.
        #
        # @param txid [String] display-order hex transaction ID
        # @return [ProtocolResponse]
        def call_get_tx_status(txid, **)
          response = default_call(:get_tx_status, txid)
          return response unless response.http_success?

          body = response.data
          return response unless body.is_a?(Hash)

          if rejected_status?(body)
            return response.with(
              http_success: false,
              error_message: body['txStatus'] || 'REJECTED'
            )
          end

          response
        end

        def build_broadcast_headers(callback_url:, callback_token:, full_status_updates:,
                                    skip_fee_validation:, skip_script_validation:)
          headers = {}
          headers['X-CallbackUrl']          = callback_url if callback_url
          headers['X-CallbackToken']        = callback_token if callback_token
          headers['X-FullStatusUpdates']    = 'true'                if full_status_updates
          headers['X-SkipFeeValidation']    = 'true'                if skip_fee_validation
          headers['X-SkipScriptValidation'] = 'true'                if skip_script_validation
          headers
        end

        def parse_broadcast_response(response)
          code = response.code.to_i

          if code == 503
            retry_after = response['Retry-After']
            msg = retry_after ? "Arcade backpressure; retry after #{retry_after}s" : 'Arcade backpressure'
            return ProtocolResponse.new(response, http_success: false, error_message: msg)
          end

          unless (200..299).cover?(code)
            body = BSV::Network::Util.safe_parse_json(response.body)
            return ProtocolResponse.new(
              response,
              http_success: false,
              error_message: body.is_a?(Hash) ? (body['reason'] || body['detail'] || "HTTP #{code}") : "HTTP #{code}"
            )
          end

          body = BSV::Network::Util.safe_parse_json(response.body)

          unless body.is_a?(Hash)
            return ProtocolResponse.new(
              response,
              http_success: false,
              error_message: 'Arcade returned a malformed 2xx response'
            )
          end

          status = body['status']
          unless status
            return ProtocolResponse.new(
              response,
              http_success: false,
              error_message: 'Arcade returned a malformed 2xx response'
            )
          end

          ProtocolResponse.new(response, data: body)
        end

        def rejected_status?(body)
          tx_status = body['txStatus'].to_s.upcase
          REJECTED_STATUSES.include?(tx_status)
        end
      end
    end
  end
end
