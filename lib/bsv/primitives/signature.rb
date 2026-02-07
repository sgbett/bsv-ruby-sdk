# frozen_string_literal: true

require 'openssl'

module BSV
  module Primitives
    class Signature
      attr_reader :r, :s

      def initialize(r, s)
        @r = r.is_a?(OpenSSL::BN) ? r : OpenSSL::BN.new(r.to_s, 10)
        @s = s.is_a?(OpenSSL::BN) ? s : OpenSSL::BN.new(s.to_s, 10)
      end

      def self.from_der(der_bytes)
        der_bytes = der_bytes.b if der_bytes.encoding != Encoding::ASCII_8BIT
        bytes = der_bytes.bytes

        raise ArgumentError, 'signature too short' if bytes.length < 8
        raise ArgumentError, 'invalid sequence tag' unless bytes[0] == 0x30

        total_len = bytes[1]
        raise ArgumentError, 'length mismatch' unless total_len == bytes.length - 2

        # Parse R
        raise ArgumentError, 'invalid integer tag for R' unless bytes[2] == 0x02

        r_len = bytes[3]
        raise ArgumentError, 'R length overflows' if 4 + r_len > bytes.length
        raise ArgumentError, 'R is zero length' if r_len.zero?

        r_bytes = bytes[4, r_len]
        raise ArgumentError, 'R has negative flag' if r_bytes[0] & 0x80 != 0
        raise ArgumentError, 'R has excessive padding' if r_len > 1 && r_bytes[0].zero? && r_bytes[1].nobits?(0x80)

        # Parse S
        s_offset = 4 + r_len
        raise ArgumentError, 'invalid integer tag for S' unless bytes[s_offset] == 0x02

        s_len = bytes[s_offset + 1]
        raise ArgumentError, 'S length overflows' if s_offset + 2 + s_len > bytes.length
        raise ArgumentError, 'S is zero length' if s_len.zero?

        s_bytes = bytes[s_offset + 2, s_len]
        raise ArgumentError, 'S has negative flag' if s_bytes[0] & 0x80 != 0
        raise ArgumentError, 'S has excessive padding' if s_len > 1 && s_bytes[0].zero? && s_bytes[1].nobits?(0x80)

        raise ArgumentError, 'trailing bytes' unless s_offset + 2 + s_len == bytes.length

        r = OpenSSL::BN.new(r_bytes.pack('C*'), 2)
        s = OpenSSL::BN.new(s_bytes.pack('C*'), 2)
        new(r, s)
      end

      def to_der
        rb = canonicalise_int(@r)
        sb = canonicalise_int(@s)

        der = [0x30, rb.length + sb.length + 4,
               0x02, rb.length, *rb,
               0x02, sb.length, *sb]
        der.pack('C*')
      end

      def self.from_hex(hex)
        from_der([hex].pack('H*'))
      end

      def to_hex
        to_der.unpack1('H*')
      end

      def low_s?
        @s <= Curve::HALF_N
      end

      def to_low_s
        return self if low_s?

        self.class.new(@r, Curve::N - @s)
      end

      def ==(other)
        other.is_a?(Signature) && @r == other.r && @s == other.s
      end

      private

      def canonicalise_int(bn)
        bytes = bn.to_s(2).bytes
        bytes = [0] if bytes.empty?
        bytes.unshift(0) if bytes[0] & 0x80 != 0
        bytes
      end
    end
  end
end
