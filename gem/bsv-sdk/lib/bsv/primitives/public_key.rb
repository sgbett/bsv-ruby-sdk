# frozen_string_literal: true

require 'openssl'

module BSV
  module Primitives
    # A secp256k1 public key for address derivation and signature verification.
    #
    # Public keys are points on the secp256k1 curve. They can be serialised
    # in compressed (33-byte) or uncompressed (65-byte) form, converted to
    # Bitcoin addresses, and used to verify ECDSA signatures.
    #
    # @example Derive address from a public key
    #   pub = private_key.public_key
    #   pub.address #=> "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
    class PublicKey
      # Address version byte for mainnet P2PKH addresses.
      MAINNET_PUBKEY_HASH = "\x00".b

      # Address version byte for testnet P2PKH addresses.
      TESTNET_PUBKEY_HASH = "\x6f".b

      # @return [OpenSSL::PKey::EC::Point] the underlying curve point
      attr_reader :point

      # @param point [OpenSSL::PKey::EC::Point] a point on the secp256k1 curve
      # @raise [ArgumentError] if point is not an EC point or is at infinity
      def initialize(point)
        raise ArgumentError, 'point must be an EC point' unless point.is_a?(OpenSSL::PKey::EC::Point)
        raise ArgumentError, 'point is at infinity' if point.infinity?

        @point = point
      end

      # Create a public key from raw bytes (compressed or uncompressed).
      #
      # @param bytes [String] 33-byte compressed or 65-byte uncompressed encoding
      # @return [PublicKey]
      def self.from_bytes(bytes)
        point = Curve.point_from_bytes(bytes)
        new(point)
      end

      # Create a public key from a hex string.
      #
      # @param hex [String] hex-encoded compressed or uncompressed public key
      # @return [PublicKey]
      def self.from_hex(hex)
        from_bytes(Hex.decode(hex, name: 'public key hex'))
      end

      # Derive the public key from a {PrivateKey}.
      #
      # @param private_key [PrivateKey] the private key
      # @return [PublicKey]
      def self.from_private_key(private_key)
        private_key.public_key
      end

      # Return the compressed (33-byte) encoding.
      #
      # @return [String] compressed public key bytes
      def compressed
        @point.to_octet_string(:compressed)
      end

      # Return the uncompressed (65-byte) encoding.
      #
      # @return [String] uncompressed public key bytes
      def uncompressed
        @point.to_octet_string(:uncompressed)
      end

      # Return the public key as a hex string.
      #
      # @param compressed [Boolean] whether to use compressed encoding (default: true)
      # @return [String] hex-encoded public key
      def to_hex(compressed: true)
        if compressed
          self.compressed.unpack1('H*')
        else
          uncompressed.unpack1('H*')
        end
      end

      # Compute the Hash160 (RIPEMD-160 of SHA-256) of the compressed public key.
      #
      # @return [String] 20-byte public key hash
      def hash160
        Digest.hash160(compressed)
      end

      # Derive a Base58Check-encoded Bitcoin address.
      #
      # @param network [Symbol] +:mainnet+ or +:testnet+
      # @return [String] the P2PKH address
      def address(network: :mainnet)
        prefix = network == :mainnet ? MAINNET_PUBKEY_HASH : TESTNET_PUBKEY_HASH
        Base58.check_encode(prefix + hash160)
      end

      # Derive an ECDH shared secret with another party's private key.
      #
      # Computes the shared point by multiplying this public key by the
      # given private key's scalar. The result is commutative:
      #   alice_pub.derive_shared_secret(bob_priv) ==
      #     bob_pub.derive_shared_secret(alice_priv)
      #
      # Uses constant-time scalar multiplication to protect the private
      # key scalar from timing side-channels.
      #
      # This is the foundational primitive for BRC-42 key derivation,
      # BRC-77/78 messaging, and ECIES encryption.
      #
      # @param private_key [PrivateKey] the other party's private key
      # @return [PublicKey] the shared secret as a public key (curve point)
      def derive_shared_secret(private_key)
        shared_point = Curve.multiply_point_ct(@point, private_key.bn)
        PublicKey.new(shared_point)
      end

      # Derive a child public key using BRC-42 key derivation.
      #
      # Computes HMAC-SHA256(key: ECDH_shared_secret, msg: invoice_number)
      # and adds the corresponding curve point to this public key. The result
      # matches the public key of {PrivateKey#derive_child} with the same
      # inputs, enabling public-key-only derivation.
      #
      # @param private_key [PrivateKey] the counterparty's private key
      # @param invoice_number [String] the invoice number (UTF-8)
      # @return [PublicKey] the derived child public key
      def derive_child(private_key, invoice_number)
        shared = derive_shared_secret(private_key)
        hmac = Digest.hmac_sha256(shared.compressed, invoice_number.encode('UTF-8'))
        hmac_bn = OpenSSL::BN.new(hmac, 2)
        hmac_point = Curve.multiply_generator_ct(hmac_bn)
        child_point = Curve.add_points(@point, hmac_point)
        PublicKey.new(child_point)
      end

      # Verify an ECDSA signature against a message hash.
      #
      # @param hash [String] 32-byte message digest
      # @param signature [Signature] the signature to verify
      # @return [Boolean] +true+ if the signature is valid
      def verify(hash, signature)
        ECDSA.verify(hash, signature, @point)
      end

      # @param other [Object] the object to compare
      # @return [Boolean] +true+ if both keys represent the same curve point
      def ==(other)
        other.is_a?(PublicKey) && compressed == other.compressed
      end
    end
  end
end
