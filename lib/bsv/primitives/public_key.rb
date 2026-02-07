# frozen_string_literal: true

require 'openssl'

module BSV
  module Primitives
    class PublicKey
      MAINNET_PUBKEY_HASH = "\x00".b
      TESTNET_PUBKEY_HASH = "\x6f".b

      attr_reader :point

      def initialize(point)
        raise ArgumentError, 'point must be an EC point' unless point.is_a?(OpenSSL::PKey::EC::Point)
        raise ArgumentError, 'point is at infinity' if point.infinity?

        @point = point
      end

      def self.from_bytes(bytes)
        point = Curve.point_from_bytes(bytes)
        new(point)
      end

      def self.from_hex(hex)
        from_bytes([hex].pack('H*'))
      end

      def self.from_private_key(private_key)
        private_key.public_key
      end

      def compressed
        @point.to_octet_string(:compressed)
      end

      def uncompressed
        @point.to_octet_string(:uncompressed)
      end

      def to_hex(compressed: true)
        if compressed
          self.compressed.unpack1('H*')
        else
          uncompressed.unpack1('H*')
        end
      end

      def hash160
        Digest.hash160(compressed)
      end

      def address(network: :mainnet)
        prefix = network == :mainnet ? MAINNET_PUBKEY_HASH : TESTNET_PUBKEY_HASH
        Base58.check_encode(prefix + hash160)
      end

      def verify(hash, signature)
        ECDSA.verify(hash, signature, @point)
      end

      def ==(other)
        other.is_a?(PublicKey) && compressed == other.compressed
      end
    end
  end
end
