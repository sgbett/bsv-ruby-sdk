# frozen_string_literal: true

require_relative 'error'

module BSV
  module Script
    # Bitcoin script number: arbitrary-precision integer with sign-magnitude
    # little-endian byte encoding.
    #
    # Script numbers use a specialised encoding where the sign bit occupies
    # the MSB of the last byte, and the magnitude is stored little-endian.
    # This class handles encoding/decoding, minimal encoding validation,
    # and arithmetic operations as required by the script interpreter.
    class ScriptNumber
      include Comparable

      # Maximum byte length for script numbers (post-Genesis: 750 KB).
      MAX_BYTE_LENGTH = 750_000

      # Minimum 32-bit signed integer value.
      INT32_MIN = -(2**31)

      # Maximum 32-bit signed integer value.
      INT32_MAX = (2**31) - 1

      # @return [Integer] the numeric value
      attr_reader :value

      def initialize(value)
        @value = value
      end

      # Decode little-endian sign-magnitude bytes into a ScriptNumber.
      #
      # Encoding: little-endian magnitude with sign bit in the MSB of the last byte.
      #   127 -> [0x7f]
      #  -127 -> [0xff]
      #   128 -> [0x80 0x00]
      #  -128 -> [0x80 0x80]
      #   256 -> [0x00 0x01]
      #  -256 -> [0x00 0x81]
      def self.from_bytes(bytes, max_length: MAX_BYTE_LENGTH, require_minimal: false)
        bytes = bytes.b if bytes.encoding != Encoding::ASCII_8BIT
        return new(0) if bytes.empty?

        if bytes.bytesize > max_length
          raise ScriptError.new ScriptErrorCode::NUMBER_TOO_BIG, "script number overflow: #{bytes.bytesize} > #{max_length}"
        end

        check_minimal_encoding!(bytes) if require_minimal

        # Accumulate little-endian magnitude
        val = 0
        bytes.each_byte.with_index do |byte, i|
          val |= byte << (8 * i)
        end

        # Extract sign from MSB of last byte
        if bytes.getbyte(bytes.bytesize - 1) & 0x80 != 0
          val ^= 0x80 << (8 * (bytes.bytesize - 1))
          val = -val
        end

        new(val)
      end

      # Encode as little-endian sign-magnitude bytes.
      def to_bytes
        return ''.b if @value.zero?

        negative = @value.negative?
        abs_val = @value.abs

        result = []
        v = abs_val
        while v.positive?
          result << (v & 0xff)
          v >>= 8
        end

        if result.last & 0x80 != 0
          # MSB conflicts with sign bit — add padding byte
          result << (negative ? 0x80 : 0x00)
        elsif negative
          # Set sign bit in MSB
          result[-1] |= 0x80
        end

        result.pack('C*')
      end

      # Strip trailing zero-padding while preserving sign.
      def self.minimally_encode(data)
        return ''.b if data.nil? || data.empty?

        data = data.b
        last = data.getbyte(data.bytesize - 1)

        # If MSB has non-sign bits set, already minimal
        return data.dup if last.anybits?(0x7f)

        # Single byte with only sign/zero bits — encode as empty
        return ''.b if data.bytesize == 1

        # If second-to-last byte needs the sign extension, keep it
        return data.dup if data.getbyte(data.bytesize - 2) & 0x80 != 0

        # Scan backwards to find last non-zero byte
        i = data.bytesize - 2
        i -= 1 while i.positive? && data.getbyte(i).zero?

        if data.getbyte(i).zero?
          # All zeros
          ''.b
        elsif data.getbyte(i) & 0x80 != 0
          # This byte has high bit set — keep sign extension byte
          result = data.byteslice(0, i + 1)
          result << [last].pack('C')
          result
        else
          # Fold sign bit into this byte
          result = data.byteslice(0, i + 1).b
          result.setbyte(i, data.getbyte(i) | (last & 0x80))
          result
        end
      end

      # Clamp to int32 range (for opcodes that need bounded indices).
      def to_i32
        return INT32_MIN if @value < INT32_MIN
        return INT32_MAX if @value > INT32_MAX

        @value
      end

      def to_i
        @value
      end

      def zero?
        @value.zero?
      end

      # --- Arithmetic (returns new ScriptNumber) ---

      def +(other)
        self.class.new(@value + other.value)
      end

      def -(other)
        self.class.new(@value - other.value)
      end

      def *(other)
        self.class.new(@value * other.value)
      end

      # Truncated-toward-zero division (matching Bitcoin consensus).
      def /(other)
        raise ScriptError.new(ScriptErrorCode::DIVIDE_BY_ZERO, 'division by zero') if other.value.zero?

        result = @value.abs / other.value.abs
        result = -result if @value.negative? ^ other.value.negative?
        self.class.new(result)
      end

      # Remainder with sign of dividend (matching Bitcoin consensus).
      def %(other)
        raise ScriptError.new(ScriptErrorCode::DIVIDE_BY_ZERO, 'modulo by zero') if other.value.zero?

        result = @value.abs % other.value.abs
        result = -result if @value.negative?
        self.class.new(result)
      end

      def -@
        self.class.new(-@value)
      end

      def abs
        self.class.new(@value.abs)
      end

      def <=>(other)
        case other
        when ScriptNumber
          @value <=> other.value
        when Integer
          @value <=> other
        end
      end

      def self.check_minimal_encoding!(bytes)
        return if bytes.empty?

        msb = bytes.getbyte(bytes.bytesize - 1)

        # If MSB has non-sign bits set, encoding is minimal
        return if msb.anybits?(0x7f)

        # Single byte that is pure sign/zero (0x00 or 0x80) — not minimal
        raise ScriptError.new(ScriptErrorCode::MINIMAL_DATA, 'non-minimal script number encoding') if bytes.bytesize == 1

        # Padding is justified if second-to-last byte has high bit set
        return if bytes.getbyte(bytes.bytesize - 2) & 0x80 != 0

        raise ScriptError.new(ScriptErrorCode::MINIMAL_DATA, 'non-minimal script number encoding')
      end

      private_class_method :check_minimal_encoding!
    end
  end
end
