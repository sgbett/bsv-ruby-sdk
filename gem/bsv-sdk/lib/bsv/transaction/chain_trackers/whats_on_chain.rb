# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module BSV
  module Transaction
    module ChainTrackers
      # Chain tracker that verifies merkle roots using the WhatsOnChain API.
      #
      # Queries the WoC block header endpoint to retrieve the merkle root for a
      # given block height and compares it with the provided root.
      #
      # @example
      #   tracker = BSV::Transaction::ChainTrackers::WhatsOnChain.new
      #   tracker.valid_root_for_height?('abcd...', 800_000)
      class WhatsOnChain < ChainTracker
        BASE_URL = 'https://api.whatsonchain.com'

        NETWORKS = {
          main: 'main',
          mainnet: 'main',
          test: 'test',
          testnet: 'test',
          stn: 'stn'
        }.freeze

        # @param network [Symbol] :main, :mainnet, :test, :testnet, or :stn
        # @param api_key [String, nil] optional WoC API key
        # @param http_client [#request, nil] injectable HTTP client for testing
        def initialize(network: :main, api_key: nil, http_client: nil)
          super()
          @network = NETWORKS.fetch(network) { raise ArgumentError, "unknown network: #{network}" }
          @api_key = api_key
          @http_client = http_client
        end

        # Verify that a merkle root is valid for the given block height.
        #
        # @param root [String] merkle root as a hex string
        # @param height [Integer] block height
        # @return [Boolean]
        def valid_root_for_height?(root, height)
          response = get("/v1/bsv/#{@network}/block/#{height}/header")
          return false if response.nil?

          data = JSON.parse(response.body)
          data['merkleroot'].downcase == root.downcase
        end

        # Return the current blockchain height.
        #
        # @return [Integer]
        def current_height
          response = get("/v1/bsv/#{@network}/chain/info", not_found_returns_nil: false)
          data = JSON.parse(response.body)
          data['blocks']
        end

        private

        # @param path [String] API path
        # @param not_found_returns_nil [Boolean] if true, return nil on 404 instead of raising
        # @return [Net::HTTPResponse, nil]
        def get(path, not_found_returns_nil: true)
          uri = URI("#{BASE_URL}#{path}")
          request = Net::HTTP::Get.new(uri)
          request['Authorization'] = @api_key if @api_key

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
