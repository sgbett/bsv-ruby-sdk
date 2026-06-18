# frozen_string_literal: true

require 'bsv/primitives/digest'

module BSV
  module Script
    # BIP-276 text encoding for scripts and templates.
    #
    # Encodes and decodes typed bitcoin data using the scheme described in
    # https://github.com/moneybutton/bips/blob/master/bip-0276.mediawiki
    #
    # Format: `<prefix>:<version-byte><network-byte><hex-payload><checksum>`
    # where version and network are each one byte (two hex digits), and
    # checksum is the first 4 bytes of double-SHA256 over the full preimage
    # (the string up to and including the payload), hex-encoded.
    #
    # @note Field order is version-then-network, matching the BIP-276 spec
    #   and the Go SDK reference. The Python SDK has these reversed — a known
    #   py-sdk bug that is invisible at default v=1, n=1.
    module BIP276
      # Returned by {decode}; immutable value object.
      Result = Data.define(:prefix, :version, :network, :data)

      # Custom exception hierarchy.
      class Error < StandardError; end
      class InvalidFormat   < Error; end
      class InvalidChecksum < Error; end

      PREFIX_SCRIPT   = 'bitcoin-script'
      PREFIX_TEMPLATE = 'bitcoin-template'
      CURRENT_VERSION = 1
      NETWORK_MAINNET = 1
      NETWORK_TESTNET = 2

      # Regex: prefix(:)(version 2 hex)(network 2 hex)(data hex*)(checksum 8 hex)
      VALID_BIP276 = /\A(.+?):([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]*)([0-9A-Fa-f]{8})\z/

      module_function

      # Encode a binary payload as a BIP-276 string.
      #
      # @param data    [String]  binary payload (e.g. a {Script::Script}'s binary form)
      # @param prefix  [String]  {PREFIX_SCRIPT} or {PREFIX_TEMPLATE} (or any custom prefix)
      # @param version [Integer] 1..255 — {CURRENT_VERSION} by default
      # @param network [Integer] 1..255 — {NETWORK_MAINNET} by default
      # @return [String] BIP-276 encoded string
      # @raise [ArgumentError] if version or network is out of the range 1..255
      def encode(data, prefix: PREFIX_SCRIPT, network: NETWORK_MAINNET, version: CURRENT_VERSION)
        raise ArgumentError, "version must be 1..255, got #{version}"  unless (1..255).cover?(version)
        raise ArgumentError, "network must be 1..255, got #{network}"  unless (1..255).cover?(network)

        preimage = build_preimage(prefix, version, network, data)
        preimage + checksum(preimage)
      end

      # Decode a BIP-276 string.
      #
      # @param str [String] BIP-276 encoded string
      # @return [Result] value object with +:prefix+, +:version+, +:network+, +:data+
      # @raise [InvalidFormat]   if the string is structurally malformed
      # @raise [InvalidChecksum] if the checksum does not match the payload
      def decode(str)
        match = VALID_BIP276.match(str)
        raise InvalidFormat, 'not a valid BIP-276 string' unless match

        prefix  = match[1]
        version = match[2].to_i(16)
        network = match[3].to_i(16)

        raise InvalidFormat, 'data payload has odd number of hex digits' if match[4].length.odd?

        data = [match[4]].pack('H*')

        preimage        = build_preimage(prefix, version, network, data)
        expected        = checksum(preimage)
        raise InvalidChecksum, 'checksum mismatch' unless match[5].downcase == expected

        Result.new(prefix: prefix, version: version, network: network, data: data)
      end

      # Encode a script payload using the {PREFIX_SCRIPT} prefix.
      #
      # @param (see encode)
      # @return [String] BIP-276 encoded string with +bitcoin-script+ prefix
      def encode_script(data, network: NETWORK_MAINNET, version: CURRENT_VERSION)
        encode(data, prefix: PREFIX_SCRIPT, network: network, version: version)
      end

      # Encode a template payload using the {PREFIX_TEMPLATE} prefix.
      #
      # @param (see encode)
      # @return [String] BIP-276 encoded string with +bitcoin-template+ prefix
      def encode_template(data, network: NETWORK_MAINNET, version: CURRENT_VERSION)
        encode(data, prefix: PREFIX_TEMPLATE, network: network, version: version)
      end

      # Decode a BIP-276 string that must have the {PREFIX_SCRIPT} prefix.
      #
      # @param str [String] BIP-276 encoded string
      # @return [Result]
      # @raise [InvalidFormat] if prefix is not +bitcoin-script+
      # @raise [InvalidChecksum] if the checksum does not match
      def decode_script(str)
        result = decode(str)
        raise InvalidFormat, "expected prefix '#{PREFIX_SCRIPT}', got '#{result.prefix}'" \
          unless result.prefix == PREFIX_SCRIPT

        result
      end

      # Decode a BIP-276 string that must have the {PREFIX_TEMPLATE} prefix.
      #
      # @param str [String] BIP-276 encoded string
      # @return [Result]
      # @raise [InvalidFormat] if prefix is not +bitcoin-template+
      # @raise [InvalidChecksum] if the checksum does not match
      def decode_template(str)
        result = decode(str)
        raise InvalidFormat, "expected prefix '#{PREFIX_TEMPLATE}', got '#{result.prefix}'" \
          unless result.prefix == PREFIX_TEMPLATE

        result
      end

      # @api private
      def build_preimage(prefix, version, network, data)
        format('%<prefix>s:%<version>02x%<network>02x%<payload>s',
               prefix: prefix, version: version, network: network, payload: data.unpack1('H*'))
      end
      private_class_method :build_preimage

      # @api private
      def checksum(preimage)
        BSV::Primitives::Digest.sha256d(preimage)[0, 4].unpack1('H*')
      end
      private_class_method :checksum
    end
  end
end
