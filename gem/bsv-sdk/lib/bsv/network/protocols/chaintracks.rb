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
      # and testnet are served from separate base URLs; the default points to
      # the mainnet ARCADE domain.
      #
      # == Usage
      #
      #   ct = BSV::Network::Protocols::Chaintracks.new
      #   result = ct.call(:current_height)
      #   result.data  # => 800000
      #
      #   result = ct.call(:get_block_header, 800_000)
      #   result.data  # => { 'hash' => '...', 'height' => 800000, 'merkleRoot' => '...' }
      class Chaintracks < Protocol
        BASE_URL = 'https://arcade.gorillapool.io'

        endpoint :get_block_header, :get, '/chaintracks/v2/header/height/{height}', response: :json
        endpoint :current_height,   :get, '/chaintracks/v2/tip',
                 response: ->(body) { JSON.parse(body)['height'] }

        # @param api_key     [String, nil] optional Bearer API key
        # @param http_client [Object, nil] injectable HTTP client for testing
        def initialize(api_key: nil, http_client: nil)
          super(base_url: BASE_URL, api_key: api_key, http_client: http_client)
        end
      end
    end
  end
end
