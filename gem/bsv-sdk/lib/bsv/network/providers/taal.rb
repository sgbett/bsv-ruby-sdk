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
      # TAAL requires an API key for production use. The default rate limit is +nil+
      # (unconstrained) because the effective limit depends on the subscription tier.
      #
      # There is no TAAL testnet default — TAAL does not publish a supported testnet ARC URL.
      #
      # == Example
      #
      #   provider = BSV::Network::Providers::TAAL.mainnet(auth: { api_key: 'mainnet_...' })
      #   provider.call(:broadcast, tx)
      #
      #   # Legacy api_key: shorthand — still supported
      #   provider = BSV::Network::Providers::TAAL.mainnet(api_key: 'mainnet_...')
      class TAAL
        # Default requests-per-second limit.
        # +nil+ because the effective limit depends on the TAAL subscription tier.
        DEFAULT_RATE_LIMIT = nil

        # Returns a mainnet Provider configured with ARC and TAALBinary.
        #
        # Both protocols receive the same auth credentials.
        #
        # @param auth       [Hash, Symbol, nil] auth config forwarded to Provider and all protocols
        # @param rate_limit [Numeric, nil] requests per second; defaults to +DEFAULT_RATE_LIMIT+ (nil)
        # @param opts       [Hash] keyword arguments forwarded to each protocol constructor
        # @return [Provider]
        def self.mainnet(auth: nil, rate_limit: DEFAULT_RATE_LIMIT, **opts)
          resolved_auth = auth || (opts[:api_key] ? { bearer: opts[:api_key] } : :none)
          common = opts.slice(:api_key, :http_client).merge(auth: auth)
          Provider.new('TAAL', auth: resolved_auth, rate_limit: rate_limit) do |p|
            p.protocol Protocols::ARC,        base_url: 'https://arc.taal.com',  auth: auth, **opts
            p.protocol Protocols::TAALBinary, base_url: 'https://api.taal.com',  **common
          end
        end

        # Returns a testnet Provider configured with ARC only.
        #
        # @param auth       [Hash, Symbol, nil] auth config forwarded to Provider and ARC protocol
        # @param rate_limit [Numeric, nil] requests per second; defaults to +DEFAULT_RATE_LIMIT+ (nil)
        # @param opts       [Hash] keyword arguments forwarded to the ARC protocol constructor
        # @return [Provider]
        def self.testnet(auth: nil, rate_limit: DEFAULT_RATE_LIMIT, **opts)
          resolved_auth = auth || (opts[:api_key] ? { bearer: opts[:api_key] } : :none)
          Provider.new('TAAL', auth: resolved_auth, rate_limit: rate_limit) do |p|
            p.protocol Protocols::ARC, base_url: 'https://arc-test.taal.com', auth: auth, **opts
          end
        end

        # Returns a mainnet or testnet Provider depending on the +testnet:+ flag.
        #
        # @param testnet    [Boolean] when true, returns the testnet Provider
        # @param auth       [Hash, Symbol, nil] auth config forwarded to Provider and all protocols
        # @param rate_limit [Numeric, nil] requests per second; defaults to +DEFAULT_RATE_LIMIT+ (nil)
        # @param opts       [Hash] keyword arguments forwarded to each protocol constructor
        # @return [Provider]
        def self.default(testnet: false, auth: nil, rate_limit: DEFAULT_RATE_LIMIT, **opts)
          kwargs = { auth: auth, rate_limit: rate_limit, **opts }
          testnet ? testnet(**kwargs) : mainnet(**kwargs)
        end
      end
    end
  end
end
