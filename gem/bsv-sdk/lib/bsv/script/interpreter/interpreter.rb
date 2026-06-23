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
      # to maintain correct nesting depth. OP_VERIF and OP_VERNOTIF are included
      # here because they open conditional blocks (like OP_IF/OP_NOTIF) and must
      # be dispatched to track nesting depth even when the branch is not executing.
      # This matches the Go SDK's IsConditional() function.
      CONDITIONAL_OPCODES = [
        Opcodes::OP_IF, Opcodes::OP_NOTIF, Opcodes::OP_ELSE, Opcodes::OP_ENDIF,
        Opcodes::OP_VERIF, Opcodes::OP_VERNOTIF
      ].freeze

      # Maximum nesting depth for OP_IF / OP_NOTIF blocks. Prevents interpreter
      # stack overflow from deeply nested conditionals.
      MAX_CONDITIONAL_DEPTH = 256

      # Opcodes that require Chronicle to execute. With explicit flags but
      # without UTXO_AFTER_CHRONICLE, executing any of these raises
      # DISABLED_OPCODE. OP_VER / OP_VERIF / OP_VERNOTIF are included because
      # pre-Chronicle they're either reserved (OP_VER) or behave as a
      # conditional-only NOP in non-executing branches — execution itself is
      # disabled. Mirrors TS Spend.ts (lines ~694-709) and Go IsDisabled.
      CHRONICLE_ONLY_OPCODES = [
        Opcodes::OP_2MUL, Opcodes::OP_2DIV,
        Opcodes::OP_VER, Opcodes::OP_VERIF, Opcodes::OP_VERNOTIF
      ].freeze

      # Evaluate unlock + lock scripts without transaction context.
      #
      # Signature operations will always fail (no sighash available).
      #
      # @param unlock_script [Script] the unlocking script
      # @param lock_script [Script] the locking script
      # @param flags [Array<String>, Set<String>, nil] explicit verification flags
      #   (e.g. +SIGPUSHONLY+, +CLEANSTACK+, +UTXO_AFTER_CHRONICLE+). When +nil+,
      #   the interpreter runs in relaxed (post-Chronicle) mode.
      # @param tx_version [Integer, nil] transaction version made available to
      #   +OP_VER+/+OP_VERIF+/+OP_VERNOTIF+ when no transaction is supplied
      # @return [Boolean] +true+ if execution succeeds
      # @raise [ScriptError] if script execution fails
      def self.evaluate(unlock_script, lock_script, flags: nil, tx_version: nil)
        new(
          unlock_script: unlock_script,
          lock_script: lock_script,
          flags: flags,
          tx_version: tx_version
        ).execute
      end

      # Verify a transaction input by evaluating its scripts.
      #
      # @param tx [Transaction::Tx] the transaction being verified
      # @param input_index [Integer] the input index within the transaction
      # @param unlock_script [Script] the input's unlocking script
      # @param lock_script [Script] the previous output's locking script
      # @param satoshis [Integer] the value of the previous output in satoshis
      # @param flags [Array<String>, Set<String>, nil] explicit verification flags
      # @return [Boolean] +true+ if verification succeeds
      # @raise [ScriptError] if script execution fails
      def self.verify(tx:, input_index:, unlock_script:, lock_script:, satoshis:, flags: nil)
        new(
          unlock_script: unlock_script,
          lock_script: lock_script,
          tx: tx,
          input_index: input_index,
          satoshis: satoshis,
          flags: flags
        ).execute
      end

      def execute
        enforce_sig_pushonly

        scripts = [@unlock_script, @lock_script]
        script_names = %w[unlock_script lock_script]

        scripts.each_with_index do |script, script_idx|
          @current_script = script
          chunks = script.chunks
          BSV.logger&.debug { "[Interpreter] === #{script_names[script_idx]} (#{chunks.length} chunks) ===" }

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
        BSV.logger&.debug { "[Interpreter] final stack: #{@dstack.length} items -> success" }
        true
      end

      private

      def initialize(unlock_script:, lock_script:, tx: nil, input_index: nil, satoshis: nil,
                     flags: nil, tx_version: nil)
        @unlock_script = unlock_script
        @lock_script = lock_script
        @tx = tx
        @input_index = input_index
        @satoshis = satoshis
        @flags = flags.nil? ? nil : Set.new(flags.map(&:to_s))
        @tx_version = tx_version

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

      # Whether explicit verification flags were supplied.
      # In their absence the interpreter behaves as if Chronicle is active and
      # the unlock-script maleability flags are off (matches the TS SDK's
      # +isRelaxed+ default — see Spend.ts).
      def explicit_flags?
        !@flags.nil?
      end

      def flag?(name)
        explicit_flags? && @flags.include?(name)
      end

      # Whether post-Chronicle semantics apply (OP_2MUL/2DIV enabled,
      # OP_VER/OP_VERIF/OP_VERNOTIF interpret +tx_version+).
      def chronicle?
        return flag?('UTXO_AFTER_CHRONICLE') if explicit_flags?

        true
      end

      # Whether post-Genesis rules apply. With explicit flags this requires one
      # of the genesis-era flags; without, the interpreter is always post-Genesis.
      def after_genesis?
        return flag?('GENESIS') || flag?('UTXO_AFTER_GENESIS') || flag?('UTXO_AFTER_CHRONICLE') if explicit_flags?

        true
      end

      def enforce_sig_pushonly?
        return flag?('SIGPUSHONLY') if explicit_flags?

        false
      end

      def enforce_sig_pushonly
        return unless enforce_sig_pushonly?
        return if @unlock_script.push_only?

        raise ScriptError.new(
          ScriptErrorCode::SIG_PUSHONLY,
          'unlock script must contain only push-data operations'
        )
      end

      def enforce_clean_stack?
        return flag?('CLEANSTACK') if explicit_flags?

        false
      end

      def enforce_clean_stack
        return unless enforce_clean_stack?
        return if @dstack.length == 1

        raise ScriptError.new(
          ScriptErrorCode::CLEAN_STACK,
          "CLEANSTACK requires exactly one stack item at end (found #{@dstack.length})"
        )
      end

      def execute_opcode(chunk)
        opcode = chunk.opcode

        # Pre-Chronicle, pre-Genesis mode (explicit non-genesis flags) treats
        # OP_VER / OP_VERIF / OP_VERNOTIF as universally illegal — they raise
        # even in a non-executing branch. Mirrors TS Spend.ts line ~700.
        enforce_pre_genesis_ver_gate(opcode)

        # After OP_RETURN inside a conditional: only process flow control opcodes
        # and OP_RETURN itself (which may terminate at top level once conditionals
        # are balanced), matching Go SDK's branchExecuting semantics.
        if @after_op_return
          if conditional_opcode?(opcode) || opcode == Opcodes::OP_RETURN
            return if skipped_ver_conditional?(opcode)

            dispatch_opcode(opcode, chunk)
          end
          return
        end

        # In non-executing branch: only dispatch conditional opcodes (for nesting tracking).
        # All other opcodes are skipped.
        unless branch_executing?
          if conditional_opcode?(opcode)
            return if skipped_ver_conditional?(opcode)

            dispatch_opcode(opcode, chunk)
          end
          return
        end

        enforce_chronicle_gate(opcode)

        BSV.logger&.debug do
          name = Opcodes.name_for(opcode) || format('0x%02x', opcode)
          "[Interpreter]   #{name} (stack: #{@dstack.length})"
        end
        dispatch_opcode(opcode, chunk)
      end

      def enforce_chronicle_gate(opcode)
        return unless CHRONICLE_ONLY_OPCODES.include?(opcode)
        return if chronicle?

        raise ScriptError.new(
          ScriptErrorCode::DISABLED_OPCODE,
          "#{Opcodes.name_for(opcode) || format('0x%02x', opcode)} is disabled outside Chronicle"
        )
      end

      # OP_VERIF / OP_VERNOTIF in a non-executing branch are conditional opcodes
      # post-Chronicle (push to cond_stack, like OP_IF in a non-executing branch),
      # but a complete NOP pre-Chronicle post-genesis — they neither push nor
      # consume. This matches TS Spend.ts (line ~710) and Go opcodeVerConditional.
      def skipped_ver_conditional?(opcode)
        !chronicle? && after_genesis? &&
          [Opcodes::OP_VERIF, Opcodes::OP_VERNOTIF].include?(opcode)
      end

      # Pre-Genesis VERIF / VERNOTIF are unconditionally illegal (even in
      # non-executing branches — they enter the dispatcher as conditional opcodes).
      # OP_VER pre-Genesis is illegal only when executing; in a non-executing
      # branch it's skipped silently. Mirrors the Bitcoin Core script test
      # rule "VER non-functional (ok if not executed); VERIF illegal everywhere".
      def enforce_pre_genesis_ver_gate(opcode)
        return unless explicit_flags? && !after_genesis?
        return unless [Opcodes::OP_VERIF, Opcodes::OP_VERNOTIF].include?(opcode)

        raise ScriptError.new(
          ScriptErrorCode::DISABLED_OPCODE,
          "#{Opcodes.name_for(opcode) || format('0x%02x', opcode)} is illegal pre-Genesis"
        )
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
        when Opcodes::OP_VER then op_ver
        when Opcodes::OP_VERIF then op_verif
        when Opcodes::OP_VERNOTIF then op_vernotif

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
        when Opcodes::OP_SUBSTR then op_substr
        when Opcodes::OP_LEFT then op_left
        when Opcodes::OP_RIGHT then op_right

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
        when Opcodes::OP_2MUL then op_2mul
        when Opcodes::OP_2DIV then op_2div
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
        when Opcodes::OP_LSHIFTNUM then op_lshiftnum
        when Opcodes::OP_RSHIFTNUM then op_rshiftnum
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
      # When the CLEANSTACK flag is set, additionally requires exactly one item.
      def check_final_stack
        raise ScriptError.new(ScriptErrorCode::EMPTY_STACK, 'stack empty at end of script execution') if @dstack.empty?

        enforce_clean_stack

        return if @dstack.pop_bool

        raise ScriptError.new(ScriptErrorCode::EVAL_FALSE, 'false stack entry at end of script execution')
      end
    end
  end
end
