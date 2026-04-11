# frozen_string_literal: true

module BSV
  module Primitives
    # Base58 and Base58Check encoding/decoding.
    #
    # Implements the Base58 alphabet used throughout Bitcoin for addresses,
    # WIF keys, and extended keys. Base58Check adds a 4-byte double-SHA-256
    # checksum for error detection.
    #
    # @example Encode and decode an address payload
    #   encoded = BSV::Primitives::Base58.check_encode(payload)
    #   decoded = BSV::Primitives::Base58.check_decode(encoded)
    module Base58
      # The Base58 alphabet (no 0, O, I, l to avoid visual ambiguity).
      ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'

      # The base (58).
      BASE = ALPHABET.length # 58

      # Reverse lookup table mapping ASCII byte values to Base58 digit indices.
      DECODE_MAP = Array.new(256, -1).tap do |map|
        ALPHABET.each_char.with_index { |c, i| map[c.ord] = i }
      end.freeze

      # Raised when a Base58Check checksum does not match.
      class ChecksumError < StandardError; end

      module_function

      # Encode binary data as a Base58 string.
      #
      # Leading zero bytes are preserved as +'1'+ characters.
      #
      # @param bytes [String] binary data to encode
      # @return [String] Base58-encoded string
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

      # Decode a Base58 string to binary data.
      #
      # Leading +'1'+ characters are decoded as zero bytes.
      #
      # @param string [String] Base58-encoded string
      # @return [String] decoded binary data
      # @raise [ArgumentError] if the string contains invalid Base58 characters
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

      # Encode binary data with a 4-byte double-SHA-256 checksum appended.
      #
      # @param payload [String] binary data to encode
      # @return [String] Base58Check-encoded string
      def check_encode(payload)
        checksum = Digest.sha256d(payload)[0, 4]
        encode(payload + checksum)
      end

      # Decode a Base58Check string and verify its checksum.
      #
      # @param string [String] Base58Check-encoded string
      # @return [String] decoded payload (without checksum)
      # @raise [ChecksumError] if the checksum does not match or input is too short
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
