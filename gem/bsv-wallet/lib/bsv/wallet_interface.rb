# frozen_string_literal: true

module BSV
  module Wallet
    autoload :VERSION,          'bsv/wallet_interface/version'

    # BRC-100 Interface
    autoload :Interface,        'bsv/wallet_interface/interface'
    autoload :KeyDeriver,       'bsv/wallet_interface/key_deriver'
    autoload :ProtoWallet,      'bsv/wallet_interface/proto_wallet'
    autoload :Validators,       'bsv/wallet_interface/validators'
    autoload :StorageAdapter,    'bsv/wallet_interface/storage/storage_adapter'
    autoload :BroadcastQueue,    'bsv/wallet_interface/broadcast/broadcast_queue'
    autoload :InlineQueue,       'bsv/wallet_interface/broadcast/inline_queue'
    autoload :MemoryStore,       'bsv/wallet_interface/storage/memory_store'
    autoload :FileStore,         'bsv/wallet_interface/storage/file_store'
    autoload :ProofStore,        'bsv/wallet_interface/storage/proof_store'
    autoload :LocalProofStore,   'bsv/wallet_interface/storage/local_proof_store'
    autoload :WalletClient,      'bsv/wallet_interface/wallet_client'
    autoload :Wire,              'bsv/wallet_interface/wire'
    autoload :Substrates,        'bsv/wallet_interface/substrates'
    autoload :CertificateSignature, 'bsv/wallet_interface/certificate_signature'
    autoload :FeeModel,             'bsv/wallet_interface/fee_model'
    autoload :FeeEstimator,         'bsv/wallet_interface/fee_estimator'
    autoload :CoinSelector,         'bsv/wallet_interface/coin_selector'
    autoload :ChangeGenerator,      'bsv/wallet_interface/change_generator'
    autoload :UTXOPool,             'bsv/wallet_interface/pool/utxo_pool'
    autoload :LocalPool,            'bsv/wallet_interface/pool/local_pool'
    autoload :ReplenishmentWorker,  'bsv/wallet_interface/pool/replenishment_worker'

    # Error classes
    autoload :InsufficientFundsError, 'bsv/wallet/insufficient_funds_error'
    autoload :WalletError,            'bsv/wallet_interface/errors/wallet_error'
    autoload :InvalidParameterError,  'bsv/wallet_interface/errors/invalid_parameter_error'
    autoload :InvalidHmacError,       'bsv/wallet_interface/errors/invalid_hmac_error'
    autoload :InvalidSignatureError,  'bsv/wallet_interface/errors/invalid_signature_error'
    autoload :UnsupportedActionError, 'bsv/wallet_interface/errors/unsupported_action_error'
    autoload :PoolDepletedError,      'bsv/wallet_interface/errors/pool_depleted_error'
  end
end
