# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

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
      REJECTED_STATUSES = %w[REJECTED DOUBLE_SPEND_ATTEMPTED].freeze

      def initialize(url, api_key: nil, http_client: nil)
        @url = url.chomp('/')
        @api_key = api_key
        @http_client = http_client
      end

      # Submit a transaction to ARC.
      #
      # @param tx [Transaction] the transaction to broadcast
      # @param wait_for [String, nil] ARC wait condition — one of
      #   'RECEIVED', 'STORED', 'ANNOUNCED_TO_NETWORK',
      #   'SEEN_ON_NETWORK', or 'MINED'. When set, ARC holds the
      #   connection open until the transaction reaches the requested
      #   state (or times out). Defaults to nil (no wait).
      # @return [BroadcastResponse]
      # @raise [BroadcastError]
      def broadcast(tx, wait_for: nil)
        uri = URI("#{@url}/v1/tx")
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/octet-stream'
        request['X-WaitFor'] = wait_for if wait_for
        apply_auth_header(request)
        request.body = tx.to_binary

        response = execute(uri, request)
        handle_broadcast_response(response)
      end

      # Query the status of a previously submitted transaction.
      # Returns BroadcastResponse on success, raises BroadcastError on failure.
      def status(txid)
        uri = URI("#{@url}/v1/tx/#{txid}")
        request = Net::HTTP::Get.new(uri)
        apply_auth_header(request)

        response = execute(uri, request)
        handle_broadcast_response(response)
      end

      private

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

        tx_status = body['txStatus']
        if rejected_status?(tx_status)
          raise BroadcastError.new(
            body['detail'] || body['title'] || tx_status,
            status_code: code,
            txid: body['txid']
          )
        end

        build_response(body)
      end

      def rejected_status?(tx_status)
        REJECTED_STATUSES.include?(tx_status)
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
