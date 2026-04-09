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
      # Always produces a compressed WIF (the 0x01 compression flag is
      # appended). BSV exclusively uses compressed public keys; uncompressed
      # WIF export is not supported ("construct only what's valid").
      #
      # The +from_wif+ parser continues to accept both compressed and
      # uncompressed WIF for import compatibility with legacy wallets.
      #
      # @param network [Symbol] +:mainnet+ or +:testnet+
      # @return [String] Base58Check-encoded WIF string (compressed format)
      def to_wif(network: :mainnet)
        prefix = network == :mainnet ? MAINNET_PREFIX : TESTNET_PREFIX
        Base58.check_encode(prefix + to_bytes + "\x01".b)
      end

      # Derive the corresponding public key.
      #
      # Uses constant-time scalar multiplication to protect the private
      # key scalar from timing side-channels during derivation.
      #
      # @return [PublicKey] the public key for this private key
      def public_key
        @public_key ||= PublicKey.new(Curve.multiply_generator_ct(@bn))
      end

      # Derive an ECDH shared secret with another party's public key.
      #
      # Computes the shared point by multiplying the given public key by
      # this private key's scalar. The result is commutative:
      #   alice_priv.derive_shared_secret(bob_pub) ==
      #     bob_priv.derive_shared_secret(alice_pub)
      #
      # Uses constant-time scalar multiplication to protect the private
      # key scalar from timing side-channels.
      #
      # This is the foundational primitive for BRC-42 key derivation,
      # BRC-77/78 messaging, and ECIES encryption.
      #
      # @param public_key [PublicKey] the other party's public key
      # @return [PublicKey] the shared secret as a public key (curve point)
      def derive_shared_secret(public_key)
        shared_point = Curve.multiply_point_ct(public_key.point, @bn)
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

      # Split this private key into Shamir's Secret Sharing shares.
      #
      # Generates +total_shares+ evaluation points on a random polynomial whose
      # y-intercept encodes this key. Any +threshold+ of them suffice to
      # reconstruct the key. X-coordinates are derived via HMAC-SHA-512 over a
      # 64-byte random seed, ensuring uniqueness even under partial RNG failure.
      #
      # @param threshold    [Integer] minimum shares needed to reconstruct (>= 2)
      # @param total_shares [Integer] total shares to generate (>= threshold)
      # @return [KeyShares]
      # @raise [ArgumentError] if parameters are out of range
      def to_key_shares(threshold, total_shares)
        raise ArgumentError, 'threshold must be an integer'    unless threshold.is_a?(Integer)
        raise ArgumentError, 'total_shares must be an integer' unless total_shares.is_a?(Integer)
        raise ArgumentError, 'threshold must be at least 2'    if threshold < 2
        raise ArgumentError, 'total_shares must be at least 2' if total_shares < 2
        raise ArgumentError, 'threshold must be <= total_shares' if threshold > total_shares

        poly = Polynomial.from_private_key(self, threshold: threshold)

        seed          = SecureRandom.random_bytes(64)
        used_x        = {}
        points        = []

        total_shares.times do |i|
          x = nil
          attempts = 0
          loop do
            counter_bytes = [i, attempts].pack('N*') + SecureRandom.random_bytes(32)
            h             = Digest.hmac_sha512(seed, counter_bytes)
            candidate     = OpenSSL::BN.new(h.unpack1('H*'), 16) % PointInFiniteField::P

            attempts += 1
            raise ArgumentError, 'failed to generate unique x-coordinate after 5 attempts' if attempts > 5

            next if candidate.zero? || used_x.key?(candidate.to_s)

            x = candidate
            break
          end

          used_x[x.to_s] = true
          y = poly.value_at(x)
          points << PointInFiniteField.new(x, y)
        end

        integrity = public_key.hash160[0, 4].unpack1('H*')
        KeyShares.new(points, threshold, integrity)
      end

      # Serialise this key as Shamir backup share strings.
      #
      # Convenience wrapper around {#to_key_shares} and {KeyShares#to_backup_format}.
      #
      # @param threshold    [Integer] minimum shares needed to reconstruct
      # @param total_shares [Integer] total shares to generate
      # @return [Array<String>] backup-format share strings
      def to_backup_shares(threshold, total_shares)
        to_key_shares(threshold, total_shares).to_backup_format
      end

      # Reconstruct a private key from a {KeyShares} object.
      #
      # Evaluates the Lagrange polynomial at x=0 to recover the secret, then
      # checks the integrity hash against the reconstructed public key.
      #
      # @param key_shares [KeyShares] the shares to combine
      # @return [PrivateKey] the reconstructed private key
      # @raise [ArgumentError] if there are too few shares, duplicates, or integrity fails
      def self.from_key_shares(key_shares)
        points    = key_shares.points
        threshold = key_shares.threshold
        integrity = key_shares.integrity

        raise ArgumentError, 'threshold must be at least 2' if threshold < 2
        raise ArgumentError, "at least #{threshold} shares are required" if points.length < threshold

        # Guard against duplicate x-coordinates
        xs = points.first(threshold).map { |p| p.x.to_s }
        raise ArgumentError, 'duplicate share detected; each share must be unique' if xs.length != xs.uniq.length

        poly    = Polynomial.new(points.first(threshold), threshold)
        secret  = poly.value_at(OpenSSL::BN.new('0'))
        key     = new(secret)

        actual_integrity = key.public_key.hash160[0, 4].unpack1('H*')
        raise ArgumentError, 'integrity hash mismatch — shares may be corrupt or belong to a different key' unless actual_integrity == integrity

        key
      end

      # Reconstruct a private key from backup-format share strings.
      #
      # @param shares [Array<String>] backup-format share strings
      # @return [PrivateKey]
      def self.from_backup_shares(shares)
        from_key_shares(KeyShares.from_backup_format(shares))
      end
    end
  end
end
