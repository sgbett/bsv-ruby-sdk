# frozen_string_literal: true

module BSV
  module Network
    module Providers
      # BSVAssociation returns pre-configured Provider instances for the BSV
      # Association's public BSV Broadcaster (formerly Arcade) hosts, the same
      # ones the TypeScript wallet-toolbox uses (+publicArcadeUrl+).
      #
      # This provider is opt-in: no default in the SDK uses it. It is named after
      # the operator, like the other providers; the hosts also serve Chaintracks,
      # which a later change can add here.
      #
      # - Mainnet: Arcade at +https://arcade-v2-us-1.bsvblockchain.tech+
      # - Testnet: Arcade at +https://arcade-v2-testnet-us-1.bsvblockchain.tech+
      #
      # No key is required: anonymous use is rate-limited per IP address. Any
      # credentials supplied are forwarded to the Arcade protocol only.
      #
      # == Example
      #
      #   provider = BSV::Network::Providers::BSVAssociation.mainnet
      #   provider.call(:broadcast, tx)
      #
      #   provider = BSV::Network::Providers::BSVAssociation.testnet(auth: { bearer: 'token' })
      class BSVAssociation
        # The anonymous per-IP limit is not published, so none is assumed.
        DEFAULT_RATE_LIMIT = nil

        # Returns a mainnet Provider configured with Arcade.
        #
        # @param auth       [Hash, Symbol, nil] auth config forwarded to Provider and Arcade
        # @param rate_limit [Numeric, nil] requests per second; defaults to +DEFAULT_RATE_LIMIT+ (nil)
        # @param opts       [Hash] keyword arguments forwarded to the Arcade constructor
        # @return [Provider]
        def self.mainnet(auth: nil, rate_limit: DEFAULT_RATE_LIMIT, **opts)
          resolved_auth = auth || (opts[:api_key] ? { bearer: opts[:api_key] } : :none)
          Provider.new('BSVAssociation', auth: resolved_auth, rate_limit: rate_limit) do |p|
            p.protocol Protocols::Arcade, base_url: 'https://arcade-v2-us-1.bsvblockchain.tech', auth: auth, **opts
          end
        end

        # Returns a testnet Provider configured with Arcade.
        #
        # @param auth       [Hash, Symbol, nil] auth config forwarded to Provider and Arcade
        # @param rate_limit [Numeric, nil] requests per second; defaults to +DEFAULT_RATE_LIMIT+ (nil)
        # @param opts       [Hash] keyword arguments forwarded to the Arcade constructor
        # @return [Provider]
        def self.testnet(auth: nil, rate_limit: DEFAULT_RATE_LIMIT, **opts)
          resolved_auth = auth || (opts[:api_key] ? { bearer: opts[:api_key] } : :none)
          Provider.new('BSVAssociation', auth: resolved_auth, rate_limit: rate_limit) do |p|
            p.protocol Protocols::Arcade, base_url: 'https://arcade-v2-testnet-us-1.bsvblockchain.tech', auth: auth, **opts
          end
        end

        # Returns a mainnet or testnet Provider depending on the +testnet:+ flag.
        #
        # @param testnet    [Boolean] when true, returns the testnet Provider
        # @param auth       [Hash, Symbol, nil] auth config forwarded to Provider and Arcade
        # @param rate_limit [Numeric, nil] requests per second; defaults to +DEFAULT_RATE_LIMIT+ (nil)
        # @param opts       [Hash] keyword arguments forwarded to the Arcade constructor
        # @return [Provider]
        def self.default(testnet: false, auth: nil, rate_limit: DEFAULT_RATE_LIMIT, **opts)
          kwargs = { auth: auth, rate_limit: rate_limit, **opts }
          testnet ? testnet(**kwargs) : mainnet(**kwargs)
        end
      end
    end
  end
end
