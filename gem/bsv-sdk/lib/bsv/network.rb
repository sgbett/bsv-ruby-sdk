# frozen_string_literal: true

module BSV
  module Network
    autoload :Command,            'bsv/network/command'
    autoload :BroadcastError,     'bsv/network/broadcast_error'
    autoload :BroadcastResponse,  'bsv/network/broadcast_response'
    autoload :ChainProviderError, 'bsv/network/chain_provider_error'
    autoload :UTXO,               'bsv/network/utxo'
    autoload :ARC,                'bsv/network/arc'
    autoload :Result,             'bsv/network/result'
    autoload :Specifier,          'bsv/network/specifier'
    autoload :WhatsOnChain,       'bsv/network/whats_on_chain'
  end
end
