# frozen_string_literal: true

module BSV
  module Network
    module Providers
      # GorillaPool returns pre-configured Provider instances using the GorillaPool
      # Arcade infrastructure for broadcasting, the GorillaPool Ordinals API for
      # transaction and merkle path lookups, and JungleBus for indexed transaction
      # data and block headers.
      #
      # Mainnet composes three protocols:
      # - Arcade at +https://arcade.gorillapool.io+
      # - Ordinals at +https://ordinals.gorillapool.io+
      # - JungleBus at +https://junglebus.gorillapool.io+
      #
      # Testnet composes two protocols:
      # - Arcade at +https://testnet.arcade.gorillapool.io+
      # - JungleBus at +https://testnet.junglebus.gorillapool.io+
      #
      # == Example
      #
      #   provider = BSV::Network::Providers::GorillaPool.mainnet
      #   provider.call(:broadcast, tx)
      #
      #   provider = BSV::Network::Providers::GorillaPool.mainnet(auth: { bearer: 'token' })
      #   provider.call(:broadcast, tx)
      #
      #   # Legacy api_key: shorthand — still supported
      #   provider = BSV::Network::Providers::GorillaPool.testnet(api_key: 'my-key')
      class GorillaPool
        # Default requests-per-second limit for unauthenticated use.
        DEFAULT_RATE_LIMIT = 3

        # Returns a mainnet Provider configured with Arcade, Ordinals, and JungleBus.
        #
        # Auth is forwarded to all three protocols so each can authenticate independently.
        #
        # @param auth       [Hash, Symbol, nil] auth config forwarded to Provider and all protocols
        # @param rate_limit [Numeric, nil] requests per second; defaults to +DEFAULT_RATE_LIMIT+
        # @param opts       [Hash] keyword arguments forwarded to each protocol constructor
        # @return [Provider]
        def self.mainnet(auth: nil, rate_limit: DEFAULT_RATE_LIMIT, **opts)
          resolved_auth = auth || (opts[:api_key] ? { bearer: opts[:api_key] } : :none)
          common = opts.slice(:api_key, :http_client).merge(auth: auth)
          Provider.new('GorillaPool', auth: resolved_auth, rate_limit: rate_limit) do |p|
            p.protocol Protocols::Arcade,    base_url: 'https://arcade.gorillapool.io', auth: auth, **opts
            # TODO: re-register chaintracks_server at separate URL/port — see issue #778
            p.protocol Protocols::Ordinals,  base_url: 'https://ordinals.gorillapool.io', **common
            p.protocol Protocols::JungleBus, base_url: 'https://junglebus.gorillapool.io', **common
          end
        end

        # Returns a testnet Provider configured with Arcade only.
        #
        # @param auth       [Hash, Symbol, nil] auth config forwarded to Provider and all protocols
        # @param rate_limit [Numeric, nil] requests per second; defaults to +DEFAULT_RATE_LIMIT+
        # @param opts       [Hash] keyword arguments forwarded to each protocol constructor
        # @return [Provider]
        def self.testnet(auth: nil, rate_limit: DEFAULT_RATE_LIMIT, **opts)
          resolved_auth = auth || (opts[:api_key] ? { bearer: opts[:api_key] } : :none)
          common = opts.slice(:api_key, :http_client).merge(auth: auth)
          Provider.new('GorillaPool', auth: resolved_auth, rate_limit: rate_limit) do |p|
            p.protocol Protocols::Arcade,    base_url: 'https://testnet.arcade.gorillapool.io', auth: auth, **opts
            p.protocol Protocols::JungleBus, base_url: 'https://testnet.junglebus.gorillapool.io', **common
            # TODO: re-register chaintracks_server at separate URL/port — see issue #778
          end
        end

        # Returns a mainnet or testnet Provider depending on the +testnet:+ flag.
        #
        # @param testnet    [Boolean] when true, returns the testnet Provider
        # @param auth       [Hash, Symbol, nil] auth config forwarded to Provider and all protocols
        # @param rate_limit [Numeric, nil] requests per second; defaults to +DEFAULT_RATE_LIMIT+
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
