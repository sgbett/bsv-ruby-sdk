# frozen_string_literal: true

require 'openssl'
require 'securerandom'

module BSV
  module Primitives
    class PrivateKey
      MAINNET_PREFIX = "\x80".b
      TESTNET_PREFIX = "\xef".b

      attr_reader :bn

      def initialize(bn)
        raise ArgumentError, 'private key must be an OpenSSL::BN' unless bn.is_a?(OpenSSL::BN)
        raise ArgumentError, 'private key out of range' if bn <= OpenSSL::BN.new('0') || bn >= Curve::N

        @bn = bn
      end

      def self.generate
        loop do
          bytes = SecureRandom.random_bytes(32)
          bn = OpenSSL::BN.new(bytes, 2)
          return new(bn) if bn > OpenSSL::BN.new('0') && bn < Curve::N
        end
      end

      def self.from_bytes(bytes)
        new(OpenSSL::BN.new(bytes, 2))
      end

      def self.from_hex(hex)
        new(OpenSSL::BN.new(hex, 16))
      end

      def self.from_wif(wif_string)
        data = Base58.check_decode(wif_string)
        prefix = data[0]
        unless [MAINNET_PREFIX, TESTNET_PREFIX].include?(prefix)
          raise ArgumentError, "unknown WIF network prefix: 0x#{prefix.unpack1('H*')}"
        end

        case data.length
        when 33
          # Uncompressed: prefix (1) + key (32)
          from_bytes(data[1, 32])
        when 34
          # Compressed: prefix (1) + key (32) + 0x01 (1)
          raise ArgumentError, 'invalid compression flag' unless data[33] == "\x01".b

          from_bytes(data[1, 32])
        else
          raise ArgumentError, "invalid WIF length: #{data.length}"
        end
      end

      def to_bytes
        raw = @bn.to_s(2)
        # Pad to 32 bytes
        raw.length < 32 ? ("\x00".b * (32 - raw.length)) + raw : raw
      end

      def to_hex
        to_bytes.unpack1('H*')
      end

      def to_wif(network: :mainnet, compressed: true)
        prefix = network == :mainnet ? MAINNET_PREFIX : TESTNET_PREFIX
        payload = prefix + to_bytes
        payload += "\x01".b if compressed
        Base58.check_encode(payload)
      end

      def public_key
        @public_key ||= PublicKey.new(Curve.multiply_generator(@bn))
      end

      def sign(hash)
        ECDSA.sign(hash, @bn)
      end
    end
  end
end
