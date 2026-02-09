# frozen_string_literal: true

require 'openssl'

module BSV
  module Primitives
    module ECDSA
      BYTE_LEN = 32 # secp256k1 order is 256 bits = 32 bytes

      module_function

      def sign(hash, private_key_bn)
        sig, _recovery_id = sign_raw(hash, private_key_bn)
        sig
      end

      def sign_recoverable(hash, private_key_bn)
        sign_raw(hash, private_key_bn)
      end

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

          r_point = Curve.multiply_generator(k)
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
