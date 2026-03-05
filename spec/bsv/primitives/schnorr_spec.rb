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

  # Fixed-nonce vectors for cross-SDK interoperability. The challenge computation
  # (SHA256 of compressed points) and verification equations match the Go SDK.
  # These proofs were generated with known nonces so the output is deterministic.
  describe 'cross-SDK interoperability vectors' do
    it 'verifies a proof generated with known keys and nonce (vector 1)' do
      pub_a = BSV::Primitives::PublicKey.from_bytes(['02bb50e2d89a4ed70663d080659fe0ad4b9bc3e06c17a227433966cb59ceee020d'].pack('H*'))
      pub_b = BSV::Primitives::PublicKey.from_bytes(['0297855f402631f09e602e5ccadc219503f07cdd4c73b2215b5418f52a7fdbfcd9'].pack('H*'))
      shared = BSV::Primitives::PublicKey.from_bytes(['032a15f55ab4d9474165e927d1b3c8e9dc0df2de76c09e4ef8072087c829af171d'].pack('H*'))
      r = BSV::Primitives::PublicKey.from_bytes(['026a04ab98d9e4774ad806e302dddeb63bea16b5cb5f223ee77478e861bb583eb3'].pack('H*'))
      s_prime = BSV::Primitives::PublicKey.from_bytes(['03b5eff34e21bd26e97aa1a7f18d65db160695d1820dfe023706051041137c30d7'].pack('H*'))
      z = OpenSSL::BN.new('b5099ccc04e4e054b9dca7ff6373809bcd2e1b4b1d7c7da1cfccde988a18881a', 16)

      proof = BSV::Primitives::Schnorr::Proof.new(r, s_prime, z)
      expect(described_class.verify_proof(pub_a, pub_b, shared, proof)).to be true
    end

    it 'verifies a proof with minimal private keys (vector 2)' do
      # key_c = 1, key_d = 2 (leading zero bytes)
      pub_c = BSV::Primitives::PublicKey.from_bytes(['0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798'].pack('H*'))
      pub_d = BSV::Primitives::PublicKey.from_bytes(['02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5'].pack('H*'))
      shared = BSV::Primitives::PublicKey.from_bytes(['02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5'].pack('H*'))
      r = BSV::Primitives::PublicKey.from_bytes(['0268680737c76dabb801cb2204f57dbe4e4579e4f710cd67dc1b4227592c81e9b5'].pack('H*'))
      s_prime = BSV::Primitives::PublicKey.from_bytes(['02d6db78f56b8e36a5e1ae8aeddd657e5fc1e04b625876f76fb82a19495dfe5fde'].pack('H*'))
      z = OpenSSL::BN.new('5880696de16902557ba5824cef3f058afe704c1f8dc01e5be7bad452f837e96a', 16)

      proof = BSV::Primitives::Schnorr::Proof.new(r, s_prime, z)
      expect(described_class.verify_proof(pub_c, pub_d, shared, proof)).to be true
    end

    it 'rejects a cross-SDK vector with tampered z' do
      pub_a = BSV::Primitives::PublicKey.from_bytes(['02bb50e2d89a4ed70663d080659fe0ad4b9bc3e06c17a227433966cb59ceee020d'].pack('H*'))
      pub_b = BSV::Primitives::PublicKey.from_bytes(['0297855f402631f09e602e5ccadc219503f07cdd4c73b2215b5418f52a7fdbfcd9'].pack('H*'))
      shared = BSV::Primitives::PublicKey.from_bytes(['032a15f55ab4d9474165e927d1b3c8e9dc0df2de76c09e4ef8072087c829af171d'].pack('H*'))
      r = BSV::Primitives::PublicKey.from_bytes(['026a04ab98d9e4774ad806e302dddeb63bea16b5cb5f223ee77478e861bb583eb3'].pack('H*'))
      s_prime = BSV::Primitives::PublicKey.from_bytes(['03b5eff34e21bd26e97aa1a7f18d65db160695d1820dfe023706051041137c30d7'].pack('H*'))
      z = OpenSSL::BN.new('b5099ccc04e4e054b9dca7ff6373809bcd2e1b4b1d7c7da1cfccde988a18881b', 16) # +1

      proof = BSV::Primitives::Schnorr::Proof.new(r, s_prime, z)
      expect(described_class.verify_proof(pub_a, pub_b, shared, proof)).to be false
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
