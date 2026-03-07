# frozen_string_literal: true

require 'openssl'
require 'securerandom'

module BSV
  module Primitives
    # A secp256k1 private key for signing transactions and deriving public keys.
    #
    # Can be created from random entropy, raw bytes, hex, or WIF (Wallet
    # Import Format). Produces deterministic ECDSA signatures via {ECDSA}.
    #
    # @example Generate a new random key
    #   key = BSV::Primitives::PrivateKey.generate
    #   key.to_wif #=> "5J..."
    #
    # @example Import from WIF
    #   key = BSV::Primitives::PrivateKey.from_wif('5HueCGU8rMjxEX...')
    #   key.public_key.address #=> "1GAeh..."
    class PrivateKey
      # WIF version prefix for mainnet private keys.
      MAINNET_PREFIX = "\x80".b

      # WIF version prefix for testnet private keys.
      TESTNET_PREFIX = "\xef".b

      # @return [OpenSSL::BN] the private key as a big number
      attr_reader :bn

      # @param bn [OpenSSL::BN] the private key scalar (must be 1 < bn < N)
      # @raise [ArgumentError] if bn is not an OpenSSL::BN or is out of range
      def initialize(bn)
        raise ArgumentError, 'private key must be an OpenSSL::BN' unless bn.is_a?(OpenSSL::BN)
        raise ArgumentError, 'private key out of range' if bn <= OpenSSL::BN.new('0') || bn >= Curve::N

        @bn = bn
      end

      # Generate a new random private key using secure random bytes.
      #
      # @return [PrivateKey] a cryptographically random private key
      def self.generate
        loop do
          bytes = SecureRandom.random_bytes(32)
          bn = OpenSSL::BN.new(bytes, 2)
          return new(bn) if bn > OpenSSL::BN.new('0') && bn < Curve::N
        end
      end

      # Create a private key from raw 32-byte big-endian encoding.
      #
      # @param bytes [String] 32-byte binary string
      # @return [PrivateKey]
      def self.from_bytes(bytes)
        new(OpenSSL::BN.new(bytes, 2))
      end

      # Create a private key from a hex string.
      #
      # @param hex [String] 64-character hex-encoded private key
      # @return [PrivateKey]
      def self.from_hex(hex)
        new(OpenSSL::BN.new(hex, 16))
      end

      # Create a private key from Wallet Import Format (WIF).
      #
      # Supports both compressed and uncompressed WIF encodings,
      # and both mainnet and testnet prefixes.
      #
      # @param wif_string [String] Base58Check-encoded WIF string
      # @return [PrivateKey]
      # @raise [ArgumentError] if the WIF prefix, length, or compression flag is invalid
      def self.from_wif(wif_string)
        data = Base58.check_decode(wif_string)
        prefix = data[0]
        raise ArgumentError, "unknown WIF network prefix: 0x#{prefix.unpack1('H*')}" unless [MAINNET_PREFIX, TESTNET_PREFIX].include?(prefix)

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

      # Serialise the private key as 32-byte big-endian binary.
      #
      # @return [String] 32-byte binary string (zero-padded)
      def to_bytes
        raw = @bn.to_s(2)
        # Pad to 32 bytes
        raw.length < 32 ? ("\x00".b * (32 - raw.length)) + raw : raw
      end

      # Serialise the private key as a 64-character hex string.
      #
      # @return [String] hex-encoded private key
      def to_hex
        to_bytes.unpack1('H*')
      end

      # Serialise the private key in Wallet Import Format (WIF).
      #
      # @param network [Symbol] +:mainnet+ or +:testnet+
      # @param compressed [Boolean] whether to flag for compressed public key derivation
      # @return [String] Base58Check-encoded WIF string
      def to_wif(network: :mainnet, compressed: true)
        prefix = network == :mainnet ? MAINNET_PREFIX : TESTNET_PREFIX
        payload = prefix + to_bytes
        payload += "\x01".b if compressed
        Base58.check_encode(payload)
      end

      # Derive the corresponding public key.
      #
      # @return [PublicKey] the public key for this private key
      def public_key
        @public_key ||= PublicKey.new(Curve.multiply_generator(@bn))
      end

      # Derive an ECDH shared secret with another party's public key.
      #
      # Computes the shared point by multiplying the given public key by
      # this private key's scalar. The result is commutative:
      #   alice_priv.derive_shared_secret(bob_pub) ==
      #     bob_priv.derive_shared_secret(alice_pub)
      #
      # This is the foundational primitive for BRC-42 key derivation,
      # BRC-77/78 messaging, and ECIES encryption.
      #
      # @param public_key [PublicKey] the other party's public key
      # @return [PublicKey] the shared secret as a public key (curve point)
      def derive_shared_secret(public_key)
        shared_point = Curve.multiply_point(public_key.point, @bn)
        PublicKey.new(shared_point)
      end

      # Derive a child private key using BRC-42 key derivation.
      #
      # Computes HMAC-SHA256(key: ECDH_shared_secret, msg: invoice_number)
      # and adds it to this private key's scalar mod n. The corresponding
      # public key can be derived without the private key using
      # {PublicKey#derive_child}.
      #
      # @param public_key [PublicKey] the counterparty's public key
      # @param invoice_number [String] the invoice number (UTF-8)
      # @return [PrivateKey] the derived child private key
      def derive_child(public_key, invoice_number)
        shared = derive_shared_secret(public_key)
        hmac = Digest.hmac_sha256(shared.compressed, invoice_number.encode('UTF-8'))
        hmac_bn = OpenSSL::BN.new(hmac.unpack1('H*'), 16)
        PrivateKey.new(@bn.mod_add(hmac_bn, Curve::N))
      end

      # Sign a 32-byte hash using deterministic ECDSA (RFC 6979).
      #
      # @param hash [String] 32-byte message digest to sign
      # @return [Signature] the DER-encodable signature
      def sign(hash)
        ECDSA.sign(hash, @bn)
      end
    end
  end
end
