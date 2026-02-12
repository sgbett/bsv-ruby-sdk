# frozen_string_literal: true

require_relative 'error'
require_relative 'script_number'
require_relative 'stack'
require_relative 'operations/data_push'
require_relative 'operations/stack_ops'

module BSV
  module Script
    class Interpreter # rubocop:disable Metrics/ClassLength
      include Operations::DataPush
      include Operations::StackOps

      attr_reader :dstack, :astack

      # Evaluate unlock + lock scripts without transaction context.
      # Signature operations will always fail (no sighash available).
      def self.evaluate(unlock_script, lock_script)
        new(
          unlock_script: unlock_script,
          lock_script: lock_script
        ).execute
      end

      # Verify a transaction input by evaluating its scripts.
      def self.verify(tx:, input_index:, unlock_script:, lock_script:, satoshis:)
        new(
          unlock_script: unlock_script,
          lock_script: lock_script,
          tx: tx,
          input_index: input_index,
          satoshis: satoshis
        ).execute
      end

      def execute # rubocop:disable Naming/PredicateMethod
        scripts = [@unlock_script, @lock_script]

        scripts.each_with_index do |script, script_idx|
          chunks = script.chunks

          chunks.each do |chunk|
            execute_opcode(chunk)
            break if @early_return
          end

          break if @early_return && script_idx == 1

          # Between scripts: verify conditionals balanced
          unless @cond_stack.empty?
            raise ScriptError.new(ScriptErrorCode::UNBALANCED_CONDITIONAL, 'unbalanced conditional')
          end

          # Clear alt stack between scripts
          @astack.clear

          # Reset state for next script
          @last_code_sep = 0
          @early_return = false
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
      end

      def execute_opcode(chunk)
        opcode = chunk.opcode

        # Conditional execution check: if we're in a non-executing branch,
        # only process conditional opcodes (IF/NOTIF/ELSE/ENDIF).
        # This will be implemented in Phase 3 (flow control).
        # For now, all opcodes execute unconditionally.
        unless branch_executing?
          return if conditional_opcode?(opcode)

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

        else
          raise ScriptError.new(
            ScriptErrorCode::INVALID_OPCODE,
            "unhandled opcode: 0x#{opcode.to_s(16).rjust(2, '0')}"
          )
        end
      end

      # Is the current conditional branch executing?
      # True when not inside any conditional, or inside a true branch.
      # Uses symbol :true (not boolean) because Phase 3 adds :false and :skip states.
      def branch_executing?
        @cond_stack.empty? || @cond_stack.last == :true # rubocop:disable Lint/BooleanSymbol
      end

      # Is this a conditional opcode that must be processed even in non-executing branches?
      def conditional_opcode?(_opcode)
        # Implemented in Phase 3 (flow control): OP_IF, OP_NOTIF, OP_ELSE, OP_ENDIF
        false
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
