# frozen_string_literal: true

module BSV
  module Network
    autoload :Command,            'bsv/network/command'
    autoload :Commands,           'bsv/network/commands'
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
  end
end
