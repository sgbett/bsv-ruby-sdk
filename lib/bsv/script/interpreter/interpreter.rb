# frozen_string_literal: true

require_relative 'error'
require_relative 'script_number'
require_relative 'stack'
require_relative 'operations/data_push'
require_relative 'operations/stack_ops'
require_relative 'operations/flow_control'
require_relative 'operations/bitwise'
require_relative 'operations/arithmetic'
require_relative 'operations/splice'
require_relative 'operations/crypto'

module BSV
  module Script
    # Bitcoin script interpreter implementing the post-Genesis BSV script engine.
    #
    # Evaluates unlock + lock script pairs, supporting the full BSV opcode set
    # including restored opcodes (OP_MUL, OP_LSHIFT, OP_CAT, etc.) and
    # post-Genesis rules (OP_RETURN as early success, no script size limits).
    #
    # @example Evaluate scripts without transaction context
    #   BSV::Script::Interpreter.evaluate(unlock_script, lock_script)
    #
    # @example Verify a transaction input
    #   BSV::Script::Interpreter.verify(
    #     tx: transaction, input_index: 0,
    #     unlock_script: input.script, lock_script: prev_output.script,
    #     satoshis: prev_output.satoshis
    #   )
    class Interpreter
      include Operations::DataPush
      include Operations::StackOps
      include Operations::FlowControl
      include Operations::Bitwise
      include Operations::Arithmetic
      include Operations::Splice
      include Operations::Crypto

      attr_reader :dstack, :astack

      # Conditional opcodes must be processed even in non-executing branches
      # to maintain correct nesting depth.
      CONDITIONAL_OPCODES = [
        Opcodes::OP_IF, Opcodes::OP_NOTIF, Opcodes::OP_ELSE, Opcodes::OP_ENDIF
      ].freeze

      # Maximum nesting depth for OP_IF / OP_NOTIF blocks. Prevents interpreter
      # stack overflow from deeply nested conditionals.
      MAX_CONDITIONAL_DEPTH = 256

      # Evaluate unlock + lock scripts without transaction context.
      #
      # Signature operations will always fail (no sighash available).
      #
      # @param unlock_script [Script] the unlocking script
      # @param lock_script [Script] the locking script
      # @return [Boolean] +true+ if execution succeeds
      # @raise [ScriptError] if script execution fails
      def self.evaluate(unlock_script, lock_script)
        new(
          unlock_script: unlock_script,
          lock_script: lock_script
        ).execute
      end

      # Verify a transaction input by evaluating its scripts.
      #
      # @param tx [Transaction::Transaction] the transaction being verified
      # @param input_index [Integer] the input index within the transaction
      # @param unlock_script [Script] the input's unlocking script
      # @param lock_script [Script] the previous output's locking script
      # @param satoshis [Integer] the value of the previous output in satoshis
      # @return [Boolean] +true+ if verification succeeds
      # @raise [ScriptError] if script execution fails
      def self.verify(tx:, input_index:, unlock_script:, lock_script:, satoshis:)
        new(
          unlock_script: unlock_script,
          lock_script: lock_script,
          tx: tx,
          input_index: input_index,
          satoshis: satoshis
        ).execute
      end

      def execute
        scripts = [@unlock_script, @lock_script]

        scripts.each_with_index do |script, script_idx|
          @current_script = script
          chunks = script.chunks

          chunks.each_with_index do |chunk, chunk_idx|
            @current_chunk_idx = chunk_idx
            execute_opcode(chunk)
            break if @early_return
          end

          break if @early_return && script_idx == 1

          # Between scripts: verify conditionals balanced
          raise ScriptError.new(ScriptErrorCode::UNBALANCED_CONDITIONAL, 'unbalanced conditional') unless @cond_stack.empty?

          # Clear alt stack between scripts
          @astack.clear

          # Reset state for next script
          @last_code_sep = 0
          @early_return = false
          @after_op_return = false
        end

        check_final_stack
        true
      end

      private

      def initialize(unlock_script:, lock_script:, tx: nil, input_index: nil, satoshis: nil)
        @unlock_script = unlock_script
        @lock_script = lock_script
        @tx = tx
        @input_index = input_index
        @satoshis = satoshis

        @dstack = Stack.new
        @astack = Stack.new
        @cond_stack = []
        @else_stack = []
        @last_code_sep = 0
        @early_return = false
        @after_op_return = false
        @current_script = nil
        @current_chunk_idx = 0
      end

      def execute_opcode(chunk)
        opcode = chunk.opcode

        # After OP_RETURN inside a conditional: only process flow control opcodes
        # and OP_RETURN itself (which may terminate at top level once conditionals
        # are balanced), matching Go SDK's branchExecuting semantics.
        if @after_op_return
          dispatch_opcode(opcode, chunk) if conditional_opcode?(opcode) || opcode == Opcodes::OP_RETURN
          return
        end

        # In non-executing branch: only dispatch conditional opcodes (for nesting tracking).
        # All other opcodes are skipped.
        unless branch_executing?
          dispatch_opcode(opcode, chunk) if conditional_opcode?(opcode)
          return
        end

        dispatch_opcode(opcode, chunk)
      end

      def dispatch_opcode(opcode, chunk)
        case opcode
        # --- Data push ---
        when Opcodes::OP_0
          op_false
        when Opcodes::OP_1NEGATE
          op_1negate
        when Opcodes::OP_1..Opcodes::OP_16
          op_n(opcode)
        when 0x01..0x4b, Opcodes::OP_PUSHDATA1, Opcodes::OP_PUSHDATA2, Opcodes::OP_PUSHDATA4
          op_push_data(chunk)

        # --- Flow control ---
        when Opcodes::OP_NOP, Opcodes::OP_NOP1, Opcodes::OP_CHECKLOCKTIMEVERIFY,
             Opcodes::OP_CHECKSEQUENCEVERIFY, Opcodes::OP_NOP9, Opcodes::OP_NOP10
          op_nop
        when Opcodes::OP_IF then op_if
        when Opcodes::OP_NOTIF then op_notif
        when Opcodes::OP_ELSE then op_else
        when Opcodes::OP_ENDIF then op_endif
        when Opcodes::OP_VERIFY then op_verify
        when Opcodes::OP_RETURN then op_return
        when Opcodes::OP_RESERVED, Opcodes::OP_RESERVED1, Opcodes::OP_RESERVED2
          op_reserved(opcode)
        # Chronicle fail-safe: OP_VER, OP_VERIF, OP_VERNOTIF, and the Chronicle
        # string/shift slots raise UnimplementedOpcode. Full semantics are
        # deferred to SDK v0.10.
        when Opcodes::OP_VER, Opcodes::OP_VERIF, Opcodes::OP_VERNOTIF,
             Opcodes::OP_SUBSTR, Opcodes::OP_LEFT, Opcodes::OP_RIGHT,
             Opcodes::OP_LSHIFTNUM, Opcodes::OP_RSHIFTNUM
          op_unimplemented(opcode)

        # --- Stack manipulation ---
        when Opcodes::OP_TOALTSTACK then op_toaltstack
        when Opcodes::OP_FROMALTSTACK then op_fromaltstack
        when Opcodes::OP_IFDUP then op_ifdup
        when Opcodes::OP_DEPTH then op_depth
        when Opcodes::OP_DROP then op_drop
        when Opcodes::OP_2DROP then op_2drop
        when Opcodes::OP_DUP then op_dup
        when Opcodes::OP_2DUP then op_2dup
        when Opcodes::OP_3DUP then op_3dup
        when Opcodes::OP_NIP then op_nip
        when Opcodes::OP_OVER then op_over
        when Opcodes::OP_2OVER then op_2over
        when Opcodes::OP_PICK then op_pick
        when Opcodes::OP_ROLL then op_roll
        when Opcodes::OP_ROT then op_rot
        when Opcodes::OP_2ROT then op_2rot
        when Opcodes::OP_SWAP then op_swap
        when Opcodes::OP_2SWAP then op_2swap
        when Opcodes::OP_TUCK then op_tuck

        # --- Splice ---
        when Opcodes::OP_CAT then op_cat
        when Opcodes::OP_SPLIT then op_split
        when Opcodes::OP_NUM2BIN then op_num2bin
        when Opcodes::OP_BIN2NUM then op_bin2num
        when Opcodes::OP_SIZE then op_size

        # --- Bitwise ---
        when Opcodes::OP_EQUAL then op_equal
        when Opcodes::OP_EQUALVERIFY then op_equalverify
        when Opcodes::OP_AND then op_and
        when Opcodes::OP_OR then op_or
        when Opcodes::OP_XOR then op_xor
        when Opcodes::OP_INVERT then op_invert

        # --- Arithmetic ---
        when Opcodes::OP_1ADD then op_1add
        when Opcodes::OP_1SUB then op_1sub
        when Opcodes::OP_2MUL, Opcodes::OP_2DIV
          op_disabled(opcode)
        when Opcodes::OP_NEGATE then op_negate
        when Opcodes::OP_ABS then op_abs
        when Opcodes::OP_NOT then op_not
        when Opcodes::OP_0NOTEQUAL then op_0notequal
        when Opcodes::OP_ADD then op_add
        when Opcodes::OP_SUB then op_sub
        when Opcodes::OP_MUL then op_mul
        when Opcodes::OP_DIV then op_div
        when Opcodes::OP_MOD then op_mod
        when Opcodes::OP_LSHIFT then op_lshift
        when Opcodes::OP_RSHIFT then op_rshift
        when Opcodes::OP_BOOLAND then op_booland
        when Opcodes::OP_BOOLOR then op_boolor
        when Opcodes::OP_NUMEQUAL then op_numequal
        when Opcodes::OP_NUMEQUALVERIFY then op_numequalverify
        when Opcodes::OP_NUMNOTEQUAL then op_numnotequal
        when Opcodes::OP_LESSTHAN then op_lessthan
        when Opcodes::OP_GREATERTHAN then op_greaterthan
        when Opcodes::OP_LESSTHANOREQUAL then op_lessthanorequal
        when Opcodes::OP_GREATERTHANOREQUAL then op_greaterthanorequal
        when Opcodes::OP_MIN then op_min
        when Opcodes::OP_MAX then op_max
        when Opcodes::OP_WITHIN then op_within

        # --- Crypto ---
        when Opcodes::OP_RIPEMD160 then op_ripemd160
        when Opcodes::OP_SHA1 then op_sha1
        when Opcodes::OP_SHA256 then op_sha256
        when Opcodes::OP_HASH160 then op_hash160
        when Opcodes::OP_HASH256 then op_hash256
        when Opcodes::OP_CODESEPARATOR then op_codeseparator
        when Opcodes::OP_CHECKSIG then op_checksig
        when Opcodes::OP_CHECKSIGVERIFY then op_checksigverify
        when Opcodes::OP_CHECKMULTISIG then op_checkmultisig
        when Opcodes::OP_CHECKMULTISIGVERIFY then op_checkmultisigverify

        else
          raise ScriptError.new(
            ScriptErrorCode::INVALID_OPCODE,
            "unhandled opcode: 0x#{opcode.to_s(16).rjust(2, '0')}"
          )
        end
      end

      # Is the current conditional branch executing?
      # Checks ALL entries — a :false anywhere means we're not executing.
      def branch_executing?
        @cond_stack.none? { |v| v == :false }
      end

      def conditional_opcode?(opcode)
        CONDITIONAL_OPCODES.include?(opcode)
      end

      # Verify final stack state: must have at least one truthy element on top.
      def check_final_stack
        raise ScriptError.new(ScriptErrorCode::EMPTY_STACK, 'stack empty at end of script execution') if @dstack.empty?

        return if @dstack.pop_bool

        raise ScriptError.new(ScriptErrorCode::EVAL_FALSE, 'false stack entry at end of script execution')
      end
    end
  end
end
