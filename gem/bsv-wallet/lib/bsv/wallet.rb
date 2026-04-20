# frozen_string_literal: true

module BSV
  module Wallet
    autoload :VERSION,          'bsv/wallet/version'

    # BRC-100 abstract contract modules
    autoload :BRC100,           'bsv/wallet/interface/brc100'

    # BRC-100 Interface
    autoload :Interface,        'bsv/wallet/interface'
    autoload :KeyDeriver,       'bsv/wallet/client/key_deriver'
    autoload :Validators,       'bsv/wallet/client/validators'
    autoload :Store,             'bsv/wallet/store'
    autoload :BroadcastQueue,    'bsv/wallet/broadcast_queue'
    autoload :ProofStore,        'bsv/wallet/interface/proof_store'
    autoload :LocalProofStore,   'bsv/wallet/proof_store/local_proof_store'
    autoload :Client,            'bsv/wallet/client'
    autoload :Wire,              'bsv/wallet/wire'
    autoload :Substrates,        'bsv/wallet/substrates'
    autoload :CertificateSignature, 'bsv/wallet/client/certificate_signature'
    autoload :FeeModel,             'bsv/wallet/client/fee_model'
    autoload :FeeEstimator,         'bsv/wallet/client/fee_estimator'
    autoload :CoinSelector,         'bsv/wallet/client/coin_selector'
    autoload :ChangeGenerator,      'bsv/wallet/client/change_generator'
    autoload :UTXOPool,             'bsv/wallet/interface/utxo_pool'
    autoload :LocalPool,            'bsv/wallet/utxo_pool/local_pool'
    autoload :ReplenishmentWorker,  'bsv/wallet/utxo_pool/replenishment_worker'

    # Error classes
    autoload :InsufficientFundsError, 'bsv/wallet/errors/insufficient_funds_error'
    autoload :WalletError,            'bsv/wallet/errors/wallet_error'
    autoload :InvalidParameterError,  'bsv/wallet/errors/invalid_parameter_error'
    autoload :InvalidHmacError,       'bsv/wallet/errors/invalid_hmac_error'
    autoload :InvalidSignatureError,  'bsv/wallet/errors/invalid_signature_error'
    autoload :UnsupportedActionError, 'bsv/wallet/errors/unsupported_action_error'
    autoload :PoolDepletedError,      'bsv/wallet/errors/pool_depleted_error'
  end
end
