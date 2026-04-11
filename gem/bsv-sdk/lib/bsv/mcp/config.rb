# frozen_string_literal: true

module BSV
  module MCP
    # Configuration parsed from environment variables for the MCP server.
    #
    # Environment variables:
    #   BSV_NETWORK   — 'mainnet' or 'testnet' (default: 'mainnet')
    #   BSV_ARC_URL   — optional ARC endpoint override
    #   BSV_ARC_API_KEY — optional ARC bearer token
    class Config
      MAINNET = 'mainnet'
      TESTNET = 'testnet'
      VALID_NETWORKS = [MAINNET, TESTNET].freeze

      attr_reader :network, :arc_url, :arc_api_key

      def initialize(network: nil, arc_url: nil, arc_api_key: nil)
        raw_network = network || ENV.fetch('BSV_NETWORK', MAINNET)
        @network = normalise_network(raw_network)
        @arc_url = arc_url || ENV.fetch('BSV_ARC_URL', nil)
        @arc_api_key = arc_api_key || ENV.fetch('BSV_ARC_API_KEY', nil)
      end

      def mainnet?
        @network == MAINNET
      end

      def testnet?
        @network == TESTNET
      end

      private

      def normalise_network(value)
        normalised = value.to_s.strip.downcase
        return normalised if VALID_NETWORKS.include?(normalised)

        warn "BSV::MCP::Config: unknown network '#{value}', defaulting to '#{MAINNET}'"
        MAINNET
      end
    end
  end
end
