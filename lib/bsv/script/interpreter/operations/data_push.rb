# frozen_string_literal: true

module BSV
  module Script
    class Interpreter
      module Operations
        module DataPush
          private

          # OP_0 / OP_FALSE: push empty byte array
          def op_false
            @dstack.push_bytes(''.b)
          end

          # OP_1NEGATE: push -1
          def op_1negate
            @dstack.push_int(ScriptNumber.new(-1))
          end

          # OP_1..OP_16: push the corresponding integer value
          def op_n(opcode)
            @dstack.push_int(ScriptNumber.new(opcode - Opcodes::OP_1 + 1))
          end

          # Data push: chunk carries its own data
          def op_push_data(chunk)
            @dstack.push_bytes(chunk.data)
          end
        end
      end
    end
  end
end
