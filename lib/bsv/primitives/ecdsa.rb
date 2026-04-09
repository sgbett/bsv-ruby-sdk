# frozen_string_literal: true

require 'openssl'

module BSV
  module Primitives
    # Deterministic ECDSA signing and verification on secp256k1.
    #
    # Implements RFC 6979 deterministic nonce generation to produce
    # signatures that are fully reproducible from the same (key, hash)
    # pair. All signatures are normalised to low-S form (BIP-62 rule 5).
    #
    # Typically used indirectly via {PrivateKey#sign} and {PublicKey#verify}
    # rather than calling this module directly.
    module ECDSA
      # Byte length of a secp256k1 scalar (256 bits).
      BYTE_LEN = 32 # secp256k1 order is 256 bits = 32 bytes

      module_function

      # Sign a 32-byte message hash with a private key.
      #
      # By default the signature is low-S normalised per BIP-62 rule 5, as
      # required by BSV consensus. Pass +force_low_s: true+ to explicitly
      # enforce normalisation even when calling code cannot guarantee it
      # (e.g. when wrapping external signing paths).
      #
      # @param hash [String] 32-byte message digest
      # @param private_key_bn [OpenSSL::BN] the private key scalar
      # @param force_low_s [Boolean] normalise S to the lower half when true
      # @return [Signature] a deterministic signature
      def sign(hash, private_key_bn, force_low_s: false)
        sig, _recovery_id = sign_raw(hash, private_key_bn)
        force_low_s ? sig.to_low_s : sig
      end

      # Sign a hash and return both the signature and recovery ID.
      #
      # The recovery ID (0-3) allows the public key to be recovered
      # from the signature without knowing it in advance, as used by
      # Bitcoin Signed Messages (BSM) and compact signature formats.
      #
      # @param hash [String] 32-byte message digest
      # @param private_key_bn [OpenSSL::BN] the private key scalar
      # @return [Array(Signature, Integer)] the signature and recovery ID
      def sign_recoverable(hash, private_key_bn)
        sign_raw(hash, private_key_bn)
      end

      # Recover a public key from a signature and recovery ID.
      #
      # Given a message hash, signature, and the recovery ID produced
      # during signing, reconstructs the public key that created the
      # signature.
      #
      # @param hash [String] 32-byte message digest that was signed
      # @param signature [Signature] the ECDSA signature
      # @param recovery_id [Integer] recovery ID (0-3)
      # @return [PublicKey] the recovered public key
      # @raise [ArgumentError] if the recovered point is at infinity
      def recover_public_key(hash, signature, recovery_id)
        r = signature.r
        s = signature.s
        n = Curve::N

        # Reconstruct R.x (may include overflow when recovery_id >= 2)
        x = recovery_id >= 2 ? r + n : r

        # Decompress R from x-coordinate and y-parity
        prefix = (recovery_id & 1).odd? ? "\x03".b : "\x02".b
        x_bytes = x.to_s(2)
        x_bytes = ("\x00".b * (32 - x_bytes.length)) + x_bytes if x_bytes.length < 32
        r_point = Curve.point_from_bytes(prefix + x_bytes)

        # Q = r^(-1) * (s*R - e*G)
        r_inv = r.mod_inverse(n)
        e = OpenSSL::BN.new(hash, 2)
        u1 = ((n - e) * r_inv) % n
        u2 = (s * r_inv) % n

        p1 = Curve.multiply_generator(u1)
        p2 = Curve.multiply_point(r_point, u2)
        q = Curve.add_points(p1, p2)

        raise ArgumentError, 'recovered point is at infinity' if q.infinity?

        PublicKey.new(q)
      end

      # Verify an ECDSA signature against a message hash and public key.
      #
      # @param hash [String] 32-byte message digest
      # @param signature [Signature] the signature to verify
      # @param public_key_point [OpenSSL::PKey::EC::Point] the signer's public key point
      # @return [Boolean] +true+ if the signature is valid
      def verify(hash, signature, public_key_point)
        r = signature.r
        s = signature.s
        n = Curve::N

        return false if r <= OpenSSL::BN.new('0') || r >= n
        return false if s <= OpenSSL::BN.new('0') || s >= n

        e = OpenSSL::BN.new(hash, 2)
        s_inv = s.mod_inverse(n)

        u1 = (e * s_inv) % n
        u2 = (r * s_inv) % n

        # R' = u1*G + u2*Q
        point1 = Curve.multiply_generator(u1)
        point2 = Curve.multiply_point(public_key_point, u2)
        result_point = Curve.add_points(point1, point2)

        return false if result_point.infinity?

        x = Curve.point_x(result_point) % n
        x == r
      end

      class << self
        private

        def sign_raw(hash, private_key_bn)
          k = nonce_rfc6979(private_key_bn, hash)
          k_inv = k.mod_inverse(Curve::N)

          # Use constant-time multiplication for the secret nonce k to
          # prevent timing side-channels during signing.
          r_point = Curve.multiply_generator_ct(k)
          r = Curve.point_x(r_point) % Curve::N
          raise 'calculated R is zero' if r.zero?

          e = OpenSSL::BN.new(hash, 2)
          s = (k_inv * ((e + (private_key_bn * r)) % Curve::N)) % Curve::N
          raise 'calculated S is zero' if s.zero?

          # Recovery ID: bit 0 = R.y parity, bit 1 = R.x overflow (>= N)
          r_y_odd = r_point.to_octet_string(:compressed).getbyte(0) == 0x03
          r_overflow = Curve.point_x(r_point) >= Curve::N
          recovery_id = (r_y_odd ? 1 : 0) + (r_overflow ? 2 : 0)

          sig = Signature.new(r, s)
          unless sig.low_s?
            sig = sig.to_low_s
            recovery_id ^= 1 # Flipping s negates R.y, toggling parity
          end

          [sig, recovery_id]
        end

        # RFC 6979 Section 3.2 — deterministic k generation for secp256k1/SHA-256
        def nonce_rfc6979(privkey_bn, hash)
          q = Curve::N
          qlen = q.num_bits # 256 for secp256k1
          rolen = (qlen + 7) >> 3 # 32

          # a. Process input: private key as fixed-width octets
          x_bytes = int2octets(privkey_bn, rolen)
          # b. Process hash
          h_bytes = bits2octets(hash, rolen)

          # bx = int2octets(x) || bits2octets(hash)
          bx = x_bytes + h_bytes

          # Step B: V = 0x01 * hlen (32 bytes of 0x01)
          v = "\x01".b * 32

          # Step C: K = 0x00 * hlen (32 bytes of 0x00)
          k = "\x00".b * 32

          # Step D: K = HMAC(K, V || 0x00 || bx)
          k = Digest.hmac_sha256(k, v + "\x00".b + bx)

          # Step E: V = HMAC(K, V)
          v = Digest.hmac_sha256(k, v)

          # Step F: K = HMAC(K, V || 0x01 || bx)
          k = Digest.hmac_sha256(k, v + "\x01".b + bx)

          # Step G: V = HMAC(K, V)
          v = Digest.hmac_sha256(k, v)

          # Step H: Generate and test candidates
          loop do
            # H1/H2: Generate qlen bits
            t = ''.b
            while t.length * 8 < qlen
              v = Digest.hmac_sha256(k, v)
              t += v
            end

            # H3: Convert to integer and test
            secret = bits2int(t, qlen)
            return secret if secret >= OpenSSL::BN.new('1') && secret < q

            # Not valid — update K, V and retry
            k = Digest.hmac_sha256(k, v + "\x00".b)
            v = Digest.hmac_sha256(k, v)
          end
        end

        # Convert integer to fixed-width big-endian octets
        def int2octets(bn, rolen)
          bytes = bn.to_s(2)
          if bytes.length > rolen
            bytes[-rolen, rolen]
          elsif bytes.length < rolen
            ("\x00".b * (rolen - bytes.length)) + bytes
          else
            bytes
          end
        end

        # Convert hash bits to integer, reduce mod q, then to octets
        def bits2octets(hash_bytes, rolen)
          z1 = bits2int(hash_bytes, Curve::N.num_bits)
          z2 = z1 % Curve::N
          int2octets(z2, rolen)
        end

        # Convert bit string to integer, right-shifting if longer than qlen
        def bits2int(bytes, qlen)
          blen = bytes.length * 8
          v = OpenSSL::BN.new(bytes, 2)
          v >>= (blen - qlen) if blen > qlen
          v
        end
      end
    end
  end
end
