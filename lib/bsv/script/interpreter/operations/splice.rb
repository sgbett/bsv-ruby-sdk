# frozen_string_literal: true

module BSV
  module Script
    class Interpreter
      module Operations
        module Splice
          private

          # OP_CAT: concatenate two byte arrays
          def op_cat
            b = @dstack.pop_bytes
            a = @dstack.pop_bytes
            @dstack.push_bytes(a + b)
          end

          # OP_SPLIT: split byte array at position
          # Stack: [... data position] -> [... left right]
          def op_split
            pos = @dstack.pop_int.to_i32
            data = @dstack.pop_bytes

            if pos.negative? || pos > data.bytesize
              raise ScriptError.new(
                ScriptErrorCode::INVALID_INPUT_LENGTH,
                "invalid OP_SPLIT position: #{pos} for data of length #{data.bytesize}"
              )
            end

            @dstack.push_bytes(data.byteslice(0, pos) || ''.b)
            @dstack.push_bytes(data.byteslice(pos, data.bytesize - pos) || ''.b)
          end

          # OP_SIZE: push length of top item (peek, does NOT pop)
          def op_size
            data = @dstack.peek_bytes
            @dstack.push_int(ScriptNumber.new(data.bytesize))
          end

          # OP_NUM2BIN: convert number to fixed-size byte array
          # Stack: [... value size] -> [... padded_bytes]
          def op_num2bin
            size = @dstack.pop_int.to_i32
            data = @dstack.pop_bytes

            if size.negative?
              raise ScriptError.new(ScriptErrorCode::INVALID_INPUT_LENGTH, 'OP_NUM2BIN: size is negative')
            end

            minimal = ScriptNumber.minimally_encode(data)

            if minimal.bytesize > size
              raise ScriptError.new(
                ScriptErrorCode::IMPOSSIBLE_ENCODING,
                "OP_NUM2BIN: cannot fit value in #{size} bytes"
              )
            end

            if minimal.bytesize == size
              @dstack.push_bytes(minimal)
              return
            end

            # Pad minimal encoding to target size, preserving sign bit
            result = "\x00".b * size

            unless minimal.empty?
              result[0, minimal.bytesize] = minimal

              # Move sign bit from old last byte to new last byte
              sign_bit = minimal.getbyte(minimal.bytesize - 1) & 0x80
              result.setbyte(minimal.bytesize - 1, result.getbyte(minimal.bytesize - 1) & 0x7f)
              result.setbyte(size - 1, result.getbyte(size - 1) | sign_bit)
            end

            @dstack.push_bytes(result)
          end

          # OP_BIN2NUM: minimally encode byte array as script number
          def op_bin2num
            data = @dstack.pop_bytes
            @dstack.push_bytes(ScriptNumber.minimally_encode(data))
          end
        end
      end
    end
  end
end
