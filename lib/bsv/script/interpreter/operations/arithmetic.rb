# frozen_string_literal: true

module BSV
  module Script
    class Interpreter
      module Operations
        # Arithmetic and comparison operations including restored post-Genesis
        # opcodes: MUL, DIV, MOD, LSHIFT, RSHIFT.
        module Arithmetic
          private

          # OP_1ADD: increment top by 1
          def op_1add
            a = @dstack.pop_int
            @dstack.push_int(a + ScriptNumber.new(1))
          end

          # OP_1SUB: decrement top by 1
          def op_1sub
            a = @dstack.pop_int
            @dstack.push_int(a - ScriptNumber.new(1))
          end

          # OP_NEGATE: flip sign
          def op_negate
            a = @dstack.pop_int
            @dstack.push_int(-a)
          end

          # OP_ABS: absolute value
          def op_abs
            a = @dstack.pop_int
            @dstack.push_int(a.abs)
          end

          # OP_NOT: boolean NOT (0 -> 1, nonzero -> 0)
          def op_not
            a = @dstack.pop_int
            @dstack.push_int(ScriptNumber.new(a.zero? ? 1 : 0))
          end

          # OP_0NOTEQUAL: 0 -> 0, nonzero -> 1
          def op_0notequal
            a = @dstack.pop_int
            @dstack.push_int(ScriptNumber.new(a.zero? ? 0 : 1))
          end

          # OP_ADD: a + b
          def op_add
            b = @dstack.pop_int
            a = @dstack.pop_int
            @dstack.push_int(a + b)
          end

          # OP_SUB: a - b (second-to-top minus top)
          def op_sub
            b = @dstack.pop_int
            a = @dstack.pop_int
            @dstack.push_int(a - b)
          end

          # OP_MUL: a * b (re-enabled after genesis)
          def op_mul
            b = @dstack.pop_int
            a = @dstack.pop_int
            @dstack.push_int(a * b)
          end

          # OP_DIV: a / b truncated toward zero (re-enabled after genesis)
          def op_div
            b = @dstack.pop_int
            a = @dstack.pop_int
            @dstack.push_int(a / b)
          end

          # OP_MOD: a % b with sign of dividend (re-enabled after genesis)
          def op_mod
            b = @dstack.pop_int
            a = @dstack.pop_int
            @dstack.push_int(a % b)
          end

          # OP_LSHIFT: left-shift byte array by n bits (re-enabled after genesis)
          def op_lshift
            n = @dstack.pop_int.to_i32
            x = @dstack.pop_bytes
            raise ScriptError.new(ScriptErrorCode::INVALID_INPUT_LENGTH, 'shift amount negative') if n.negative?

            @dstack.push_bytes(byte_shift_left(x, n))
          end

          # OP_RSHIFT: right-shift byte array by n bits (re-enabled after genesis)
          def op_rshift
            n = @dstack.pop_int.to_i32
            x = @dstack.pop_bytes
            raise ScriptError.new(ScriptErrorCode::INVALID_INPUT_LENGTH, 'shift amount negative') if n.negative?

            @dstack.push_bytes(byte_shift_right(x, n))
          end

          # OP_BOOLAND: logical AND (both nonzero -> 1, else 0)
          def op_booland
            b = @dstack.pop_int
            a = @dstack.pop_int
            @dstack.push_int(ScriptNumber.new(!a.zero? && !b.zero? ? 1 : 0))
          end

          # OP_BOOLOR: logical OR (either nonzero -> 1, else 0)
          def op_boolor
            b = @dstack.pop_int
            a = @dstack.pop_int
            @dstack.push_int(ScriptNumber.new(!a.zero? || !b.zero? ? 1 : 0))
          end

          # OP_NUMEQUAL: a == b -> 1, else 0
          def op_numequal
            b = @dstack.pop_int
            a = @dstack.pop_int
            @dstack.push_int(ScriptNumber.new(a == b ? 1 : 0))
          end

          # OP_NUMEQUALVERIFY: OP_NUMEQUAL then OP_VERIFY
          def op_numequalverify
            op_numequal
            return if @dstack.pop_bool

            raise ScriptError.new(ScriptErrorCode::NUMEQUALVERIFY_FAILED, 'OP_NUMEQUALVERIFY failed')
          end

          # OP_NUMNOTEQUAL: a != b -> 1, else 0
          def op_numnotequal
            b = @dstack.pop_int
            a = @dstack.pop_int
            @dstack.push_int(ScriptNumber.new(a == b ? 0 : 1))
          end

          # OP_LESSTHAN: a < b -> 1, else 0
          def op_lessthan
            b = @dstack.pop_int
            a = @dstack.pop_int
            @dstack.push_int(ScriptNumber.new(a < b ? 1 : 0))
          end

          # OP_GREATERTHAN: a > b -> 1, else 0
          def op_greaterthan
            b = @dstack.pop_int
            a = @dstack.pop_int
            @dstack.push_int(ScriptNumber.new(a > b ? 1 : 0))
          end

          # OP_LESSTHANOREQUAL: a <= b -> 1, else 0
          def op_lessthanorequal
            b = @dstack.pop_int
            a = @dstack.pop_int
            @dstack.push_int(ScriptNumber.new(a <= b ? 1 : 0))
          end

          # OP_GREATERTHANOREQUAL: a >= b -> 1, else 0
          def op_greaterthanorequal
            b = @dstack.pop_int
            a = @dstack.pop_int
            @dstack.push_int(ScriptNumber.new(a >= b ? 1 : 0))
          end

          # OP_MIN: push the smaller of a, b
          def op_min
            b = @dstack.pop_int
            a = @dstack.pop_int
            @dstack.push_int([a, b].min)
          end

          # OP_MAX: push the larger of a, b
          def op_max
            b = @dstack.pop_int
            a = @dstack.pop_int
            @dstack.push_int([a, b].max)
          end

          # OP_WITHIN: min <= x < max -> 1, else 0
          # Stack: [... x min max]
          def op_within
            max = @dstack.pop_int
            min = @dstack.pop_int
            x = @dstack.pop_int
            @dstack.push_int(ScriptNumber.new(x >= min && x < max ? 1 : 0))
          end

          # OP_2MUL, OP_2DIV: disabled opcodes
          def op_disabled(opcode)
            raise ScriptError.new(
              ScriptErrorCode::DISABLED_OPCODE,
              "attempt to execute disabled opcode: 0x#{opcode.to_s(16).rjust(2, '0')}"
            )
          end

          # --- Byte-array shift helpers ---

          # Left-shift byte array by n bits, preserving length (big-endian bit order).
          def byte_shift_left(data, bits)
            len = data.bytesize
            return "\x00".b * len if bits >= len * 8

            byte_shift = bits / 8
            bit_shift = bits % 8
            result = "\x00".b * len

            (0...len).each do |i|
              src = i + byte_shift
              break if src >= len

              val = (data.getbyte(src) << bit_shift) & 0xff
              val |= data.getbyte(src + 1) >> (8 - bit_shift) if bit_shift.positive? && src + 1 < len
              result.setbyte(i, val)
            end

            result
          end

          # Right-shift byte array by n bits, preserving length (big-endian bit order).
          def byte_shift_right(data, bits)
            len = data.bytesize
            return "\x00".b * len if bits >= len * 8

            byte_shift = bits / 8
            bit_shift = bits % 8
            result = "\x00".b * len

            (0...len).each do |i|
              src = i - byte_shift
              next if src.negative?

              val = data.getbyte(src) >> bit_shift
              val |= (data.getbyte(src - 1) << (8 - bit_shift)) & 0xff if bit_shift.positive? && src.positive?
              result.setbyte(i, val)
            end

            result
          end
        end
      end
    end
  end
end
