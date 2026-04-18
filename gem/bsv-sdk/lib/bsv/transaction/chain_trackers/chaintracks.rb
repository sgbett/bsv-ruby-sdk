# frozen_string_literal: true

module BSV
  module Transaction
    module ChainTrackers
      # Chain tracker that verifies merkle roots using the Chaintracks API (Arcade/GorillaPool).
      #
      # Delegates all HTTP communication to {BSV::Network::Protocols::Chaintracks}.
      # The constructor signature and {ChainTracker} contract are preserved.
      #
      # @example
      #   tracker = BSV::Transaction::ChainTrackers::Chaintracks.new
      #   tracker.valid_root_for_height?('abcd...', 800_000)
      #
      # @example With API key
      #   tracker = BSV::Transaction::ChainTrackers::Chaintracks.new(api_key: 'my-key')
      #   tracker.current_height
      class Chaintracks < ChainTracker
        MAINNET_URL = BSV::MAINNET_URL
        TESTNET_URL = BSV::TESTNET_URL

        # @param url [String] base URL for the Chaintracks API
        # @param api_key [String, nil] optional Bearer API key
        # @param http_client [#request, nil] injectable HTTP client for testing
        def initialize(url: MAINNET_URL, api_key: nil, http_client: nil)
          super()
          @url = url.chomp('/')
          @api_key = api_key
          @protocol = BSV::Network::Protocols::Chaintracks.new(
            base_url: @url,
            api_key: api_key,
            http_client: http_client
          )
        end

        # Verify that a merkle root is valid for the given block height.
        #
        # @param root [String] merkle root as a hex string
        # @param height [Integer] block height
        # @return [Boolean]
        # @raise [BSV::Network::ChainProviderError] on network or API error
        def valid_root_for_height?(root, height)
          result = @protocol.call(:get_block_header, height)
          return false if result.not_found?

          if result.error?
            raise BSV::Network::ChainProviderError.new(
              result.message.to_s,
              status_code: result.metadata[:status_code]
            )
          end

          merkle_root = result.data['merkleRoot']
          return false unless merkle_root

          merkle_root.downcase == root.downcase
        end

        # Return the current blockchain height.
        #
        # @return [Integer]
        # @raise [BSV::Network::ChainProviderError] on network or API error
        def current_height
          result = @protocol.call(:current_height)
          return result.data if result.success?

          raise BSV::Network::ChainProviderError.new(
            result.message.to_s,
            status_code: result.metadata[:status_code]
          )
        end
      end
    end
  end
end
