# frozen_string_literal: true

module BSV
  module Script
    class Interpreter
      module Operations
        # Flow control operations: IF, NOTIF, ELSE, ENDIF, VERIFY, RETURN, NOP.
        module FlowControl
          private

          # OP_IF: conditional execution
          def op_if
            if @cond_stack.length >= MAX_CONDITIONAL_DEPTH
              raise ScriptError.new(
                ScriptErrorCode::UNBALANCED_CONDITIONAL,
                "conditional depth exceeded #{MAX_CONDITIONAL_DEPTH}"
              )
            end

            if branch_executing?
              @cond_stack.push(@dstack.pop_bool ? :true : :false)
            else
              @cond_stack.push(:false)
            end
            @else_stack.push(false)
          end

          # OP_NOTIF: inverse conditional execution
          def op_notif
            if @cond_stack.length >= MAX_CONDITIONAL_DEPTH
              raise ScriptError.new(
                ScriptErrorCode::UNBALANCED_CONDITIONAL,
                "conditional depth exceeded #{MAX_CONDITIONAL_DEPTH}"
              )
            end

            if branch_executing?
              @cond_stack.push(@dstack.pop_bool ? :false : :true)
            else
              @cond_stack.push(:false)
            end
            @else_stack.push(false)
          end

          # OP_ELSE: toggle the current conditional branch.
          #
          # Multi-ELSE handling matches the TS SDK (Spend.ts OP_ELSE case):
          # - In relaxed mode (no explicit flags), each ELSE toggles the branch —
          #   any number of ELSEs per IF is valid. This is the script-021 case.
          # - With explicit post-genesis flags, only one ELSE per IF is permitted;
          #   a second ELSE raises UNBALANCED_CONDITIONAL. Vectors such as
          #   node.script.bitcoin-sv.0731 and teranode.0057 enforce this.
          def op_else
            raise ScriptError.new(ScriptErrorCode::UNBALANCED_CONDITIONAL, 'OP_ELSE without matching OP_IF') if @cond_stack.empty?

            already_seen_else = @else_stack.pop
            if already_seen_else && explicit_flags? && after_genesis?
              raise ScriptError.new(ScriptErrorCode::UNBALANCED_CONDITIONAL, 'duplicate OP_ELSE')
            end

            case @cond_stack.last
            when :true  then @cond_stack[-1] = :false
            when :false then @cond_stack[-1] = :true
            end

            @else_stack.push(true)
          end

          # OP_ENDIF: close conditional block
          def op_endif
            raise ScriptError.new(ScriptErrorCode::UNBALANCED_CONDITIONAL, 'OP_ENDIF without matching OP_IF') if @cond_stack.empty?

            @cond_stack.pop
            @else_stack.pop
          end

          # OP_VERIFY: pop top, fail if false
          def op_verify
            return if @dstack.pop_bool

            raise ScriptError.new(ScriptErrorCode::VERIFY_FAILED, 'OP_VERIFY failed')
          end

          # OP_RETURN: after-genesis early termination.
          # At top level (outside conditionals): immediate success.
          # Inside a conditional: remaining opcodes are skipped but conditional
          # balance is still checked at script end.
          def op_return
            if @cond_stack.empty?
              @early_return = true
            else
              @after_op_return = true
            end
          end

          # OP_NOP and OP_NOP1..OP_NOP10 (including CLTV/CSV treated as NOP)
          def op_nop; end

          # OP_RESERVED, OP_RESERVED1, OP_RESERVED2: fail when executing
          def op_reserved(opcode)
            raise ScriptError.new(
              ScriptErrorCode::RESERVED_OPCODE,
              "attempt to execute reserved opcode: 0x#{opcode.to_s(16).rjust(2, '0')}"
            )
          end

          # OP_VER: push 4-byte little-endian transaction version onto the stack.
          #
          # Resolves the version from +@tx.version+ (when verifying a
          # transaction) or from the +tx_version:+ parameter passed to
          # +Interpreter.evaluate+. Raises MISSING_TX_CONTEXT only if neither
          # is available.
          #
          # The version is always encoded as exactly 4 bytes (LE uint32), never as
          # a ScriptNumber. Version 1 → 01000000, version 2 → 02000000.
          def op_ver
            bytes = tx_version_bytes
            if bytes.nil?
              raise ScriptError.new(
                ScriptErrorCode::MISSING_TX_CONTEXT,
                'OP_VER requires transaction context'
              )
            end

            @dstack.push_bytes(bytes)
          end

          # OP_VERIF: version-conditional branch — executes like OP_IF but compares
          # the top stack item against the 4-byte LE transaction version rather than
          # interpreting the item as a boolean.
          #
          # In an executing branch: pops bytes from the stack. If the bytes are
          # exactly 4 bytes and match the current transaction version, the true
          # branch executes; otherwise the false/else branch executes.
          #
          # In a non-executing branch: pushes +:false+ to track nesting depth
          # without touching the data stack.
          #
          # If @tx is nil, +tx_version_matches?+ returns false — the else branch
          # is always taken (not an error, unlike OP_VER).
          def op_verif
            if @cond_stack.length >= MAX_CONDITIONAL_DEPTH
              raise ScriptError.new(
                ScriptErrorCode::UNBALANCED_CONDITIONAL,
                "conditional depth exceeded #{MAX_CONDITIONAL_DEPTH}"
              )
            end

            if branch_executing?
              data = @dstack.pop_bytes
              @cond_stack.push(tx_version_matches?(data) ? :true : :false)
            else
              @cond_stack.push(:false)
            end
            @else_stack.push(false)
          end

          # OP_VERNOTIF: inverse version-conditional branch — executes like OP_NOTIF
          # but compares against the 4-byte LE transaction version.
          #
          # In an executing branch: match → false branch (else), no match → true branch.
          # In a non-executing branch: pushes +:false+ for nesting tracking only.
          def op_vernotif
            if @cond_stack.length >= MAX_CONDITIONAL_DEPTH
              raise ScriptError.new(
                ScriptErrorCode::UNBALANCED_CONDITIONAL,
                "conditional depth exceeded #{MAX_CONDITIONAL_DEPTH}"
              )
            end

            if branch_executing?
              data = @dstack.pop_bytes
              @cond_stack.push(tx_version_matches?(data) ? :false : :true)
            else
              @cond_stack.push(:false)
            end
            @else_stack.push(false)
          end

          # Returns the transaction version as a 4-byte little-endian binary
          # string, or +nil+ if no version is available. Used by OP_VER,
          # OP_VERIF, and OP_VERNOTIF. Prefers +@tx.version+ when verifying a
          # transaction; falls back to the +tx_version:+ argument used by
          # evaluate-without-tx (e.g. conformance corpus runs).
          def tx_version_bytes
            v = @tx&.version || @tx_version
            v.nil? ? nil : [v].pack('V')
          end

          # Compares raw bytes against the current transaction version.
          # Returns false if:
          # - +data+ is not exactly 4 bytes
          # - no version is available (neither @tx nor @tx_version set)
          # - the bytes do not match the 4-byte LE encoding of the version
          def tx_version_matches?(data)
            return false if data.bytesize != 4

            bytes = tx_version_bytes
            !bytes.nil? && data == bytes
          end
        end
      end
    end
  end
end
