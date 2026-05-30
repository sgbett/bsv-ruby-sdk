# frozen_string_literal: true

require 'json'

module BSV
  module Network
    module Protocols
      # Chaintracks implements the GorillaPool Chaintracks API as a Protocol subclass.
      #
      # Provides block header lookup and current chain tip height via the
      # GorillaPool Chaintracks v2 REST API. Pure DSL — no escape hatches needed.
      #
      # Chaintracks does not use a +{network}+ placeholder in the URL. Mainnet
      # and testnet are served from separate base URLs; the provider defaults
      # supply the correct URL for each network.
      #
      # == Usage
      #
      #   ct = BSV::Network::Protocols::Chaintracks.new(base_url: 'http://localhost:8080')
      #   result = ct.call(:current_height)
      #   result.data  # => 800000
      #
      #   result = ct.call(:get_block_header, 800_000)
      #   result.data  # => { 'hash' => '...', 'height' => 800000, 'merkleRoot' => '...' }
      #
      # @note No public Chaintracks instance is hosted by major providers — GorillaPool
      #   serves chain data via JungleBus instead. For general chain-tracking against
      #   GorillaPool, use the porcelain interface:
      #   +BSV::Transaction::ChainTracker.new(BSV::Network::Providers::GorillaPool.mainnet)+
      #   which routes through JungleBus automatically.
      class Chaintracks < Protocol
        endpoint :get_block_header, :get, '/chaintracks/v2/header/height/{height}', response: :json
        endpoint :current_height,   :get, '/chaintracks/v2/tip',
                 response: ->(body) { JSON.parse(body)['height'] }

        # @param base_url    [String] base URL for the Chaintracks API
        # @param api_key     [String, nil] legacy Bearer API key shorthand — use +auth:+ for new code
        # @param auth        [Hash, Symbol, nil] auth config; takes precedence over +api_key:+
        # @param http_client [Object, nil] injectable HTTP client for testing
        def initialize(base_url:, api_key: nil, auth: nil, http_client: nil)
          super
        end
      end
    end
  end
end
