# frozen_string_literal: true

module BSV
  module Transaction
    # Error raised during SPV verification.
    #
    # Carries a machine-readable code alongside a human-readable message,
    # matching the typed error pattern used by the Go SDK
    # (ErrInvalidMerklePath, ErrFeeTooLow, ErrScriptVerificationFailed).
    #
    # == Error Codes
    #
    # - +:invalid_merkle_proof+ — merkle path verification failed against the chain tracker
    # - +:insufficient_fee+ — transaction fee is below the fee model's requirement
    # - +:output_overflow+ — total outputs exceed total inputs
    # - +:script_failure+ — script interpreter rejected an input (original +ScriptError+ in +#cause+)
    # - +:missing_source+ — required input data (unlocking script, source locking script,
    #   or source satoshis) is absent
    class VerificationError < StandardError
      # @return [Symbol] the error code
      attr_reader :code

      INVALID_MERKLE_PROOF = :invalid_merkle_proof
      INSUFFICIENT_FEE = :insufficient_fee
      OUTPUT_OVERFLOW = :output_overflow
      SCRIPT_FAILURE = :script_failure
      MISSING_SOURCE = :missing_source

      # @param code [Symbol] error code
      # @param message [String] human-readable description
      def initialize(code, message)
        @code = code
        super(message)
      end
    end
  end
end
