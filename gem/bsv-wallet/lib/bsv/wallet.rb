# frozen_string_literal: true

module BSV
  module Wallet
    autoload :VERSION,          'bsv/wallet/version'

    # BRC-100 abstract contract modules
    autoload :BRC100,           'bsv/wallet/brc100'

    # BRC-100 Interface
    autoload :Interface,        'bsv/wallet/interface'
    autoload :KeyDeriver,       'bsv/wallet/key_deriver'
    autoload :Validators,       'bsv/wallet/validators'
    autoload :StorageAdapter,    'bsv/wallet/storage_adapter'
    autoload :BroadcastQueue,    'bsv/wallet/broadcast_queue'
    autoload :InlineQueue,       'bsv/wallet/inline_queue'
    autoload :MemoryStore,       'bsv/wallet/memory_store'
    autoload :FileStore,         'bsv/wallet/file_store'
    autoload :ProofStore,        'bsv/wallet/proof_store'
    autoload :LocalProofStore,   'bsv/wallet/local_proof_store'
    autoload :Client,            'bsv/wallet/client'
    autoload :Wire,              'bsv/wallet/wire'
    autoload :Substrates,        'bsv/wallet/substrates'
    autoload :CertificateSignature, 'bsv/wallet/certificate_signature'
    autoload :FeeModel,             'bsv/wallet/fee_model'
    autoload :FeeEstimator,         'bsv/wallet/fee_estimator'
    autoload :CoinSelector,         'bsv/wallet/coin_selector'
    autoload :ChangeGenerator,      'bsv/wallet/change_generator'
    autoload :UTXOPool,             'bsv/wallet/utxo_pool'
    autoload :LocalPool,            'bsv/wallet/local_pool'
    autoload :ReplenishmentWorker,  'bsv/wallet/replenishment_worker'

    # Error classes
    autoload :InsufficientFundsError, 'bsv/wallet/insufficient_funds_error'
    autoload :WalletError,            'bsv/wallet/errors/wallet_error'
    autoload :InvalidParameterError,  'bsv/wallet/errors/invalid_parameter_error'
    autoload :InvalidHmacError,       'bsv/wallet/errors/invalid_hmac_error'
    autoload :InvalidSignatureError,  'bsv/wallet/errors/invalid_signature_error'
    autoload :UnsupportedActionError, 'bsv/wallet/errors/unsupported_action_error'
    autoload :PoolDepletedError,      'bsv/wallet/errors/pool_depleted_error'
  end
end
