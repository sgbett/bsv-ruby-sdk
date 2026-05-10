# frozen_string_literal: true

module BSV
  module Network
    autoload :ProtocolResponse,   'bsv/network/protocol_response'
    autoload :Protocol,           'bsv/network/protocol'
    autoload :Protocols,          'bsv/network/protocols'
    autoload :Providers,          'bsv/network/providers'
    autoload :Provider,           'bsv/network/provider'
    autoload :BroadcastError,     'bsv/network/broadcast_error'
    autoload :BroadcastResponse,  'bsv/network/broadcast_response'
    autoload :ChainProviderError, 'bsv/network/chain_provider_error'
    autoload :UTXO,               'bsv/network/utxo'
    autoload :ARC,                'bsv/network/arc'
    autoload :WhatsOnChain,       'bsv/network/whats_on_chain'
  end
end
