# frozen_string_literal: true

module BSV
  module Network
    module Providers
      # WhatsOnChain returns pre-configured Provider instances using the
      # WhatsOnChain REST API (WoCREST protocol).
      #
      # The base URL is fully resolved per network — no +{network}+ template
      # is used in provider defaults. The WoCREST protocol's +network:+ param
      # is omitted since the URL already encodes the network segment.
      #
      # == Example
      #
      #   provider = BSV::Network::Providers::WhatsOnChain.mainnet
      #   provider.call(:get_tx, 'abc123...')
      #
      #   provider = BSV::Network::Providers::WhatsOnChain.testnet(api_key: 'my-key')
      #   provider.call(:broadcast, tx)
      class WhatsOnChain
        # Returns a mainnet Provider configured with WoCREST.
        #
        # @param opts [Hash] keyword arguments forwarded to each protocol constructor
        # @return [Provider]
        def self.mainnet(**opts)
          Provider.new('WhatsOnChain') do |p|
            p.protocol Protocols::WoCREST, base_url: 'https://api.whatsonchain.com/v1/bsv/main', **opts
          end
        end

        # Returns a testnet Provider configured with WoCREST.
        #
        # @param opts [Hash] keyword arguments forwarded to each protocol constructor
        # @return [Provider]
        def self.testnet(**opts)
          Provider.new('WhatsOnChain') do |p|
            p.protocol Protocols::WoCREST, base_url: 'https://api.whatsonchain.com/v1/bsv/test', **opts
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
