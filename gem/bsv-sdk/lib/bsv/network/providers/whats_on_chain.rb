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
      #   provider = BSV::Network::Providers::WhatsOnChain.mainnet(auth: { api_key: 'my-key' })
      #   provider.call(:broadcast, tx)
      #
      #   # Legacy api_key: shorthand — still supported
      #   provider = BSV::Network::Providers::WhatsOnChain.testnet(api_key: 'my-key')
      class WhatsOnChain
        # Default requests-per-second limit for unauthenticated use.
        DEFAULT_RATE_LIMIT = 3

        # Returns a mainnet Provider configured with WoCREST.
        #
        # @param auth       [Hash, Symbol, nil] auth config forwarded to Provider and WoCREST protocol
        # @param rate_limit [Numeric, nil] requests per second; defaults to +DEFAULT_RATE_LIMIT+
        # @param opts       [Hash] keyword arguments forwarded to the WoCREST protocol constructor
        # @return [Provider]
        def self.mainnet(auth: nil, rate_limit: DEFAULT_RATE_LIMIT, **opts)
          resolved_auth = auth || (opts[:api_key] ? { api_key: opts[:api_key] } : :none)
          Provider.new('WhatsOnChain', auth: resolved_auth, rate_limit: rate_limit) do |p|
            p.protocol Protocols::WoCREST, base_url: 'https://api.whatsonchain.com/v1/bsv/main',
                                           auth: auth, **opts
          end
        end

        # Returns a testnet Provider configured with WoCREST.
        #
        # @param auth       [Hash, Symbol, nil] auth config forwarded to Provider and WoCREST protocol
        # @param rate_limit [Numeric, nil] requests per second; defaults to +DEFAULT_RATE_LIMIT+
        # @param opts       [Hash] keyword arguments forwarded to the WoCREST protocol constructor
        # @return [Provider]
        def self.testnet(auth: nil, rate_limit: DEFAULT_RATE_LIMIT, **opts)
          resolved_auth = auth || (opts[:api_key] ? { api_key: opts[:api_key] } : :none)
          Provider.new('WhatsOnChain', auth: resolved_auth, rate_limit: rate_limit) do |p|
            p.protocol Protocols::WoCREST, base_url: 'https://api.whatsonchain.com/v1/bsv/test',
                                           auth: auth, **opts
          end
        end

        # Returns a Provider for the BSV Scaling Test Network (STN).
        #
        # @param auth       [Hash, Symbol, nil] auth config forwarded to Provider and WoCREST protocol
        # @param rate_limit [Numeric, nil] requests per second; defaults to +DEFAULT_RATE_LIMIT+
        # @param opts       [Hash] keyword arguments forwarded to the WoCREST protocol constructor
        # @return [Provider]
        def self.stn(auth: nil, rate_limit: DEFAULT_RATE_LIMIT, **opts)
          resolved_auth = auth || (opts[:api_key] ? { api_key: opts[:api_key] } : :none)
          Provider.new('WhatsOnChain', auth: resolved_auth, rate_limit: rate_limit) do |p|
            p.protocol Protocols::WoCREST, base_url: 'https://api.whatsonchain.com/v1/bsv/stn',
                                           auth: auth, **opts
          end
        end

        # Returns a Provider for the given network.
        #
        # @param testnet    [Boolean] when true, returns the testnet Provider
        # @param network    [Symbol, nil] explicit network (:main, :test, :stn) — overrides +testnet:+
        # @param auth       [Hash, Symbol, nil] auth config forwarded to Provider and WoCREST protocol
        # @param rate_limit [Numeric, nil] requests per second; defaults to +DEFAULT_RATE_LIMIT+
        # @param opts       [Hash] keyword arguments forwarded to the WoCREST protocol constructor
        # @return [Provider]
        def self.default(testnet: false, network: nil, auth: nil, rate_limit: DEFAULT_RATE_LIMIT, **opts)
          kwargs = { auth: auth, rate_limit: rate_limit, **opts }
          if network
            case network.to_sym
            when :main, :mainnet then mainnet(**kwargs)
            when :test, :testnet then testnet(**kwargs)
            when :stn then stn(**kwargs)
            else raise ArgumentError, "unknown network: #{network}"
            end
          else
            testnet ? testnet(**kwargs) : mainnet(**kwargs)
          end
        end
      end
    end
  end
end
