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
      HEX_RE = /\A(?:[0-9a-fA-F]{2})*\z/n
      private_constant :HEX_RE

      # Test whether +str+ is valid hex (even-length, hex-only).
      #
      # @param str [String]
      # @return [Boolean]
      def self.valid?(str)
        str.is_a?(String) && str.match?(HEX_RE)
      rescue Encoding::CompatibilityError
        false
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

      # Validate that +value+ is a 32-byte wire-order transaction ID.
      #
      # @param value [String] expected 32-byte binary string
      # @param name [String] label for the error message (e.g. +'prev_wtxid'+)
      # @return [String] the input value (pass-through for chaining)
      # @raise [ArgumentError] if +value+ is not a 32-byte binary string
      def self.validate_wtxid!(value, name: 'wtxid')
        unless value.is_a?(String) && value.bytesize == 32
          hint = if value.is_a?(String) && value.bytesize == 64 && value.match?(HEX_RE)
                   ' (looks like a hex txid — use wtxid_from_hex to convert)'
                 else
                   ''
                 end
          size = value.is_a?(String) ? "#{value.bytesize}-byte string" : value.class.to_s
          raise ArgumentError,
                "expected 32-byte wire-order wtxid for #{name}, got #{size}#{hint}"
        end
        value
      end

      # Validate that +value+ is a 32-byte binary hash.
      #
      # General-purpose validator for any 32-byte hash (merkle nodes, roots,
      # etc.) — not specific to transaction IDs. For txid-specific validation
      # use {.validate_wtxid!} or {.validate_dtxid_hex!} instead.
      #
      # @param value [String] expected 32-byte binary string
      # @param name [String] label for the error message
      # @return [String] the input value (pass-through for chaining)
      # @raise [ArgumentError] if +value+ is not a 32-byte binary string
      def self.validate_hash32!(value, name: 'hash')
        unless value.is_a?(String) && value.bytesize == 32
          hint = if value.is_a?(String) && value.bytesize == 64 && value.match?(HEX_RE)
                   ' (looks like hex — decode it first)'
                 else
                   ''
                 end
          size = value.is_a?(String) ? "#{value.bytesize}-byte string" : value.class.to_s
          raise ArgumentError,
                "expected 32-byte hash for #{name}, got #{size}#{hint}"
        end
        value
      end

      # Validate that +value+ is a 64-character display-order hex transaction ID.
      #
      # @param value [String] expected 64-char hex string
      # @param name [String] label for the error message (e.g. +'dtxid_hex'+)
      # @return [String] the input value (pass-through for chaining)
      # @raise [ArgumentError] if +value+ is not a 64-char hex string
      def self.validate_dtxid_hex!(value, name: 'dtxid_hex')
        unless value.is_a?(String) && value.length == 64 && value.match?(HEX_RE)
          hint = if value.is_a?(String) && value.bytesize == 32 && !value.match?(HEX_RE)
                   ' (looks like binary bytes — use dtxid_hex or unpack to convert)'
                 else
                   ''
                 end
          size = value.is_a?(String) ? "#{value.length}-char string" : value.class.to_s
          raise ArgumentError,
                "expected 64-char display-order hex for #{name}, got #{size}#{hint}"
        end
        value
      end
    end
  end
end
