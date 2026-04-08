# frozen_string_literal: true

module BSV
  module Transaction
    # Bitcoin variable-length integer encoding/decoding.
    #
    # VarInts encode unsigned integers compactly: values under 253 use a
    # single byte; larger values use a marker byte followed by 2, 4, or 8
    # bytes in little-endian order.
    module VarInt
      module_function

      # Maximum value representable by a Bitcoin VarInt (unsigned 64-bit).
      MAX_UINT64 = 0xFFFF_FFFF_FFFF_FFFF

      # Encode an integer as a Bitcoin VarInt.
      #
      # @param value [Integer] non-negative integer to encode (0..2^64-1)
      # @return [String] encoded binary bytes
      # @raise [ArgumentError] if +value+ is negative or exceeds 2^64-1
      def encode(value)
        raise ArgumentError, "varint requires non-negative integer, got #{value}" if value.negative?
        raise ArgumentError, "varint value #{value} exceeds uint64 max (#{MAX_UINT64})" if value > MAX_UINT64

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

      # Decode a Bitcoin VarInt from binary data at the given offset.
      #
      # @param data [String] binary data containing the VarInt
      # @param offset [Integer] byte offset to start reading from
      # @return [Array(Integer, Integer)] the decoded value and number of bytes consumed
      def decode(data, offset = 0)
        raise ArgumentError, "truncated varint: need 1 byte at offset #{offset}, got end of data" if offset >= data.bytesize

        first = data.getbyte(offset)

        case first
        when 0..0xFC
          [first, 1]
        when 0xFD
          raise ArgumentError, "truncated varint: need 3 bytes at offset #{offset}, got #{data.bytesize - offset}" if data.bytesize < offset + 3

          [data.byteslice(offset + 1, 2).unpack1('v'), 3]
        when 0xFE
          raise ArgumentError, "truncated varint: need 5 bytes at offset #{offset}, got #{data.bytesize - offset}" if data.bytesize < offset + 5

          [data.byteslice(offset + 1, 4).unpack1('V'), 5]
        when 0xFF
          raise ArgumentError, "truncated varint: need 9 bytes at offset #{offset}, got #{data.bytesize - offset}" if data.bytesize < offset + 9

          [data.byteslice(offset + 1, 8).unpack1('Q<'), 9]
        end
      end
    end
  end
end
