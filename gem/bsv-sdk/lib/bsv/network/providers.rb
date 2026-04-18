# frozen_string_literal: true

module BSV
  module Network
    # Namespace for concrete {Provider} implementations.
    #
    # Each provider is registered here via +autoload+ so it is loaded on first
    # reference without eagerly requiring all implementations at boot.
    #
    # @example Access a provider class
    #   BSV::Network::Providers::WhatsOnChain
    #   BSV::Network::Providers::ARC
    module Providers
      autoload :WhatsOnChain, 'bsv/network/providers/whats_on_chain'
      autoload :ARC,          'bsv/network/providers/arc'
    end
  end
end
