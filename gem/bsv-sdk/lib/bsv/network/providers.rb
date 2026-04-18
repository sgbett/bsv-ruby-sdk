# frozen_string_literal: true

module BSV
  module Network
    # Providers is a namespace module for pre-configured Provider factory classes.
    #
    # Each provider class has +.mainnet+ and +.testnet+ class methods that return
    # a fully-configured +Provider+ instance with the appropriate protocol set.
    # Both methods accept +**opts+ which are forwarded to each protocol constructor
    # (e.g. +api_key:+, +http_client:+).
    #
    # == Example
    #
    #   provider = BSV::Network::Providers::GorillaPool.mainnet
    #   result   = provider.call(:broadcast, tx)
    #
    #   provider = BSV::Network::Providers::TAAL.mainnet(api_key: 'my-key')
    #   result   = provider.call(:broadcast, tx)
    module Providers
      autoload :GorillaPool,   'bsv/network/providers/gorilla_pool'
      autoload :WhatsOnChain,  'bsv/network/providers/whats_on_chain'
      autoload :TAAL,          'bsv/network/providers/taal'
    end
  end
end
