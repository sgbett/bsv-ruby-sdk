# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require 'securerandom'

module BSV
  module Network
    module Providers
      # ARC provider implementing broadcast, broadcast_many, get_tx_status, and get_policy
      # using the Result-based return convention from {BSV::Network::Provider}.
      #
      # This is distinct from {BSV::Network::ARC}, which raises exceptions. This provider
      # returns {BSV::Network::Result} objects so it can be composed with the Registry.
      #
      # @example
      #   provider = BSV::Network::Providers::ARC.new(api_key: 'my-key')
      #   result = provider.call(:broadcast, tx)
      #   result.success? # => true
      #   result.data     # => { txid: '...', status: '...', extra_info: nil }
      class ARC < BSV::Network::Provider
        provides :broadcast, :broadcast_many, :get_tx_status, :get_policy

        # ARC response statuses that indicate the transaction was NOT accepted.
        # Matches the behaviour of {BSV::Network::ARC::REJECTED_STATUSES}.
        REJECTED_STATUSES = %w[
          REJECTED
          DOUBLE_SPEND_ATTEMPTED
          INVALID
          MALFORMED
          MINED_IN_STALE_BLOCK
        ].freeze

        # Substring matched case-insensitively against txStatus and extraInfo.
        ORPHAN_MARKER = 'ORPHAN'

        # @param url [String] ARC base URL (without trailing slash);
        #   defaults to {BSV::MAINNET_URL} (GorillaPool ARCADE endpoint)
        # @param api_key [String, nil] optional bearer token for Authorization header
        # @param deployment_id [String, nil] optional deployment identifier for
        #   the +XDeployment-ID+ header; defaults to a per-instance random value
        # @param callback_url [String, nil] optional +X-CallbackUrl+ for ARC status callbacks
        # @param callback_token [String, nil] optional +X-CallbackToken+ for callback auth
        # @param http_client [#request, nil] injectable HTTP client for testing
        def initialize(url: BSV::MAINNET_URL, api_key: nil, deployment_id: nil,
                       callback_url: nil, callback_token: nil, http_client: nil)
          super(http_client: http_client)
          @url = url.chomp('/')
          @api_key = api_key
          @deployment_id = deployment_id || "bsv-ruby-sdk-#{SecureRandom.hex(8)}"
          @callback_url = callback_url
          @callback_token = callback_token
        end

        private

        # Submit a single transaction to ARC.
        #
        # Prefers Extended Format (BRC-30) hex when available; falls back to plain hex.
        #
        # @param tx [Transaction] the transaction to broadcast
        # @param wait_for [String, nil] ARC wait condition
        # @param skip_fee_validation [Boolean, nil] send +X-SkipFeeValidation: true+ header
        # @param skip_script_validation [Boolean, nil] send +X-SkipScriptValidation: true+ header
        # @return [Result::Success, Result::Error]
        def call_broadcast(tx, wait_for: nil, skip_fee_validation: nil, skip_script_validation: nil)
          uri = URI("#{@url}/v1/tx")
          request = build_post_request(uri, wait_for: wait_for,
                                            skip_fee_validation: skip_fee_validation,
                                            skip_script_validation: skip_script_validation)
          request.body = JSON.generate(rawTx: raw_tx_hex(tx))

          response = execute(uri, request)
          parse_single_broadcast_response(response)
        end

        # Submit multiple transactions to ARC in a single batch request.
        #
        # Returns a success wrapping an array; each element is either
        # +{ txid:, status: }+ or a nested +Result::Error+ for rejected items.
        #
        # @param txs [Array<Transaction>] transactions to broadcast
        # @param wait_for [String, nil] ARC wait condition
        # @param skip_fee_validation [Boolean, nil] send +X-SkipFeeValidation: true+ header
        # @param skip_script_validation [Boolean, nil] send +X-SkipScriptValidation: true+ header
        # @return [Result::Success, Result::Error]
        def call_broadcast_many(txs, wait_for: nil, skip_fee_validation: nil, skip_script_validation: nil)
          return success([]) if txs.empty?

          uri = URI("#{@url}/v1/txs")
          request = build_post_request(uri, wait_for: wait_for,
                                            skip_fee_validation: skip_fee_validation,
                                            skip_script_validation: skip_script_validation)
          request.body = JSON.generate(txs.map { |tx| { rawTx: raw_tx_hex(tx) } })

          response = execute(uri, request)
          parse_batch_response(response)
        end

        # Query the ARC broadcast status of a previously submitted transaction.
        #
        # @param txid [String] the transaction identifier
        # @return [Result::Success, Result::NotFound, Result::Error]
        def call_get_tx_status(txid)
          uri = URI("#{@url}/v1/tx/#{txid}")
          request = Net::HTTP::Get.new(uri)
          request['XDeployment-ID'] = @deployment_id
          apply_auth_header(request)

          response = execute(uri, request)
          code = response.code.to_i

          return not_found if code == 404

          body = parse_json(response.body)

          unless (200..299).cover?(code)
            msg = body['detail'] || body['title'] || "HTTP #{code}"
            return error(msg, retryable: retryable_code?(code))
          end

          success(
            txid: body['txid'],
            tx_status: body['txStatus'],
            block_hash: body['blockHash'],
            block_height: body['blockHeight']
          )
        end

        # Fetch the current ARC miner policy (fee rates, script limits, etc.).
        #
        # @return [Result::Success, Result::Error]
        def call_get_policy
          uri = URI("#{@url}/v1/policy")
          request = Net::HTTP::Get.new(uri)
          request['XDeployment-ID'] = @deployment_id
          apply_auth_header(request)

          response = execute(uri, request)
          code = response.code.to_i
          body = parse_json(response.body)

          unless (200..299).cover?(code)
            msg = body['detail'] || body['title'] || "HTTP #{code}"
            return error(msg, retryable: retryable_code?(code))
          end

          success(policy: body['policy'])
        end

        # Prefer Extended Format (BRC-30) hex so ARC can validate sighashes without
        # fetching parent transactions. Falls back to plain raw-tx hex when any input
        # lacks source_satoshis / source_locking_script.
        def raw_tx_hex(tx)
          tx.to_ef_hex
        rescue ArgumentError
          tx.to_hex
        end

        def build_post_request(uri, wait_for: nil, skip_fee_validation: nil, skip_script_validation: nil)
          request = Net::HTTP::Post.new(uri)
          request['Content-Type'] = 'application/json'
          request['XDeployment-ID'] = @deployment_id
          request['X-WaitFor'] = wait_for if wait_for
          request['X-CallbackUrl'] = @callback_url if @callback_url
          request['X-CallbackToken'] = @callback_token if @callback_token
          request['X-SkipFeeValidation'] = 'true' if skip_fee_validation
          request['X-SkipScriptValidation'] = 'true' if skip_script_validation
          apply_auth_header(request)
          request
        end

        def apply_auth_header(request)
          request['Authorization'] = "Bearer #{@api_key}" if @api_key
        end

        def execute(uri, request)
          if @http_client
            @http_client.request(uri, request)
          else
            Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
              http.request(request)
            end
          end
        end

        def parse_single_broadcast_response(response)
          code = response.code.to_i
          body = parse_json(response.body)

          unless (200..299).cover?(code)
            msg = body['detail'] || body['title'] || "HTTP #{code}"
            return error(msg, retryable: retryable_code?(code))
          end

          if rejected_status?(body)
            msg = body['detail'] || body['title'] || body['txStatus']
            arc_status = body['txStatus'].to_s.upcase
            return error(msg, retryable: false, metadata: { arc_status: arc_status, txid: body['txid'] })
          end

          return error('ARC returned a malformed 2xx response', retryable: false) unless body['txid']

          success(
            txid: body['txid'],
            status: body['txStatus'],
            extra_info: body['extraInfo']
          )
        end

        def parse_batch_response(response)
          code = response.code.to_i
          body = parse_json(response.body)

          unless (200..299).cover?(code)
            msg = body['detail'] || body['title'] || "HTTP #{code}"
            return error(msg, retryable: retryable_code?(code))
          end

          return error('ARC returned a malformed batch response', retryable: false) unless body.is_a?(Array)

          items = body.map { |item| build_batch_item(item) }
          success(items)
        end

        def build_batch_item(item)
          if rejected_status?(item)
            msg = item['detail'] || item['title'] || item['txStatus']
            error(msg, retryable: false)
          elsif !item['txid']
            error('ARC returned a malformed 2xx response', retryable: false)
          else
            { txid: item['txid'], status: item['txStatus'] }
          end
        end

        def rejected_status?(body)
          tx_status = body['txStatus'].to_s.upcase
          return true if REJECTED_STATUSES.include?(tx_status)
          return true if tx_status.include?(ORPHAN_MARKER)

          extra_info = body['extraInfo'].to_s.upcase
          extra_info.include?(ORPHAN_MARKER)
        end

        def parse_json(raw)
          JSON.parse(raw)
        rescue JSON::ParserError
          { 'detail' => raw }
        end

        def retryable_code?(code)
          code == 429 || code >= 500
        end
      end
    end
  end
end
