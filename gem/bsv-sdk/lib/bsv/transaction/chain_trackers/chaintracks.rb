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
        # Returns a Chaintracks instance using the GorillaPool provider default.
        #
        # @param testnet [Boolean] when true, uses the testnet endpoint
        # @param opts [Hash] forwarded to the underlying protocol (e.g. +api_key:+, +http_client:+)
        # @return [Chaintracks]
        def self.default(testnet: false, **opts)
          provider = BSV::Network::Providers::GorillaPool.default(testnet: testnet, **opts)
          protocol = provider.protocol_for(:current_height)
          new(protocol: protocol)
        end

        # @param url [String, nil] base URL (legacy compat — prefer .default or protocol:)
        # @param api_key [String, nil] optional Bearer API key
        # @param http_client [#request, nil] injectable HTTP client for testing
        # @param protocol [BSV::Network::Protocols::Chaintracks, nil] pre-configured protocol
        def initialize(url: nil, api_key: nil, http_client: nil, protocol: nil)
          super()
          if protocol
            @protocol = protocol
          elsif url
            @url = url.chomp('/')
            @api_key = api_key
            @protocol = BSV::Network::Protocols::Chaintracks.new(
              base_url: @url,
              api_key: api_key,
              http_client: http_client
            )
          else
            provider = BSV::Network::Providers::GorillaPool.default(api_key: api_key, http_client: http_client)
            @protocol = provider.protocol_for(:current_height)
          end
        end

        # Verify that a merkle root is valid for the given block height.
        #
        # @param root [String] merkle root as a hex string
        # @param height [Integer] block height
        # @return [Boolean]
        # @raise [StandardError] on network or API error
        def valid_root_for_height?(root, height)
          result = @protocol.call(:get_block_header, height)
          return false if result.http_not_found?

          raise result.message.to_s unless result.http_success?

          merkle_root = result.data['merkleRoot']
          return false unless merkle_root

          merkle_root.downcase == root.downcase
        end

        # Return the current blockchain height.
        #
        # @return [Integer]
        # @raise [StandardError] on network or API error
        def current_height
          result = @protocol.call(:current_height)
          return result.data if result.http_success?

          raise result.message.to_s
        end
      end
    end
  end
end
