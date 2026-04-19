# frozen_string_literal: true

module BSV
  module Network
    module Providers
      # GorillaPool returns pre-configured Provider instances using the GorillaPool
      # ARCADE infrastructure for ARC and Chaintracks, and the GorillaPool Ordinals
      # API for transaction and merkle path lookups.
      #
      # Mainnet composes three protocols:
      # - ARC at +https://arcade.gorillapool.io+
      # - Chaintracks at +https://arcade.gorillapool.io+
      # - Ordinals at +https://ordinals.gorillapool.io+
      #
      # Testnet provides ARC only at +https://testnet.arcade.gorillapool.io+.
      #
      # == Example
      #
      #   provider = BSV::Network::Providers::GorillaPool.mainnet
      #   provider.call(:broadcast, tx)
      #
      #   provider = BSV::Network::Providers::GorillaPool.testnet(api_key: 'my-key')
      #   provider.call(:broadcast, tx)
      class GorillaPool
        # Returns a mainnet Provider configured with ARC, Chaintracks, and Ordinals.
        #
        # @param opts [Hash] keyword arguments forwarded to each protocol constructor
        # @return [Provider]
        def self.mainnet(**opts)
          common = opts.slice(:api_key, :http_client)
          Provider.new('GorillaPool') do |p|
            p.protocol Protocols::ARC,         base_url: 'https://arcade.gorillapool.io', **opts
            p.protocol Protocols::Chaintracks, base_url: 'https://arcade.gorillapool.io', **common
            p.protocol Protocols::Ordinals,    base_url: 'https://ordinals.gorillapool.io', **common
          end
        end

        # Returns a testnet Provider configured with ARC and Chaintracks.
        #
        # @param opts [Hash] keyword arguments forwarded to each protocol constructor
        # @return [Provider]
        def self.testnet(**opts)
          common = opts.slice(:api_key, :http_client)
          Provider.new('GorillaPool') do |p|
            p.protocol Protocols::ARC,         base_url: 'https://testnet.arcade.gorillapool.io', **opts
            p.protocol Protocols::Chaintracks, base_url: 'https://testnet.arcade.gorillapool.io', **common
          end
        end

        # Returns a mainnet or testnet Provider depending on the +testnet:+ flag.
        #
        # @param testnet [Boolean] when true, returns the testnet Provider
        # @param opts    [Hash]    keyword arguments forwarded to each protocol constructor
        # @return [Provider]
        def self.default(testnet: false, **opts)
          testnet ? testnet(**opts) : mainnet(**opts)
        end
      end
    end
  end
end
