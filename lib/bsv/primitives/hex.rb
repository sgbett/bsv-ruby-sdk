# frozen_string_literal: true

module BSV
  module Primitives
    # Strict hex encoding/decoding utilities.
    #
    # Ruby's +Array#pack('H*')+ silently drops non-hex characters and
    # truncates odd-length strings. This module rejects both, raising
    # +ArgumentError+ on invalid input so consumer-facing parse paths
    # fail loudly rather than producing garbage.
    #
    # Internal paths that serialise/deserialise trusted hex (e.g.
    # round-tripping our own +unpack1('H*')+ output) can continue
    # using +pack('H*')+ directly — the validation overhead isn't
    # warranted when the hex is known-good.
    #
    # @example
    #   BSV::Primitives::Hex.decode('deadbeef')          #=> "\xDE\xAD\xBE\xEF"
    #   BSV::Primitives::Hex.decode('nope')              #=> ArgumentError
    #   BSV::Primitives::Hex.decode('abc')               #=> ArgumentError (odd length)
    #   BSV::Primitives::Hex.encode("\xDE\xAD")          #=> "dead"
    module Hex
      # Matches an even number of hex characters (case-insensitive).
      # Empty string is valid (decodes to empty bytes).
      HEX_RE = /\A(?:[0-9a-fA-F]{2})*\z/.freeze
      private_constant :HEX_RE

      # Test whether +str+ is valid hex (even-length, hex-only).
      #
      # @param str [String]
      # @return [Boolean]
      def self.valid?(str)
        str.is_a?(String) && str.match?(HEX_RE)
      end

      # Validate +str+ as hex, raising on failure.
      #
      # @param str [String]
      # @param name [String] label for the error message (e.g. +'txid'+)
      # @return [String] the input string (pass-through for chaining)
      # @raise [ArgumentError] if +str+ is not valid hex
      def self.validate!(str, name: 'hex value')
        return str if valid?(str)

        reason = if !str.is_a?(String)
                   "expected String, got #{str.class}"
                 elsif str.length.odd?
                   'odd length'
                 else
                   'contains non-hex characters'
                 end
        raise ArgumentError, "invalid #{name}: #{reason} (#{str.inspect})"
      end

      # Decode a hex string to binary bytes.
      #
      # @param str [String] hex string (must be even-length, hex-only)
      # @param name [String] label for the error message
      # @return [String] binary string (ASCII-8BIT encoding)
      # @raise [ArgumentError] if +str+ is not valid hex
      def self.decode(str, name: 'hex value')
        validate!(str, name: name)
        [str].pack('H*')
      end

      # Encode binary bytes as lowercase hex.
      #
      # @param bytes [String] binary data
      # @return [String] lowercase hex string (UTF-8 encoding)
      def self.encode(bytes)
        bytes.unpack1('H*')
      end
    end
  end
end
