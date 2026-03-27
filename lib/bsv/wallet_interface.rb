# frozen_string_literal: true

module BSV
  module WalletInterface
    autoload :VERSION, 'bsv/wallet_interface/version'
  end

  module Wallet
    # BRC-100 Interface
    autoload :Interface,        'bsv/wallet_interface/interface'
    autoload :KeyDeriver,       'bsv/wallet_interface/key_deriver'
    autoload :ProtoWallet,      'bsv/wallet_interface/proto_wallet'
    autoload :Validators,       'bsv/wallet_interface/validators'
    autoload :StorageAdapter,    'bsv/wallet_interface/storage_adapter'
    autoload :MemoryStore,       'bsv/wallet_interface/memory_store'
    autoload :ChainProvider,     'bsv/wallet_interface/chain_provider'
    autoload :NullChainProvider, 'bsv/wallet_interface/null_chain_provider'
    autoload :WalletClient,      'bsv/wallet_interface/wallet_client'

    # Error classes
    autoload :WalletError,            'bsv/wallet_interface/errors/wallet_error'
    autoload :InvalidParameterError,  'bsv/wallet_interface/errors/invalid_parameter_error'
    autoload :InvalidHmacError,       'bsv/wallet_interface/errors/invalid_hmac_error'
    autoload :InvalidSignatureError,  'bsv/wallet_interface/errors/invalid_signature_error'
    autoload :UnsupportedActionError, 'bsv/wallet_interface/errors/unsupported_action_error'
  end
end
