# frozen_string_literal: true

module BSV
  module X402
    # Configuration for the BSV x402 payment protocol middleware.
    #
    # Fields:
    # - +payee_locking_script_hex+ — hex-encoded locking script for the payment output
    # - +amount_sats+              — default payment amount in satoshis
    # - +nonce_provider+           — pluggable UTXO nonce provider (must respond to +reserve_nonce+)
    # - +broadcaster+              — pluggable broadcaster (must respond to +broadcast+)
    # - +expires_in+               — challenge expiry window in seconds
    # - +bound_headers+            — array of header names to include in request binding
    # - +on_payment_verified+      — optional callable invoked after successful verification
    #                                receives the Rack env and the VerificationResult
    # - +settlement_verifier+      — optional callable for mempool acceptance check
    #                                receives raw transaction bytes, returns truthy value
    # - +challenge_store+          — object responding to +store(sha256, challenge)+ and
    #                                +fetch(sha256)+ for persisting issued challenges.
    #                                Defaults to a new +MemoryChallengeStore+.
    class Configuration
      attr_accessor :payee_locking_script_hex,
                    :amount_sats,
                    :nonce_provider,
                    :broadcaster,
                    :expires_in,
                    :bound_headers,
                    :on_payment_verified,
                    :settlement_verifier,
                    :challenge_store

      def initialize
        @payee_locking_script_hex = nil
        @amount_sats              = 100
        @nonce_provider           = nil
        @broadcaster              = nil
        @expires_in               = 300
        @bound_headers            = []
        @on_payment_verified      = nil
        @settlement_verifier      = nil
        @challenge_store          = MemoryChallengeStore.new
      end
    end
  end
end
