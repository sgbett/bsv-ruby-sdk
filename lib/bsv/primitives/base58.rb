# frozen_string_literal: true

module BSV
  module Primitives
    module Base58
      ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
      BASE = ALPHABET.length # 58

      DECODE_MAP = Array.new(256, -1).tap do |map|
        ALPHABET.each_char.with_index { |c, i| map[c.ord] = i }
      end.freeze

      class ChecksumError < StandardError; end

      module_function

      def encode(bytes)
        return '' if bytes.empty?

        # Count leading zero bytes
        leading_zeros = 0
        bytes.each_byte { |b| b.zero? ? leading_zeros += 1 : break }

        # Convert to big integer and repeatedly divide by 58
        n = bytes.unpack1('H*').to_i(16)
        result = +''
        while n.positive?
          n, remainder = n.divmod(BASE)
          result << ALPHABET[remainder]
        end

        # Preserve leading zeros as '1' characters
        result << (ALPHABET[0] * leading_zeros)
        result.reverse!
        result
      end

      def decode(string)
        return ''.b if string.empty?

        # Count leading '1' characters (representing zero bytes)
        leading_ones = 0
        string.each_char { |c| c == ALPHABET[0] ? leading_ones += 1 : break }

        # Convert from base58 to integer
        n = 0
        string.each_char do |c|
          digit = DECODE_MAP[c.ord]
          raise ArgumentError, "invalid Base58 character: #{c.inspect}" if digit == -1

          n = (n * BASE) + digit
        end

        # Convert integer to bytes
        hex = n.zero? ? '' : n.to_s(16)
        hex = "0#{hex}" if hex.length.odd?
        result = [hex].pack('H*')

        # Prepend zero bytes for leading '1' characters
        (("\x00" * leading_ones) + result).b
      end

      def check_encode(payload)
        checksum = Digest.sha256d(payload)[0, 4]
        encode(payload + checksum)
      end

      def check_decode(string)
        data = decode(string)
        raise ChecksumError, 'input too short for checksum' if data.length < 4

        payload = data[0...-4]
        checksum = data[-4..]
        expected = Digest.sha256d(payload)[0, 4]
        raise ChecksumError, 'checksum mismatch' unless checksum == expected

        payload
      end
    end
  end
end
