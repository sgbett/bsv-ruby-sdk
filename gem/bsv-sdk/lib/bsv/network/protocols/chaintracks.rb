# frozen_string_literal: true

module BSV
  module Network
    module Protocols
      # Chaintracks protocol adapter for the GorillaPool Chaintracks service.
      #
      # Provides block header lookup and current chain tip height via the
      # GorillaPool Chaintracks v2 REST API.
      #
      # == Usage
      #
      #   ct = BSV::Network::Protocols::Chaintracks.new(
      #     base_url: 'https://arcade.gorillapool.io'
      #   )
      #   result = ct.call(:get_block_header, height: 800_000)
      #   result.data  # => { 'hash' => '...', 'height' => 800000, ... }
      #
      #   result = ct.call(:current_height)
      #   result.data  # => 800000
      class Chaintracks < BSV::Network::Protocol
        endpoint :get_block_header, :get, '/chaintracks/v2/header/height/{height}', response: :json
        endpoint :current_height,   :get, '/chaintracks/v2/tip',
                 response: ->(body) { JSON.parse(body)['height'] }
      end
    end
  end
end
