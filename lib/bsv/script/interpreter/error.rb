# frozen_string_literal: true

module BSV
  module Script
    class ScriptError < StandardError
      attr_reader :code

      def initialize(code, message = nil)
        @code = code
        super(message || code.to_s.tr('_', ' '))
      end
    end

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
      INVALID_SIGHASH_TYPE = :invalid_sighash_type
      EARLY_RETURN = :early_return
      INVALID_OPCODE = :invalid_opcode
      MINIMAL_DATA = :minimal_data
    end
  end
end
