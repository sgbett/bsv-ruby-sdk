# frozen_string_literal: true

module BSV
  module Script
    # Error raised during script execution.
    #
    # Carries a machine-readable error code from {ScriptErrorCode} alongside
    # a human-readable message.
    class ScriptError < StandardError
      # @return [Symbol] the error code from {ScriptErrorCode}
      attr_reader :code

      # @param code [Symbol] error code from {ScriptErrorCode}
      # @param message [String, nil] human-readable description (auto-generated from code if omitted)
      def initialize(code, message = nil)
        @code = code
        super(message || code.to_s.tr('_', ' '))
      end
    end

    # Error codes for script execution failures.
    #
    # Each constant corresponds to a specific script validation rule.
    module ScriptErrorCode
      EVAL_FALSE = :eval_false
      EMPTY_STACK = :empty_stack
      VERIFY_FAILED = :verify_failed
      EQUALVERIFY_FAILED = :equalverify_failed
      NUMEQUALVERIFY_FAILED = :numequalverify_failed
      CHECKSIGVERIFY_FAILED = :checksigverify_failed
      CHECKMULTISIGVERIFY_FAILED = :checkmultisigverify_failed
      UNBALANCED_CONDITIONAL = :unbalanced_conditional
      DISABLED_OPCODE = :disabled_opcode
      RESERVED_OPCODE = :reserved_opcode
      INVALID_STACK_OPERATION = :invalid_stack_operation
      MALFORMED_PUSH = :malformed_push
      NUMBER_TOO_BIG = :number_too_big
      DIVIDE_BY_ZERO = :divide_by_zero
      INVALID_INPUT_LENGTH = :invalid_input_length
      INVALID_PUBKEY_COUNT = :invalid_pubkey_count
      INVALID_SIG_COUNT = :invalid_sig_count
      SIG_NULLFAIL = :sig_nullfail
      SIG_NULLDUMMY = :sig_nulldummy
      SIG_DER = :sig_der
      SIG_HIGH_S = :sig_high_s
      PUBKEY_TYPE = :pubkey_type
      INVALID_SIGHASH_TYPE = :invalid_sighash_type
      EARLY_RETURN = :early_return
      IMPOSSIBLE_ENCODING = :impossible_encoding
      INVALID_OPCODE = :invalid_opcode
      MINIMAL_DATA = :minimal_data
      STACK_MEMORY_EXCEEDED = :stack_memory_exceeded
      UNIMPLEMENTED_OPCODE = :unimplemented_opcode
    end
  end
end
