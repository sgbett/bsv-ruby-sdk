# frozen_string_literal: true

require 'openssl'

module BSV
  module Primitives
    # BRC-94 Schnorr zero-knowledge proof protocol for verifiable
    # revelation of shared secrets.
    module Schnorr
      class Proof
        attr_reader :r, :s_prime, :z

        def initialize(r, s_prime, z)
          @r = r
          @s_prime = s_prime
          @z = z
        end
      end

      module_function

      def generate_proof(private_key, public_key_a, public_key_b, shared_secret)
        nonce = PrivateKey.generate
        r_pub = nonce.public_key
        s_prime = PublicKey.new(Curve.multiply_point(public_key_b.point, nonce.bn))

        e = compute_challenge(public_key_a, public_key_b, shared_secret, s_prime, r_pub)

        z = (nonce.bn + (e * private_key.bn)) % Curve::N

        Proof.new(r_pub, s_prime, z)
      end

      def verify_proof(public_key_a, public_key_b, shared_secret, proof)
        e = compute_challenge(public_key_a, public_key_b, shared_secret, proof.s_prime, proof.r)

        # Equation 1: z·G == R + e·A
        z_g = Curve.multiply_generator(proof.z)
        e_a = Curve.multiply_point(public_key_a.point, e)
        r_plus_ea = Curve.add_points(proof.r.point, e_a)

        return false unless points_equal?(z_g, r_plus_ea)

        # Equation 2: z·B == S' + e·S
        z_b = Curve.multiply_point(public_key_b.point, proof.z)
        e_s = Curve.multiply_point(shared_secret.point, e)
        sp_plus_es = Curve.add_points(proof.s_prime.point, e_s)

        points_equal?(z_b, sp_plus_es)
      end

      class << self
        private

        def compute_challenge(pub_a, pub_b, s, s_prime, r)
          message = pub_a.compressed + pub_b.compressed +
                    s.compressed + s_prime.compressed + r.compressed
          hash = Digest.sha256(message)
          OpenSSL::BN.new(hash, 2) % Curve::N
        end

        def points_equal?(p1, p2)
          p1.to_octet_string(:compressed) == p2.to_octet_string(:compressed)
        end
      end
    end
  end
end
