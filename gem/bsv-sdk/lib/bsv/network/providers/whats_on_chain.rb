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

        # Returns a Provider for the BSV Scaling Test Network (STN).
        #
        # @param opts [Hash] keyword arguments forwarded to each protocol constructor
        # @return [Provider]
        def self.stn(**opts)
          Provider.new('WhatsOnChain') do |p|
            p.protocol Protocols::WoCREST, base_url: 'https://api.whatsonchain.com/v1/bsv/stn', **opts
          end
        end

        # Returns a Provider for the given network.
        #
        # @param testnet [Boolean] when true, returns the testnet Provider
        # @param network [Symbol, nil] explicit network (:main, :test, :stn) — overrides +testnet:+
        # @param opts [Hash] keyword arguments forwarded to each protocol constructor
        # @return [Provider]
        def self.default(testnet: false, network: nil, **opts)
          if network
            case network.to_sym
            when :main, :mainnet then mainnet(**opts)
            when :test, :testnet then testnet(**opts)
            when :stn then stn(**opts)
            else raise ArgumentError, "unknown network: #{network}"
            end
          else
            testnet ? testnet(**opts) : mainnet(**opts)
          end
        end
      end
    end
  end
end
