# frozen_string_literal: true

require 'openssl'

module BSV
  module Primitives
    # BRC-94 Schnorr zero-knowledge proof protocol.
    #
    # Provides generation and verification of Schnorr proofs for verifiable
    # revelation of ECDH shared secrets. Given two public keys A and B and
    # a shared secret S = a*B (where a is A's private key), the prover can
    # demonstrate knowledge of the discrete log relationship without
    # revealing the private key.
    #
    # @see https://github.com/bitcoin-sv/BRCs/blob/master/peer-to-peer/0094.md BRC-94
    module Schnorr
      # A Schnorr zero-knowledge proof consisting of a commitment point,
      # blinded shared secret, and response scalar.
      class Proof
        # @return [PublicKey] the commitment point R
        attr_reader :r

        # @return [PublicKey] the blinded shared secret S'
        attr_reader :s_prime

        # @return [OpenSSL::BN] the response scalar z
        attr_reader :z

        # @param r [PublicKey] commitment point
        # @param s_prime [PublicKey] blinded shared secret
        # @param z [OpenSSL::BN] response scalar
        def initialize(r, s_prime, z)
          @r = r
          @s_prime = s_prime
          @z = z
        end
      end

      module_function

      # Generate a Schnorr proof of knowledge of a shared secret.
      #
      # Proves that the prover knows the private key +a+ such that
      # +shared_secret = a * public_key_b+, without revealing +a+.
      #
      # @param private_key [PrivateKey] the prover's private key (a)
      # @param public_key_a [PublicKey] the prover's public key (A = a*G)
      # @param public_key_b [PublicKey] the counterparty's public key (B)
      # @param shared_secret [PublicKey] the ECDH shared secret (S = a*B)
      # @return [Proof] the Schnorr proof
      def generate_proof(private_key, public_key_a, public_key_b, shared_secret)
        nonce = PrivateKey.generate
        r_pub = nonce.public_key
        s_prime = PublicKey.new(Curve.multiply_point(public_key_b.point, nonce.bn))

        e = compute_challenge(public_key_a, public_key_b, shared_secret, s_prime, r_pub)

        z = (nonce.bn + (e * private_key.bn)) % Curve::N

        Proof.new(r_pub, s_prime, z)
      end

      # Verify a Schnorr proof of knowledge of a shared secret.
      #
      # Checks the two verification equations:
      # 1. z*G == R + e*A
      # 2. z*B == S' + e*S
      #
      # @param public_key_a [PublicKey] the prover's public key
      # @param public_key_b [PublicKey] the counterparty's public key
      # @param shared_secret [PublicKey] the claimed shared secret
      # @param proof [Proof] the Schnorr proof to verify
      # @return [Boolean] +true+ if the proof is valid
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
