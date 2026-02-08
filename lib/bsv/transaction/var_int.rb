# frozen_string_literal: true

module BSV
  module Transaction
    module VarInt
      module_function

      def encode(value)
        if value < 0xFD
          [value].pack('C')
        elsif value <= 0xFFFF
          [0xFD, value].pack('Cv')
        elsif value <= 0xFFFFFFFF
          [0xFE, value].pack('CV')
        else
          [0xFF, value].pack('CQ<')
        end
      end

      def decode(data, offset = 0)
        first = data.getbyte(offset)

        case first
        when 0..0xFC
          [first, 1]
        when 0xFD
          [data.byteslice(offset + 1, 2).unpack1('v'), 3]
        when 0xFE
          [data.byteslice(offset + 1, 4).unpack1('V'), 5]
        when 0xFF
          [data.byteslice(offset + 1, 8).unpack1('Q<'), 9]
        end
      end
    end
  end
end
