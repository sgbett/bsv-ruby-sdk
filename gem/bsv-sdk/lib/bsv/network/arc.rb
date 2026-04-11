# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require 'securerandom'

module BSV
  module Network
    # ARC broadcaster for submitting transactions to the BSV network.
    #
    # Any object responding to #broadcast(tx) can serve as a broadcaster;
    # this class implements that contract using the ARC API.
    #
    # The HTTP client is injectable for testability. It must respond to
    # #request(uri, request) and return an object with #code and #body.
    class ARC
      # Returns an ARC instance pointed at the GorillaPool public ARC endpoint.
      #
      # @param testnet [Boolean] when true, uses the GorillaPool testnet endpoint
      # @param opts [Hash] forwarded to {#initialize} (e.g. +api_key:+, +callback_url:+)
      # @return [ARC]
      def self.default(testnet: false, **opts)
        url = testnet ? 'https://testnet.arc.gorillapool.io' : 'https://arc.gorillapool.io'
        new(url, **opts)
      end

      # ARC response statuses that indicate the transaction was NOT accepted.
      # Matches the TypeScript SDK's ARC broadcaster failure set (issue #305,
      # finding F5.13). Prior to this fix, Ruby only recognised REJECTED and
      # DOUBLE_SPEND_ATTEMPTED, silently treating INVALID / MALFORMED /
      # MINED_IN_STALE_BLOCK responses as successful broadcasts.
      REJECTED_STATUSES = %w[
        REJECTED
        DOUBLE_SPEND_ATTEMPTED
        INVALID
        MALFORMED
        MINED_IN_STALE_BLOCK
      ].freeze

      # Substring match for orphan detection in txStatus or extraInfo fields.
      ORPHAN_MARKER = 'ORPHAN'

      # @param url [String] ARC base URL (without trailing slash)
      # @param api_key [String, nil] optional bearer token for Authorization
      # @param deployment_id [String, nil] optional deployment identifier for
      #   the +XDeployment-ID+ header; defaults to a per-instance random value
      # @param callback_url [String, nil] optional +X-CallbackUrl+ for ARC
      #   status callbacks
      # @param callback_token [String, nil] optional +X-CallbackToken+ for
      #   ARC status callback authentication
      # @param http_client [#request, nil] injectable HTTP client for testing
      def initialize(url, api_key: nil, deployment_id: nil, callback_url: nil,
                     callback_token: nil, http_client: nil)
        @url = url.chomp('/')
        @api_key = api_key
        @deployment_id = deployment_id || "bsv-ruby-sdk-#{SecureRandom.hex(8)}"
        @callback_url = callback_url
        @callback_token = callback_token
        @http_client = http_client
      end

      # Submit a transaction to ARC.
      #
      # The transaction is encoded as Extended Format (BRC-30) hex when every
      # input has +source_satoshis+ and +source_locking_script+ populated,
      # which lets ARC validate sighashes without fetching parents. Falls back
      # to plain raw-tx hex when EF is unavailable.
      #
      # @param tx [Transaction] the transaction to broadcast
      # @param wait_for [String, nil] ARC wait condition — one of
      #   'RECEIVED', 'STORED', 'ANNOUNCED_TO_NETWORK',
      #   'SEEN_ON_NETWORK', or 'MINED'. When set, ARC holds the
      #   connection open until the transaction reaches the requested
      #   state (or times out). Defaults to nil (no wait).
      # @return [BroadcastResponse]
      # @raise [BroadcastError] when ARC returns a non-2xx HTTP status or a
      #   rejected/orphan +txStatus+
      def broadcast(tx, wait_for: nil)
        uri = URI("#{@url}/v1/tx")
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['XDeployment-ID'] = @deployment_id
        request['X-WaitFor'] = wait_for if wait_for
        request['X-CallbackUrl'] = @callback_url if @callback_url
        request['X-CallbackToken'] = @callback_token if @callback_token
        apply_auth_header(request)
        request.body = JSON.generate(rawTx: raw_tx_hex(tx))

        response = execute(uri, request)
        handle_broadcast_response(response)
      end

      # Query the status of a previously submitted transaction.
      # Returns BroadcastResponse on success, raises BroadcastError on failure.
      def status(txid)
        uri = URI("#{@url}/v1/tx/#{txid}")
        request = Net::HTTP::Get.new(uri)
        request['XDeployment-ID'] = @deployment_id
        apply_auth_header(request)

        response = execute(uri, request)
        handle_broadcast_response(response)
      end

      private

      # Prefer Extended Format (BRC-30) hex so ARC can validate sighashes
      # without fetching parent transactions. Falls back to plain raw-tx hex
      # when any input lacks source_satoshis / source_locking_script.
      def raw_tx_hex(tx)
        tx.to_ef_hex
      rescue ArgumentError
        tx.to_hex
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

      def handle_broadcast_response(response)
        body = parse_json(response.body)
        code = response.code.to_i

        unless (200..299).cover?(code)
          raise BroadcastError.new(
            body['detail'] || body['title'] || "HTTP #{code}",
            status_code: code,
            txid: body['txid']
          )
        end

        if rejected_status?(body)
          raise BroadcastError.new(
            body['detail'] || body['title'] || body['txStatus'],
            status_code: code,
            txid: body['txid']
          )
        end

        # A 2xx response without a txid is a malformed ARC reply —
        # `parse_json` falls back to `{'detail' => raw}` on non-JSON,
        # which would otherwise produce a `BroadcastResponse` full of
        # `nil`s and `success? => true`. That's the same silent
        # success-as-failure class of bug F5.13 closed for explicit
        # error statuses; closing it here for shape corruption too.
        unless body['txid']
          raise BroadcastError.new(
            'ARC returned a malformed 2xx response',
            status_code: code
          )
        end

        build_response(body)
      end

      def rejected_status?(body)
        # Case-insensitive match — the TypeScript reference
        # (`ts-sdk/src/transaction/broadcasters/ARC.ts:155-166`) explicitly
        # `.toUpperCase()`s both fields before membership / substring checks.
        # ARC has a documented history of emitting values outside its own
        # OpenAPI enum (e.g. `txStatus: "success"` for orphans in TS issue
        # #105), so case normalisation is the defensive choice.
        tx_status = body['txStatus'].to_s.upcase
        return true if REJECTED_STATUSES.include?(tx_status)
        return true if tx_status.include?(ORPHAN_MARKER)

        extra_info = body['extraInfo'].to_s.upcase
        return true if extra_info.include?(ORPHAN_MARKER)

        false
      end

      def parse_json(raw)
        JSON.parse(raw)
      rescue JSON::ParserError
        { 'detail' => raw }
      end

      def build_response(body)
        BroadcastResponse.new(
          txid: body['txid'],
          tx_status: body['txStatus'],
          message: body['title'],
          extra_info: body['extraInfo'],
          block_hash: body['blockHash'],
          block_height: body['blockHeight'],
          timestamp: body['timestamp'],
          competing_txs: body['competingTxs']
        )
      end
    end
  end
end
