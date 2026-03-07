# frozen_string_literal: true

module BSV
  module Transaction
    # Error raised during SPV verification.
    #
    # Carries a machine-readable code alongside a human-readable message,
    # matching the typed error pattern used by the Go SDK
    # (ErrInvalidMerklePath, ErrFeeTooLow, ErrScriptVerificationFailed).
    class VerificationError < StandardError
      # @return [Symbol] the error code
      attr_reader :code

      INVALID_MERKLE_PROOF = :invalid_merkle_proof
      INSUFFICIENT_FEE = :insufficient_fee
      OUTPUT_OVERFLOW = :output_overflow

      # @param code [Symbol] error code
      # @param message [String] human-readable description
      def initialize(code, message)
        @code = code
        super(message)
      end
    end
  end
end
