# frozen_string_literal: true

require 'json'
require 'securerandom'

module BSV
  module Network
    module Protocols
      # ARC protocol implementation for submitting transactions to the BSV network.
      #
      # Extends Protocol with five endpoints and two escape hatches for broadcast
      # logic: EF format preference, rejection detection, and custom headers.
      #
      # The protocol returns Result objects (never raises). The facade layer
      # (Phase D) is responsible for translating Results to BroadcastResponse /
      # BroadcastError as needed by consumer code.
      #
      # == Example
      #
      #   arc = BSV::Network::Protocols::ARC.new(
      #     base_url: 'https://arc.taal.com',
      #     api_key: 'my-api-key'
      #   )
      #   result = arc.call(:broadcast, tx)
      #   result.success? # => true
      #   result.data[:txid] # => "abc123..."
      class ARC < Protocol
        # ARC response statuses that indicate a transaction was NOT accepted.
        # Matches the TypeScript SDK's ARC broadcaster failure set.
        REJECTED_STATUSES = %w[
          REJECTED
          DOUBLE_SPEND_ATTEMPTED
          INVALID
          MALFORMED
          MINED_IN_STALE_BLOCK
        ].freeze

        # Substring marker for orphan detection in txStatus or extraInfo fields.
        ORPHAN_MARKER = 'ORPHAN'

        endpoint :broadcast,      :post, '/v1/tx',          response: :json
        endpoint :broadcast_many, :post, '/v1/txs',         response: :json_array
        endpoint :get_tx_status,  :get,  '/v1/tx/{txid}',   response: :json
        endpoint :get_policy,     :get,  '/v1/policy',      response: :json
        endpoint :health,         :get,  '/v1/health',      response: :json

        # @param base_url      [String]      ARC base URL (may contain {network})
        # @param api_key       [String, nil] optional bearer token
        # @param network       [String, nil] network name for base URL interpolation
        # @param deployment_id [String, nil] deployment identifier for the
        #   XDeployment-ID header; defaults to a per-instance random hex value
        # @param callback_url  [String, nil] optional X-CallbackUrl header value
        # @param callback_token [String, nil] optional X-CallbackToken header value
        # @param http_client   [#request, nil] injectable HTTP client for testing
        def initialize(base_url:, api_key: nil, network: nil, deployment_id: nil,
                       callback_url: nil, callback_token: nil, http_client: nil)
          super(base_url: base_url, api_key: api_key, network: network, http_client: http_client)
          @deployment_id  = deployment_id || "bsv-ruby-sdk-#{SecureRandom.hex(8)}"
          @callback_url   = callback_url
          @callback_token = callback_token
        end

        private

        # Broadcast escape hatch: EF format preference, custom headers, rejection
        # detection, and malformed 2xx detection.
        #
        # @param tx [Transaction] the transaction to broadcast
        # @param wait_for [String, nil] ARC wait condition
        # @param skip_fee_validation [Boolean, nil]
        # @param skip_script_validation [Boolean, nil]
        # @param skip_tx_validation [Boolean, nil]
        # @param callback_url [String, nil] per-call callback URL override
        # @param callback_token [String, nil] per-call callback token override
        # @param callback_batch [Boolean, nil] when truthy, sends X-CallbackBatch header
        # @return [Result::Success, Result::Error]
        def call_broadcast(tx, wait_for: nil, skip_fee_validation: nil,
                           skip_script_validation: nil, skip_tx_validation: nil,
                           callback_url: nil, callback_token: nil, callback_batch: nil, **)
          hex  = ef_hex_with_fallback(tx)
          body = JSON.generate(rawTx: hex)

          extra_headers = build_broadcast_headers(
            wait_for: wait_for,
            skip_fee_validation: skip_fee_validation,
            skip_script_validation: skip_script_validation,
            skip_tx_validation: skip_tx_validation,
            callback_url: callback_url || @callback_url,
            callback_token: callback_token || @callback_token,
            callback_batch: callback_batch
          )

          response = post_with_headers('/v1/tx', body, extra_headers)
          parse_single_broadcast_response(response)
        end

        # Broadcast-many escape hatch: batch broadcast with per-item rejection detection.
        #
        # @param txs [Array<Transaction>]
        # @param wait_for [String, nil]
        # @param skip_fee_validation [Boolean, nil]
        # @param skip_script_validation [Boolean, nil]
        # @param skip_tx_validation [Boolean, nil]
        # @param callback_url [String, nil]
        # @param callback_token [String, nil]
        # @param callback_batch [Boolean, nil]
        # @return [Result::Success, Result::Error]
        def call_broadcast_many(txs, wait_for: nil, skip_fee_validation: nil,
                                skip_script_validation: nil, skip_tx_validation: nil,
                                callback_url: nil, callback_token: nil, callback_batch: nil, **)
          return Result::Success.new(data: []) if txs.empty?

          body = JSON.generate(txs.map { |tx| { rawTx: ef_hex_with_fallback(tx) } })

          extra_headers = build_broadcast_headers(
            wait_for: wait_for,
            skip_fee_validation: skip_fee_validation,
            skip_script_validation: skip_script_validation,
            skip_tx_validation: skip_tx_validation,
            callback_url: callback_url || @callback_url,
            callback_token: callback_token || @callback_token,
            callback_batch: callback_batch
          )

          response = post_with_headers('/v1/txs', body, extra_headers)
          parse_batch_broadcast_response(response)
        end

        # Prefer Extended Format hex (BRC-30) so ARC can validate sighashes without
        # fetching parent transactions. Falls back to plain raw-tx hex when any input
        # lacks source_satoshis / source_locking_script.
        def ef_hex_with_fallback(tx)
          tx.to_ef_hex
        rescue ArgumentError
          tx.to_hex
        end

        # Build the hash of ARC-specific extra headers.
        def build_broadcast_headers(wait_for:, skip_fee_validation:, skip_script_validation:,
                                    skip_tx_validation:, callback_url:, callback_token:,
                                    callback_batch:)
          headers = { 'XDeployment-ID' => @deployment_id }
          headers['X-WaitFor']              = wait_for                     if wait_for
          headers['X-CallbackUrl']          = callback_url                 if callback_url
          headers['X-CallbackToken']        = callback_token               if callback_token
          headers['X-SkipFeeValidation']    = 'true'                       if skip_fee_validation
          headers['X-SkipScriptValidation'] = 'true'                       if skip_script_validation
          headers['X-SkipTxValidation']     = 'true'                       if skip_tx_validation
          headers['X-CallbackBatch']        = 'true'                       if callback_batch
          headers
        end

        # Perform a POST to the given path with a JSON body plus extra headers.
        # Returns a Net::HTTPResponse-like object.
        def post_with_headers(path, body, extra_headers)
          uri     = URI("#{@base_url}#{path}")
          request = build_request(:post, uri, body)
          extra_headers.each { |k, v| request[k] = v }
          execute(uri, request)
        end

        # Parse and validate a single-transaction ARC response.
        def parse_single_broadcast_response(response)
          code = response.code.to_i
          body = safe_parse_json(response.body)

          unless body.is_a?(Hash)
            return Result::Error.new(
              message: "HTTP #{code}",
              retryable: retryable_code?(code),
              metadata: {}
            )
          end

          unless (200..299).cover?(code)
            return Result::Error.new(
              message: body['detail'] || body['title'] || "HTTP #{code}",
              retryable: retryable_code?(code),
              metadata: { arc_status: body['txStatus'], txid: body['txid'] }
            )
          end

          if rejected_status?(body)
            return Result::Error.new(
              message: body['detail'] || body['title'] || body['txStatus'],
              retryable: false,
              metadata: { arc_status: body['txStatus'].to_s.upcase, txid: body['txid'] }
            )
          end

          unless body['txid']
            return Result::Error.new(
              message: 'ARC returned a malformed 2xx response',
              retryable: false,
              metadata: {}
            )
          end

          Result::Success.new(
            data: {
              txid: body['txid'],
              tx_status: body['txStatus'],
              extra_info: body['extraInfo']
            },
            metadata: { arc_status: body['txStatus'] }
          )
        end

        # Parse and validate a batch ARC response. HTTP-level errors return a
        # single Result::Error; per-item rejections are embedded in the data array.
        def parse_batch_broadcast_response(response)
          code = response.code.to_i
          body = safe_parse_json(response.body)

          unless (200..299).cover?(code)
            return Result::Error.new(
              message: body.is_a?(Hash) ? (body['detail'] || body['title'] || "HTTP #{code}") : "HTTP #{code}",
              retryable: retryable_code?(code),
              metadata: {}
            )
          end

          unless body.is_a?(Array)
            return Result::Error.new(
              message: 'ARC returned a malformed batch response',
              retryable: false,
              metadata: {}
            )
          end

          items = body.map { |item| build_item_result(item) }
          Result::Success.new(data: items, metadata: {})
        end

        # Build a per-item result for a batch response entry.
        def build_item_result(item)
          unless item.is_a?(Hash)
            return Result::Error.new(
              message: 'malformed batch item',
              retryable: false,
              metadata: {}
            )
          end

          if rejected_status?(item)
            Result::Error.new(
              message: item['detail'] || item['title'] || item['txStatus'],
              retryable: false,
              metadata: { arc_status: item['txStatus'].to_s.upcase, txid: item['txid'] }
            )
          elsif !item['txid']
            Result::Error.new(
              message: 'ARC returned a malformed 2xx response',
              retryable: false,
              metadata: {}
            )
          else
            Result::Success.new(
              data: {
                txid: item['txid'],
                tx_status: item['txStatus'],
                extra_info: item['extraInfo']
              },
              metadata: { arc_status: item['txStatus'] }
            )
          end
        end

        # Determine whether a status code indicates a retryable failure.
        def retryable_code?(code)
          code == 429 || (500..599).cover?(code)
        end

        # Determine whether an ARC response body represents a rejected transaction.
        # Case-insensitive match — the TypeScript reference SDK explicitly uppercases
        # both fields before membership / substring checks. ARC has a documented
        # history of emitting values outside its own OpenAPI enum, so case
        # normalisation is the defensive choice.
        def rejected_status?(body)
          tx_status = body['txStatus'].to_s.upcase
          return true if REJECTED_STATUSES.include?(tx_status)
          return true if tx_status.include?(ORPHAN_MARKER)

          extra_info = body['extraInfo'].to_s.upcase
          return true if extra_info.include?(ORPHAN_MARKER)

          false
        end

        # Parse JSON, returning a hash with a 'detail' key on parse failure.
        def safe_parse_json(raw)
          JSON.parse(raw.to_s)
        rescue JSON::ParserError
          { 'detail' => raw.to_s }
        end
      end
    end
  end
end
