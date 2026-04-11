# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module BSV
  module Transaction
    module ChainTrackers
      # Chain tracker that verifies merkle roots using the Chaintracks API (Arcade/GorillaPool).
      #
      # Queries the Chaintracks v2 block header endpoint to retrieve the merkle root for a
      # given block height and compares it with the provided root.
      #
      # @example
      #   tracker = BSV::Transaction::ChainTrackers::Chaintracks.new
      #   tracker.valid_root_for_height?('abcd...', 800_000)
      #
      # @example With API key
      #   tracker = BSV::Transaction::ChainTrackers::Chaintracks.new(api_key: 'my-key')
      #   tracker.current_height
      class Chaintracks < ChainTracker
        MAINNET_URL = 'https://arcade.gorillapool.io'
        TESTNET_URL = 'https://testnet.arcade.gorillapool.io'

        # @param url [String] base URL for the Chaintracks API
        # @param api_key [String, nil] optional Bearer API key
        # @param http_client [#request, nil] injectable HTTP client for testing
        def initialize(url: MAINNET_URL, api_key: nil, http_client: nil)
          super()
          @url = url
          @api_key = api_key
          @http_client = http_client
        end

        # Verify that a merkle root is valid for the given block height.
        #
        # @param root [String] merkle root as a hex string
        # @param height [Integer] block height
        # @return [Boolean]
        def valid_root_for_height?(root, height)
          response = get("/chaintracks/v2/header/height/#{height}")
          return false if response.nil?

          data = JSON.parse(response.body)
          data['merkleRoot'].downcase == root.downcase
        end

        # Return the current blockchain height.
        #
        # @return [Integer]
        def current_height
          response = get('/chaintracks/v2/tip', not_found_returns_nil: false)
          data = JSON.parse(response.body)
          data['height']
        end

        private

        # @param path [String] API path
        # @param not_found_returns_nil [Boolean] if true, return nil on 404 instead of raising
        # @return [Net::HTTPResponse, nil]
        def get(path, not_found_returns_nil: true)
          uri = URI("#{@url}#{path}")
          request = Net::HTTP::Get.new(uri)
          request['Authorization'] = "Bearer #{@api_key}" if @api_key

          response = execute(uri, request)
          code = response.code.to_i

          return nil if not_found_returns_nil && code == 404
          return response if (200..299).cover?(code)

          raise BSV::Network::ChainProviderError.new(
            response.body || "HTTP #{code}",
            status_code: code
          )
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
      end
    end
  end
end
