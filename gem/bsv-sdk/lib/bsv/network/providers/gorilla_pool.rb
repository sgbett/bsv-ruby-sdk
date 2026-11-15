# frozen_string_literal: true

module BSV
  module Network
    module Providers
      # GorillaPool returns pre-configured Provider instances using GorillaPool's
      # ARC endpoint for broadcasting, the Ordinals API for transaction and merkle
      # path lookups, and JungleBus for indexed transaction data and block headers.
      #
      # Broadcast goes through classic ARC (+/v1/tx+), as the default broadcaster
      # of the TypeScript and Python SDKs does.
      #
      # Mainnet composes three protocols:
      # - ARC at +https://arc.gorillapool.io+
      # - Ordinals at +https://ordinals.gorillapool.io+
      # - JungleBus at +https://junglebus.gorillapool.io+
      #
      # Testnet composes two protocols:
      # - ARC at +https://testnet.arc.gorillapool.io+
      # - JungleBus at +https://testnet.junglebus.gorillapool.io+
      #
      # Any credentials supplied are forwarded to every protocol, so every
      # GorillaPool host the provider composes receives the caller's key.
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

        # Returns a mainnet Provider configured with ARC, Ordinals, and JungleBus.
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
            p.protocol Protocols::ARC,       base_url: 'https://arc.gorillapool.io', auth: auth, **opts
            # TODO: re-register chaintracks_server at separate URL/port — see issue #778
            p.protocol Protocols::Ordinals,  base_url: 'https://ordinals.gorillapool.io', **common
            p.protocol Protocols::JungleBus, base_url: 'https://junglebus.gorillapool.io', **common
          end
        end

        # Returns a testnet Provider configured with ARC and JungleBus.
        #
        # @param auth       [Hash, Symbol, nil] auth config forwarded to Provider and all protocols
        # @param rate_limit [Numeric, nil] requests per second; defaults to +DEFAULT_RATE_LIMIT+
        # @param opts       [Hash] keyword arguments forwarded to each protocol constructor
        # @return [Provider]
        def self.testnet(auth: nil, rate_limit: DEFAULT_RATE_LIMIT, **opts)
          resolved_auth = auth || (opts[:api_key] ? { bearer: opts[:api_key] } : :none)
          common = opts.slice(:api_key, :http_client).merge(auth: auth)
          Provider.new('GorillaPool', auth: resolved_auth, rate_limit: rate_limit) do |p|
            p.protocol Protocols::ARC,       base_url: 'https://testnet.arc.gorillapool.io', auth: auth, **opts
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
