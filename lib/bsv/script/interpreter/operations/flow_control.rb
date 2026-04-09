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

          # OP_ELSE: toggle conditional branch (only one ELSE per IF after genesis)
          def op_else
            raise ScriptError.new(ScriptErrorCode::UNBALANCED_CONDITIONAL, 'OP_ELSE without matching OP_IF') if @cond_stack.empty?

            # After genesis: only one ELSE per IF
            raise ScriptError.new(ScriptErrorCode::UNBALANCED_CONDITIONAL, 'duplicate OP_ELSE') if @else_stack.pop

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

          # Chronicle fail-safe: OP_VER, OP_VERIF, OP_VERNOTIF and the Chronicle
          # string/shift slots (OP_SUBSTR, OP_LEFT, OP_RIGHT, OP_LSHIFTNUM,
          # OP_RSHIFTNUM). Full semantics are deferred to SDK v0.10. Any script
          # that reaches one of these opcodes will fail loudly rather than
          # silently succeeding.
          def op_unimplemented(opcode)
            raise ScriptError.new(
              ScriptErrorCode::UNIMPLEMENTED_OPCODE,
              "unimplemented opcode: 0x#{opcode.to_s(16).rjust(2, '0')}"
            )
          end
        end
      end
    end
  end
end
