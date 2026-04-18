# frozen_string_literal: true

module BSV
  module Network
    autoload :Command,            'bsv/network/command'
    autoload :BroadcastError,     'bsv/network/broadcast_error'
    autoload :BroadcastResponse,  'bsv/network/broadcast_response'
    autoload :ChainProviderError, 'bsv/network/chain_provider_error'
    autoload :UTXO,               'bsv/network/utxo'
    autoload :ARC,                'bsv/network/arc'
    autoload :Provider,           'bsv/network/provider'
    autoload :Result,             'bsv/network/result'
    autoload :Registry,           'bsv/network/registry'
    autoload :Specifier,          'bsv/network/specifier'
    autoload :WhatsOnChain,       'bsv/network/whats_on_chain'
    autoload :Providers,          'bsv/network/providers'

    # Eagerly register all 11 standard commands so they are available
    # as soon as BSV::Network is loaded, before any provider is instantiated.
    require 'bsv/network/commands'

    # Returns all registered network commands.
    #
    # @return [Hash{Symbol => Command}]
    def self.commands
      Command.all
    end

    # Returns a pre-configured Registry with both standard providers registered.
    #
    # WoC handles chain-data commands; ARC handles broadcast commands.
    # Options allow the registry to be tailored without subclassing.
    #
    # @param network [Symbol] :main or :test — passed to WhatsOnChain
    # @param arc_url [String] ARC base URL (defaults to GorillaPool ARCADE)
    # @param woc_api_key [String, nil] optional WhatsOnChain API key
    # @param arc_api_key [String, nil] optional ARC bearer token
    # @return [Registry]
    def self.default_registry(network: :main, arc_url: BSV::MAINNET_URL,
                              woc_api_key: nil, arc_api_key: nil)
      woc = Providers::WhatsOnChain.new(network: network, api_key: woc_api_key)
      arc = Providers::ARC.new(url: arc_url, api_key: arc_api_key)

      Registry.new
              .register(woc)
              .register(arc)
    end

    # Returns a capability matrix for a default registry instance.
    #
    # Delegates to {Registry#capability_matrix} on a fresh default registry.
    # Useful for introspection and tooling.
    #
    # @return [Hash{Provider => Array<Symbol>}]
    def self.capability_matrix
      default_registry.capability_matrix
    end
  end
end
