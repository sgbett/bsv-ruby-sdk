# frozen_string_literal: true

module BSV
  module Script
    class Interpreter
      module Operations
        # Bitwise and equality operations: EQUAL, AND, OR, XOR, INVERT.
        module Bitwise
          private

          # OP_EQUAL: push true if top two items are byte-equal
          def op_equal
            a = @dstack.pop_bytes
            b = @dstack.pop_bytes
            @dstack.push_bool(a == b)
          end

          # OP_EQUALVERIFY: OP_EQUAL then OP_VERIFY
          def op_equalverify
            op_equal
            return if @dstack.pop_bool

            raise ScriptError.new(ScriptErrorCode::EQUALVERIFY_FAILED, 'OP_EQUALVERIFY failed')
          end

          # OP_AND: bitwise AND (equal-length byte arrays)
          def op_and
            a, b = pop_equal_length_pair
            result = a.bytes.zip(b.bytes).map { |x, y| x & y }.pack('C*')
            @dstack.push_bytes(result)
          end

          # OP_OR: bitwise OR (equal-length byte arrays)
          def op_or
            a, b = pop_equal_length_pair
            result = a.bytes.zip(b.bytes).map { |x, y| x | y }.pack('C*')
            @dstack.push_bytes(result)
          end

          # OP_XOR: bitwise XOR (equal-length byte arrays)
          def op_xor
            a, b = pop_equal_length_pair
            result = a.bytes.zip(b.bytes).map { |x, y| x ^ y }.pack('C*')
            @dstack.push_bytes(result)
          end

          # OP_INVERT: bitwise NOT (flip all bits)
          def op_invert
            a = @dstack.pop_bytes
            result = a.bytes.map { |byte| byte ^ 0xff }.pack('C*')
            @dstack.push_bytes(result)
          end

          # Pop two byte arrays, ensuring equal length
          def pop_equal_length_pair
            a = @dstack.pop_bytes
            b = @dstack.pop_bytes
            if a.bytesize != b.bytesize
              raise ScriptError.new(ScriptErrorCode::INVALID_INPUT_LENGTH, 'byte arrays are not the same length')
            end

            [a, b]
          end
        end
      end
    end
  end
end
