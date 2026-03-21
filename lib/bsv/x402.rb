# frozen_string_literal: true

module BSV
  module X402
    autoload :Configuration,  'bsv/x402/configuration'
    autoload :Challenge,      'bsv/x402/challenge'
    autoload :CanonicalJSON,  'bsv/x402/canonical_json'
    autoload :Encoding,       'bsv/x402/encoding'
    autoload :Error,                 'bsv/x402/errors'
    autoload :EncodingError,         'bsv/x402/errors'
    autoload :ValidationError,       'bsv/x402/errors'
    autoload :InsufficientFundsError,     'bsv/x402/errors'
    autoload :ChallengeExpiredError,      'bsv/x402/errors'
    autoload :PaymentRetryExhaustedError, 'bsv/x402/errors'
    autoload :NonceUTXO,      'bsv/x402/nonce_utxo'
    autoload :Proof,          'bsv/x402/proof'
    autoload :RequestBinding,      'bsv/x402/request_binding'
    autoload :VerificationResult,  'bsv/x402/verification_result'
    autoload :Verifier,            'bsv/x402/verifier'
    autoload :TransactionBuilder, 'bsv/x402/transaction_builder'
    autoload :ProofBuilder,       'bsv/x402/proof_builder'
    autoload :NonceProvider,       'bsv/x402/nonce_provider'
    autoload :StaticNonceProvider, 'bsv/x402/nonce_provider'
    autoload :ChallengeStore,      'bsv/x402/challenge_store'
    autoload :MemoryChallengeStore, 'bsv/x402/challenge_store'
    autoload :RouteMap,            'bsv/x402/route_map'
    autoload :ChallengeGenerator,  'bsv/x402/challenge_generator'
    autoload :Middleware,          'bsv/x402/middleware'
    autoload :Client,              'bsv/x402/client'
    autoload :VERSION, 'bsv/x402/version'

    class << self
      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration)
      end

      def reset_configuration!
        @configuration = Configuration.new
      end
    end
  end
end
