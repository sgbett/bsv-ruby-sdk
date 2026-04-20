# frozen_string_literal: true

module BSV
  module Wallet
    autoload :VERSION,          'bsv/wallet/version'

    # Interfaces (abstract contracts)
    autoload :Interface,        'bsv/wallet/interface'

    # Client implementation
    autoload :Client,            'bsv/wallet/client'
    autoload :KeyDeriver,        'bsv/wallet/client/key_deriver'
    autoload :Validators,        'bsv/wallet/client/validators'
    autoload :CertificateSignature, 'bsv/wallet/client/certificate_signature'
    autoload :FeeModel,          'bsv/wallet/client/fee_model'
    autoload :FeeEstimator,      'bsv/wallet/client/fee_estimator'
    autoload :CoinSelector,      'bsv/wallet/client/coin_selector'
    autoload :ChangeGenerator,   'bsv/wallet/client/change_generator'

    # Pluggable collaborators
    autoload :Store,             'bsv/wallet/store'
    autoload :BroadcastQueue,    'bsv/wallet/broadcast_queue'
    autoload :LocalProofStore,   'bsv/wallet/proof_store/local_proof_store'
    autoload :LocalPool,         'bsv/wallet/utxo_pool/local_pool'
    autoload :ReplenishmentWorker, 'bsv/wallet/utxo_pool/replenishment_worker'

    # Communication
    autoload :Wire,              'bsv/wallet/wire'
    autoload :Substrates,        'bsv/wallet/substrates'

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
