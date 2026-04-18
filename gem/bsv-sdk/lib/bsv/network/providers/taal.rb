# frozen_string_literal: true

module BSV
  module Network
    module Providers
      # TAAL returns pre-configured Provider instances using the TAAL infrastructure.
      #
      # Mainnet composes two protocols:
      # - ARC at +https://arc.taal.com+ for standard ARC operations
      # - TAALBinary at +https://api.taal.com+ for binary broadcast
      #
      # ARC is registered first, so +:broadcast+ is served by ARC (first-registered wins).
      # TAALBinary registers its own +:broadcast+ command but will not win the index.
      # To use TAALBinary directly, call +provider.protocol_for(:broadcast)+ on the
      # TAALBinary instance via +provider.protocols.last+, or build a custom Provider.
      #
      # There is no TAAL testnet default — TAAL does not publish a supported testnet ARC URL.
      #
      # == Example
      #
      #   provider = BSV::Network::Providers::TAAL.mainnet(api_key: 'mainnet_...')
      #   provider.call(:broadcast, tx)
      class TAAL
        # Returns a mainnet Provider configured with ARC and TAALBinary.
        #
        # @param opts [Hash] keyword arguments forwarded to each protocol constructor
        # @return [Provider]
        def self.mainnet(**opts)
          Provider.new('TAAL') do |p|
            p.protocol Protocols::ARC, base_url: 'https://arc.taal.com', **opts
            p.protocol Protocols::TAALBinary, base_url: 'https://api.taal.com', **opts
          end
        end

        # Returns a testnet Provider configured with ARC only.
        #
        # @param opts [Hash] keyword arguments forwarded to each protocol constructor
        # @return [Provider]
        def self.testnet(**opts)
          Provider.new('TAAL') do |p|
            p.protocol Protocols::ARC, base_url: 'https://arc-test.taal.com', **opts
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
