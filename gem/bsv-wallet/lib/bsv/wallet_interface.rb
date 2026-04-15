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
    autoload :BroadcastQueue,    'bsv/wallet_interface/broadcast_queue'
    autoload :InlineQueue,       'bsv/wallet_interface/inline_queue'
    autoload :MemoryStore,       'bsv/wallet_interface/memory_store'
    autoload :FileStore,         'bsv/wallet_interface/file_store'
    autoload :ProofStore,        'bsv/wallet_interface/proof_store'
    autoload :LocalProofStore,   'bsv/wallet_interface/local_proof_store'
    autoload :ChainProvider,          'bsv/wallet_interface/chain_provider'
    autoload :NullChainProvider,      'bsv/wallet_interface/null_chain_provider'
    autoload :WhatsOnChainProvider,   'bsv/wallet_interface/whats_on_chain_provider'
    autoload :WalletClient,      'bsv/wallet_interface/wallet_client'
    autoload :Wire,              'bsv/wallet_interface/wire'
    autoload :Substrates,        'bsv/wallet_interface/substrates'
    autoload :CertificateSignature, 'bsv/wallet_interface/certificate_signature'
    autoload :FeeModel,             'bsv/wallet_interface/fee_model'
    autoload :FeeEstimator,         'bsv/wallet_interface/fee_estimator'
    autoload :CoinSelector,         'bsv/wallet_interface/coin_selector'
    autoload :ChangeGenerator,      'bsv/wallet_interface/change_generator'

    # Error classes
    autoload :InsufficientFundsError, 'bsv/wallet/insufficient_funds_error'
    autoload :WalletError,            'bsv/wallet_interface/errors/wallet_error'
    autoload :InvalidParameterError,  'bsv/wallet_interface/errors/invalid_parameter_error'
    autoload :InvalidHmacError,       'bsv/wallet_interface/errors/invalid_hmac_error'
    autoload :InvalidSignatureError,  'bsv/wallet_interface/errors/invalid_signature_error'
    autoload :UnsupportedActionError, 'bsv/wallet_interface/errors/unsupported_action_error'
  end
end
