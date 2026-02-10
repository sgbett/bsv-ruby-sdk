# frozen_string_literal: true

RSpec.describe BSV::Primitives::Schnorr do
  let(:key_a) { BSV::Primitives::PrivateKey.from_hex('1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef') }
  let(:key_b) { BSV::Primitives::PrivateKey.from_hex('fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321') }
  let(:pub_a) { key_a.public_key }
  let(:pub_b) { key_b.public_key }
  let(:shared_secret) do
    point = BSV::Primitives::Curve.multiply_point(pub_b.point, key_a.bn)
    BSV::Primitives::PublicKey.new(point)
  end

  describe '.generate_proof' do
    it 'returns a Proof with correct types' do
      proof = described_class.generate_proof(key_a, pub_a, pub_b, shared_secret)

      expect(proof).to be_a(BSV::Primitives::Schnorr::Proof)
      expect(proof.r).to be_a(BSV::Primitives::PublicKey)
      expect(proof.s_prime).to be_a(BSV::Primitives::PublicKey)
      expect(proof.z).to be_a(OpenSSL::BN)
    end

    it 'produces different proofs each time (random nonce)' do
      proof1 = described_class.generate_proof(key_a, pub_a, pub_b, shared_secret)
      proof2 = described_class.generate_proof(key_a, pub_a, pub_b, shared_secret)

      expect(proof1.r.compressed).not_to eq(proof2.r.compressed)
    end
  end

  describe '.verify_proof' do
    it 'verifies a valid proof with fixed keys' do
      proof = described_class.generate_proof(key_a, pub_a, pub_b, shared_secret)
      result = described_class.verify_proof(pub_a, pub_b, shared_secret, proof)

      expect(result).to be true
    end

    it 'verifies a valid proof with random keys' do
      a = BSV::Primitives::PrivateKey.generate
      b = BSV::Primitives::PrivateKey.generate
      s = BSV::Primitives::PublicKey.new(BSV::Primitives::Curve.multiply_point(b.public_key.point, a.bn))

      proof = described_class.generate_proof(a, a.public_key, b.public_key, s)
      expect(described_class.verify_proof(a.public_key, b.public_key, s, proof)).to be true
    end

    it 'round-trips with multiple key pairs' do
      3.times do
        a = BSV::Primitives::PrivateKey.generate
        b = BSV::Primitives::PrivateKey.generate
        s = BSV::Primitives::PublicKey.new(BSV::Primitives::Curve.multiply_point(b.public_key.point, a.bn))

        proof = described_class.generate_proof(a, a.public_key, b.public_key, s)
        expect(described_class.verify_proof(a.public_key, b.public_key, s, proof)).to be true
      end
    end
  end

  describe 'tamper detection' do
    let(:proof) { described_class.generate_proof(key_a, pub_a, pub_b, shared_secret) }

    it 'rejects tampered R' do
      other_key = BSV::Primitives::PrivateKey.generate
      tampered = BSV::Primitives::Schnorr::Proof.new(other_key.public_key, proof.s_prime, proof.z)

      expect(described_class.verify_proof(pub_a, pub_b, shared_secret, tampered)).to be false
    end

    it 'rejects tampered z' do
      tampered_z = (proof.z + OpenSSL::BN.new('1')) % BSV::Primitives::Curve::N
      tampered = BSV::Primitives::Schnorr::Proof.new(proof.r, proof.s_prime, tampered_z)

      expect(described_class.verify_proof(pub_a, pub_b, shared_secret, tampered)).to be false
    end

    it 'rejects tampered S\'' do
      other_key = BSV::Primitives::PrivateKey.generate
      tampered = BSV::Primitives::Schnorr::Proof.new(proof.r, other_key.public_key, proof.z)

      expect(described_class.verify_proof(pub_a, pub_b, shared_secret, tampered)).to be false
    end

    it 'rejects wrong public key A' do
      wrong_a = BSV::Primitives::PrivateKey.generate.public_key

      expect(described_class.verify_proof(wrong_a, pub_b, shared_secret, proof)).to be false
    end

    it 'rejects wrong public key B' do
      wrong_b = BSV::Primitives::PrivateKey.generate.public_key

      expect(described_class.verify_proof(pub_a, wrong_b, shared_secret, proof)).to be false
    end

    it 'rejects wrong shared secret' do
      wrong_secret_point = BSV::Primitives::Curve.multiply_generator(OpenSSL::BN.new('42'))
      wrong_secret = BSV::Primitives::PublicKey.new(wrong_secret_point)

      expect(described_class.verify_proof(pub_a, pub_b, wrong_secret, proof)).to be false
    end
  end

  describe 'edge cases' do
    it 'fails verification when proof is generated with wrong private key' do
      wrong_key = BSV::Primitives::PrivateKey.generate
      proof = described_class.generate_proof(wrong_key, pub_a, pub_b, shared_secret)

      expect(described_class.verify_proof(pub_a, pub_b, shared_secret, proof)).to be false
    end

    it 'verifies that shared secret is commutative (a·B == b·A)' do
      s_from_a = BSV::Primitives::PublicKey.new(BSV::Primitives::Curve.multiply_point(pub_b.point, key_a.bn))
      s_from_b = BSV::Primitives::PublicKey.new(BSV::Primitives::Curve.multiply_point(pub_a.point, key_b.bn))

      expect(s_from_a.compressed).to eq(s_from_b.compressed)

      proof = described_class.generate_proof(key_a, pub_a, pub_b, s_from_a)
      expect(described_class.verify_proof(pub_a, pub_b, s_from_b, proof)).to be true
    end
  end
end
