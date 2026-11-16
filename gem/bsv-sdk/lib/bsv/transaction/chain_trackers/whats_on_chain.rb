# frozen_string_literal: true

module BSV
  module Transaction
    module ChainTrackers
      # Chain tracker that verifies merkle roots using the WhatsOnChain API.
      #
      # Delegates all HTTP communication to {BSV::Network::Protocols::WoCREST}.
      # The constructor signature and {ChainTracker} contract are preserved.
      #
      # Note: the WoC API key is sent as a raw +Authorization+ header value
      # (not Bearer-prefixed) to match the existing WoC API convention.
      #
      # @example
      #   tracker = BSV::Transaction::ChainTrackers::WhatsOnChain.new
      #   tracker.valid_root_for_height?('abcd...', 800_000)
      class WhatsOnChain < ChainTracker
        # Returns a WhatsOnChain chain tracker using the provider default.
        #
        # @param testnet [Boolean] when true, uses the testnet endpoint
        # @param ** [Hash] forwarded to the underlying protocol (e.g. +api_key:+, +http_client:+)
        # @return [WhatsOnChain]
        def self.default(testnet: false, **)
          provider = BSV::Network::Providers::WhatsOnChain.default(testnet: testnet, **)
          new(protocol: provider.protocol_for(:valid_root))
        end

        # @param network [Symbol] :main, :mainnet, :test, :testnet (legacy compat)
        # @param api_key [String, nil] optional WoC API key
        # @param http_client [#request, nil] injectable HTTP client for testing
        # @param protocol [BSV::Network::Protocols::WoCREST, nil] pre-configured protocol
        def initialize(network: :main, api_key: nil, http_client: nil, protocol: nil)
          super()
          if protocol
            @protocol = protocol
          else
            provider = BSV::Network::Providers::WhatsOnChain.default(network: network, api_key: api_key, http_client: http_client)
            @protocol = provider.protocol_for(:valid_root)
          end
        end

        # Verify that a merkle root is valid for the given block height.
        #
        # @param root [String] merkle root as a hex string
        # @param height [Integer] block height
        # @return [Boolean]
        # @raise [StandardError] on network or API error
        def valid_root_for_height?(root, height)
          result = @protocol.call(:valid_root, root, height)
          return false if result.http_not_found?

          raise result.message.to_s unless result.http_success?

          result.data == true
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
