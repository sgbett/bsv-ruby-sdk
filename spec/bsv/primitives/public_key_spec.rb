# frozen_string_literal: true

RSpec.describe BSV::Primitives::PublicKey do
  let(:privkey_hex) { 'eaf02ca348c524e6392655ba4d29603cd1a7347d9d65cfe93ce1ebffdca22694' }
  let(:privkey_bn) { OpenSSL::BN.new(privkey_hex, 16) }
  let(:compressed_hex) { '025ceeba2ab4a635df2c0301a3d773da06ac5a18a7c3e0d09a795d7e57d233edf1' }

  describe '.from_hex / .from_bytes' do
    it 'constructs from compressed hex' do
      pubkey = described_class.from_hex(compressed_hex)
      expect(pubkey.to_hex).to eq(compressed_hex)
    end

    it 'constructs from uncompressed bytes' do
      point = BSV::Primitives::Curve.multiply_generator(privkey_bn)
      uncompressed = point.to_octet_string(:uncompressed)
      pubkey = described_class.from_bytes(uncompressed)
      expect(pubkey.to_hex).to eq(compressed_hex)
    end

    it 'raises on invalid point' do
      expect { described_class.from_bytes("\x00".b) }.to raise_error(StandardError)
    end
  end

  describe '#compressed / #uncompressed' do
    it 'returns 33-byte compressed form' do
      pubkey = described_class.from_hex(compressed_hex)
      expect(pubkey.compressed.length).to eq(33)
      expect(pubkey.compressed[0].ord).to be_between(0x02, 0x03)
    end

    it 'returns 65-byte uncompressed form' do
      pubkey = described_class.from_hex(compressed_hex)
      expect(pubkey.uncompressed.length).to eq(65)
      expect(pubkey.uncompressed[0].ord).to eq(0x04)
    end
  end

  describe '#to_hex' do
    it 'returns compressed hex by default' do
      pubkey = described_class.from_hex(compressed_hex)
      expect(pubkey.to_hex).to eq(compressed_hex)
    end

    it 'returns uncompressed hex when requested' do
      pubkey = described_class.from_hex(compressed_hex)
      hex = pubkey.to_hex(compressed: false)
      expect(hex.length).to eq(130) # 65 bytes = 130 hex chars
      expect(hex).to start_with('04')
    end
  end

  describe '#hash160' do
    it 'computes Hash160 of the compressed public key' do
      # Generator point compressed pubkey hash160 is known
      gen_point = BSV::Primitives::Curve::G
      pubkey = described_class.new(gen_point)
      expect(pubkey.hash160.unpack1('H*')).to eq('751e76e8199196d454941c45d1b3a323f1433bd6')
    end
  end

  describe '#address' do
    it 'returns a mainnet P2PKH address' do
      gen_point = BSV::Primitives::Curve::G
      pubkey = described_class.new(gen_point)
      expect(pubkey.address).to eq('1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH')
    end

    it 'returns a testnet P2PKH address' do
      gen_point = BSV::Primitives::Curve::G
      pubkey = described_class.new(gen_point)
      addr = pubkey.address(network: :testnet)
      expect(addr).to start_with('m') | start_with('n')
    end
  end

  describe '#verify' do
    it 'verifies a valid signature' do
      pubkey = described_class.from_hex(compressed_hex)
      hash = BSV::Primitives::Digest.sha256('hello')
      sig = BSV::Primitives::ECDSA.sign(hash, privkey_bn)
      expect(pubkey.verify(hash, sig)).to be true
    end

    it 'rejects an invalid signature' do
      pubkey = described_class.from_hex(compressed_hex)
      hash = BSV::Primitives::Digest.sha256('hello')
      wrong_hash = BSV::Primitives::Digest.sha256('wrong')
      sig = BSV::Primitives::ECDSA.sign(hash, privkey_bn)
      expect(pubkey.verify(wrong_hash, sig)).to be false
    end
  end

  describe '#==' do
    it 'considers two public keys from the same point equal' do
      pk1 = described_class.from_hex(compressed_hex)
      pk2 = described_class.from_hex(compressed_hex)
      expect(pk1).to eq(pk2)
    end
  end

  describe '#derive_shared_secret' do
    it 'returns a PublicKey' do
      alice = BSV::Primitives::PrivateKey.generate
      shared = alice.public_key.derive_shared_secret(alice)
      expect(shared).to be_a(described_class)
    end

    it 'matches PrivateKey#derive_shared_secret' do
      alice = BSV::Primitives::PrivateKey.generate
      bob = BSV::Primitives::PrivateKey.generate
      from_priv = alice.derive_shared_secret(bob.public_key)
      from_pub = bob.public_key.derive_shared_secret(alice)
      expect(from_priv).to eq(from_pub)
    end
  end
end
