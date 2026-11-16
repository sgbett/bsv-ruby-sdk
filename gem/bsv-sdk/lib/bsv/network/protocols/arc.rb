# frozen_string_literal: true

require 'json'
require 'securerandom'

module BSV
  module Network
    module Protocols
      # ARC protocol implementation for submitting transactions to the BSV network.
      #
      # Extends Protocol with five endpoints and three escape hatches
      # (+broadcast+, +broadcast_many+ and +get_tx_status+) for broadcast logic:
      # EF format preference, rejection detection, custom headers and malformed
      # reply detection.
      #
      # Transport and service failures come back as a failed ProtocolResponse.
      # Invalid arguments (an empty transaction, a malformed txid) raise
      # +ArgumentError+.
      #
      # == Example
      #
      #   arc = BSV::Network::Protocols::ARC.new(
      #     base_url: 'https://arc.taal.com',
      #     api_key: 'my-api-key'
      #   )
      #   result = arc.call(:broadcast, tx)
      #   result.http_success? # => true
      #   result.data['txid'] # => "abc123..."
      #
      # @see https://docs.gorillapool.io/arc/api.html ARC API v1 documentation
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

        MALFORMED_2XX = 'ARC returned a malformed 2xx response'

        # Whether a +txStatus+ value means the transaction was not accepted.
        # Case-insensitive: ARC has a documented history of emitting values
        # outside its own OpenAPI enum, and the TypeScript SDK upcases both
        # fields before comparing. Compared as bytes: the JSON parser admits
        # invalid UTF-8 inside strings, which +upcase+ would raise on, and the
        # tokens that matter are ASCII.
        #
        # @param tx_status [Object] the +txStatus+ field of a response body
        # @return [Boolean]
        def self.rejected_tx_status?(tx_status)
          status = tx_status.to_s.b.upcase
          REJECTED_STATUSES.include?(status) || status.include?(ORPHAN_MARKER)
        end

        # Whether a response body reports a rejected transaction, by +txStatus+
        # or by an orphan marker in +extraInfo+.
        #
        # @param body [Object] parsed JSON response body
        # @return [Boolean] false for anything other than a Hash
        def self.rejected?(body)
          return false unless body.is_a?(Hash)

          rejected_tx_status?(body['txStatus']) || body['extraInfo'].to_s.b.upcase.include?(ORPHAN_MARKER)
        end

        # Describe a rejection as +"STATUS: extraInfo"+, or just the status
        # when there is no extra information. The generic +title+ and +detail+
        # fields are not used: on a 2xx they read "OK" or are empty.
        #
        # @param body [Hash] parsed JSON response body
        # @return [String] +"REJECTED"+ stands in when +txStatus+ is unusable
        def self.rejection_message(body)
          status = BSV::Network::Util.service_text(body['txStatus']) || 'REJECTED'
          extra_info = BSV::Network::Util.service_text(body['extraInfo'])
          extra_info ? "#{status}: #{extra_info}" : status
        end

        endpoint :broadcast,      :post, '/v1/tx',          response: :json
        endpoint :broadcast_many, :post, '/v1/txs',         response: :json_array
        endpoint :get_tx_status,  :get,  '/v1/tx/{txid}',   response: :json
        endpoint :get_policy,     :get,  '/v1/policy',      response: :json
        endpoint :health,         :get,  '/v1/health',      response: :json

        # @param base_url      [String]      ARC base URL (may contain {network})
        # @param api_key       [String, nil] legacy bearer token shorthand — use +auth:+ for new code
        # @param auth          [Hash, Symbol, nil] auth config; takes precedence over +api_key:+
        # @param network       [String, nil] network name for base URL interpolation
        # @param deployment_id [String, nil] deployment identifier for the
        #   XDeployment-ID header; defaults to a per-instance random hex value
        # @param callback_url  [String, nil] optional X-CallbackUrl header value
        # @param callback_token [String, nil] optional X-CallbackToken header value
        # @param http_client   [#request, nil] injectable HTTP client for testing
        def initialize(base_url:, api_key: nil, auth: nil, network: nil, deployment_id: nil,
                       callback_url: nil, callback_token: nil, http_client: nil)
          super(base_url: base_url, api_key: api_key, auth: auth, network: network, http_client: http_client)
          @deployment_id  = deployment_id || "bsv-ruby-sdk-#{SecureRandom.hex(8)}"
          @callback_url   = callback_url
          @callback_token = callback_token
        end

        private

        # Broadcast escape hatch: EF format preference, custom headers, rejection
        # detection, and malformed 2xx detection.
        #
        # @param tx [#to_ef_hex, #to_hex, String] transaction object, hex string,
        #   or binary string
        # @param wait_for [String, nil] ARC wait condition
        # @param skip_fee_validation [Boolean, nil]
        # @param skip_script_validation [Boolean, nil]
        # @param skip_tx_validation [Boolean, nil]
        # @param callback_url [String, nil] per-call callback URL override
        # @param callback_token [String, nil] per-call callback token override
        # @param callback_batch [Boolean, nil] when truthy, sends X-CallbackBatch header
        # @return [ProtocolResponse]
        def call_broadcast(tx, wait_for: nil, skip_fee_validation: nil,
                           skip_script_validation: nil, skip_tx_validation: nil,
                           callback_url: nil, callback_token: nil, callback_batch: nil, **)
          hex  = resolve_tx_hex(tx)
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

          response = post_with_headers(self.class.endpoints[:broadcast][:path], body, extra_headers)
          parse_single_broadcast_response(response)
        end

        # Broadcast-many escape hatch: batch broadcast with raw JSON array result.
        #
        # @param txs [Array<#to_ef_hex, #to_hex, String>]
        # @param wait_for [String, nil]
        # @param skip_fee_validation [Boolean, nil]
        # @param skip_script_validation [Boolean, nil]
        # @param skip_tx_validation [Boolean, nil]
        # @param callback_url [String, nil]
        # @param callback_token [String, nil]
        # @param callback_batch [Boolean, nil]
        # @return [ProtocolResponse]
        def call_broadcast_many(txs, wait_for: nil, skip_fee_validation: nil,
                                skip_script_validation: nil, skip_tx_validation: nil,
                                callback_url: nil, callback_token: nil, callback_batch: nil, **)
          return ProtocolResponse.new(nil, data: [], http_success: true) if txs.empty?

          body = JSON.generate(txs.map { |tx| { rawTx: resolve_tx_hex(tx) } })

          extra_headers = build_broadcast_headers(
            wait_for: wait_for,
            skip_fee_validation: skip_fee_validation,
            skip_script_validation: skip_script_validation,
            skip_tx_validation: skip_tx_validation,
            callback_url: callback_url || @callback_url,
            callback_token: callback_token || @callback_token,
            callback_batch: callback_batch
          )

          response = post_with_headers(self.class.endpoints[:broadcast_many][:path], body, extra_headers)
          parse_batch_broadcast_response(response)
        end

        # Override to always include XDeployment-ID on every ARC request.
        def build_request(http_method, uri, body)
          request = super
          request['XDeployment-ID'] = @deployment_id
          request
        end

        def resolve_tx_hex(tx)
          BSV::Network::Util.resolve_tx_hex(tx)
        end

        # Build the hash of ARC-specific extra headers.
        def build_broadcast_headers(wait_for:, skip_fee_validation:, skip_script_validation:,
                                    skip_tx_validation:, callback_url:, callback_token:,
                                    callback_batch:)
          headers = {}
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
        #
        # @return [ProtocolResponse]
        def parse_single_broadcast_response(response)
          code = response.code.to_i
          body = safe_json_object(response.body)

          unless (200..299).cover?(code)
            return ProtocolResponse.new(
              response,
              http_success: false,
              error_message: service_message(body, code, %w[detail title]),
              data: body
            )
          end

          return ProtocolResponse.new(response, http_success: false, error_message: MALFORMED_2XX) unless body

          if self.class.rejected?(body)
            return ProtocolResponse.new(
              response,
              http_success: false,
              error_message: self.class.rejection_message(body),
              data: body
            )
          end

          return ProtocolResponse.new(response, http_success: false, error_message: MALFORMED_2XX) unless body['txid']

          ProtocolResponse.new(response, data: body)
        end

        # Parse and validate a batch ARC response. HTTP-level errors return a
        # single error ProtocolResponse; success data is a raw JSON array of hashes.
        #
        # @return [ProtocolResponse]
        def parse_batch_broadcast_response(response)
          code = response.code.to_i
          body = safe_json(response.body)

          unless (200..299).cover?(code)
            return ProtocolResponse.new(
              response,
              http_success: false,
              error_message: service_message(body, code, %w[detail title]),
              data: body.is_a?(Hash) || body.is_a?(Array) ? body : nil
            )
          end

          unless body.is_a?(Array)
            return ProtocolResponse.new(
              response,
              http_success: false,
              error_message: 'ARC returned a malformed batch response'
            )
          end

          ProtocolResponse.new(response, data: body)
        end

        # Escape hatch for get_tx_status: checks for rejection status, a missing
        # or mismatched txid (malformed 2xx), and bounds the service text in
        # failures. Returns raw JSON data (string keys).
        #
        # A reply naming a different transaction is rejected, as the TypeScript
        # wallet-toolbox does, so a misrouted or spoofed reply is not taken as
        # the status of the transaction asked about.
        #
        # @param txid [String] ARC API boundary: display-order hex transaction ID to query
        # @return [ProtocolResponse]
        # @raise [ArgumentError] if +txid+ is not 64-char display-order hex
        def call_get_tx_status(txid, **)
          BSV::Primitives::Hex.validate_dtxid_hex!(txid, name: 'txid')
          response = default_call(:get_tx_status, txid)
          return response if response.code.nil?
          return status_failure(response) unless response.http_success?

          body = response.data

          # The txid binding comes before the rejection check, so a rejection is
          # never attributed to a transaction the reply does not name.
          return response.with(http_success: false, data: nil, error_message: MALFORMED_2XX) unless reply_for?(body, txid)

          return response.with(http_success: false, error_message: self.class.rejection_message(body)) if self.class.rejected?(body)

          response
        end

        # The encoding is checked first because the JSON parser admits invalid
        # UTF-8 inside strings, which +match?+ raises on; the hex check comes
        # before +casecmp?+, whose Unicode case folding would let a ligature
        # such as U+FB00 stand in for "ff".
        def reply_for?(body, txid)
          reported = body.is_a?(Hash) ? body['txid'] : nil
          reported.is_a?(String) && reported.valid_encoding? && reported.match?(/\A\h{64}\z/) &&
            reported.casecmp?(txid)
        end

        # A 2xx that default_call could not turn into data is a malformed reply;
        # any other failure carries a bounded message instead of the raw body.
        def status_failure(response)
          code = response.code.to_i
          return response.with(error_message: MALFORMED_2XX) if (200..299).cover?(code)

          response.with(error_message: service_message(safe_json_object(response.body), code, %w[detail title extraInfo]))
        end

        # The first usable field of a parsed error body, bounded; +"HTTP <code>"+
        # when the body is not an object or has none. Non-JSON bodies are never echoed.
        def service_message(body, code, fields)
          if body.is_a?(Hash)
            fields.each do |field|
              text = BSV::Network::Util.service_text(body[field])
              return text if text
            end
          end
          "HTTP #{code}"
        end

        def safe_json_object(raw)
          body = safe_json(raw)
          body.is_a?(Hash) ? body : nil
        end

        # Parsed JSON, or nil for a body that is not JSON. Unlike
        # Util.safe_parse_json, a non-JSON body is never wrapped for echoing.
        def safe_json(raw)
          JSON.parse(raw.to_s)
        rescue JSON::ParserError, EncodingError
          nil
        end
      end
    end
  end
end
