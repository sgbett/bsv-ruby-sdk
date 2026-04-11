# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Primitives::PrivateKey do
  let(:known_hex) { 'eaf02ca348c524e6392655ba4d29603cd1a7347d9d65cfe93ce1ebffdca22694' }
  let(:known_wif) { 'L56Q9sRtxUT1ax8rmxFVgJtggRw7VNqFKD2gynbabhNPgAL4Qpix' }
  let(:known_pubkey_hex) { '025ceeba2ab4a635df2c0301a3d773da06ac5a18a7c3e0d09a795d7e57d233edf1' }

  describe '.generate' do
    it 'generates a valid private key' do
      key = described_class.generate
      expect(key.bn).to be > OpenSSL::BN.new('0')
      expect(key.bn).to be < BSV::Primitives::Curve::N
    end

    it 'generates unique keys' do
      keys = Array.new(5) { described_class.generate.to_hex }
      expect(keys.uniq.length).to eq(5)
    end
  end

  describe '.from_bytes / #to_bytes' do
    it 'round-trips bytes' do
      bytes = [known_hex].pack('H*')
      key = described_class.from_bytes(bytes)
      expect(key.to_bytes).to eq(bytes)
    end

    it 'pads short keys to 32 bytes' do
      key = described_class.from_hex('01')
      expect(key.to_bytes.length).to eq(32)
      expect(key.to_bytes).to eq("#{"\x00" * 31}\u0001".b)
    end
  end

  describe '.from_hex / #to_hex' do
    it 'round-trips hex' do
      key = described_class.from_hex(known_hex)
      expect(key.to_hex).to eq(known_hex)
    end
  end

  describe '.from_wif / #to_wif' do
    it 'decodes a known mainnet compressed WIF' do
      key = described_class.from_wif(known_wif)
      expect(key.to_hex).to eq(known_hex)
    end

    it 'round-trips WIF (mainnet compressed)' do
      key = described_class.from_hex(known_hex)
      wif = key.to_wif
      expect(wif).to eq(known_wif)
      expect(described_class.from_wif(wif).to_hex).to eq(known_hex)
    end

    it 'always produces compressed WIF (F2.4: uncompressed export removed)' do
      key = described_class.from_hex(known_hex)
      wif = key.to_wif
      # Compressed mainnet WIF starts with 'K' or 'L'
      expect(wif).to match(/\A[KL]/)
      expect(wif).to eq(known_wif)
    end

    it 'rejects the removed compressed: false keyword (F2.4 breaking change)' do
      key = described_class.from_hex(known_hex)
      expect { key.to_wif(compressed: false) }.to raise_error(ArgumentError)
    end

    it 'from_wif still accepts legacy uncompressed WIF for import' do
      # Build an uncompressed WIF manually for round-trip testing
      prefix = "\x80".b
      payload = prefix + [known_hex].pack('H*') # no 0x01 suffix
      uncompressed_wif = BSV::Primitives::Base58.check_encode(payload)
      expect(uncompressed_wif).to start_with('5')
      expect(described_class.from_wif(uncompressed_wif).to_hex).to eq(known_hex)
    end

    it 'round-trips WIF (testnet compressed)' do
      key = described_class.from_hex(known_hex)
      wif = key.to_wif(network: :testnet)
      expect(wif).to start_with('c')
      expect(described_class.from_wif(wif).to_hex).to eq(known_hex)
    end

    it 'rejects invalid WIF with bad checksum' do
      expect { described_class.from_wif("#{known_wif.chop}X") }
        .to raise_error(StandardError)
    end

    it 'rejects WIF with unknown prefix' do
      # Construct a valid-checksum WIF with bad prefix 0xFF
      payload = "\xFF".b + [known_hex].pack('H*') + "\x01".b
      bad_wif = BSV::Primitives::Base58.check_encode(payload)
      expect { described_class.from_wif(bad_wif) }
        .to raise_error(ArgumentError, /unknown WIF network prefix/)
    end
  end

  describe '#public_key' do
    it 'derives the correct public key' do
      key = described_class.from_hex(known_hex)
      expect(key.public_key.to_hex).to eq(known_pubkey_hex)
    end

    it 'caches the public key' do
      key = described_class.from_hex(known_hex)
      expect(key.public_key).to equal(key.public_key)
    end
  end

  describe '#sign' do
    it 'produces a verifiable signature' do
      key = described_class.from_hex(known_hex)
      hash = BSV::Primitives::Digest.sha256('test message')
      sig = key.sign(hash)

      expect(key.public_key.verify(hash, sig)).to be true
    end

    it 'produces a deterministic signature' do
      key = described_class.from_hex(known_hex)
      hash = BSV::Primitives::Digest.sha256('deterministic')
      sig1 = key.sign(hash)
      sig2 = key.sign(hash)
      expect(sig1).to eq(sig2)
    end
  end

  describe 'validation' do
    it 'rejects zero private key' do
      expect { described_class.from_hex('00') }
        .to raise_error(ArgumentError, /out of range/)
    end

    it 'rejects private key >= N' do
      n_hex = BSV::Primitives::Curve::N.to_s(16)
      expect { described_class.from_hex(n_hex) }
        .to raise_error(ArgumentError, /out of range/)
    end
  end

  describe '#derive_shared_secret' do
    it 'returns a PublicKey' do
      alice = described_class.generate
      bob = described_class.generate
      shared = alice.derive_shared_secret(bob.public_key)
      expect(shared).to be_a(BSV::Primitives::PublicKey)
    end

    it 'is commutative' do
      alice = described_class.generate
      bob = described_class.generate
      shared_ab = alice.derive_shared_secret(bob.public_key)
      shared_ba = bob.derive_shared_secret(alice.public_key)
      expect(shared_ab).to eq(shared_ba)
    end

    it 'produces deterministic output' do
      alice = described_class.from_hex(known_hex)
      bob = described_class.generate
      s1 = alice.derive_shared_secret(bob.public_key)
      s2 = alice.derive_shared_secret(bob.public_key)
      expect(s1).to eq(s2)
    end
  end

  describe '#derive_child' do
    it 'returns a PrivateKey' do
      alice = described_class.generate
      bob = described_class.generate
      child = alice.derive_child(bob.public_key, 'invoice-1')
      expect(child).to be_a(described_class)
    end

    it 'derives a key different from the parent' do
      alice = described_class.generate
      bob = described_class.generate
      child = alice.derive_child(bob.public_key, 'invoice-1')
      expect(child.to_hex).not_to eq(alice.to_hex)
    end

    it 'produces different keys for different invoice numbers' do
      alice = described_class.generate
      bob = described_class.generate
      child1 = alice.derive_child(bob.public_key, 'invoice-1')
      child2 = alice.derive_child(bob.public_key, 'invoice-2')
      expect(child1.to_hex).not_to eq(child2.to_hex)
    end

    it 'is deterministic' do
      alice = described_class.from_hex(known_hex)
      bob = described_class.generate
      c1 = alice.derive_child(bob.public_key, 'test')
      c2 = alice.derive_child(bob.public_key, 'test')
      expect(c1.to_hex).to eq(c2.to_hex)
    end

    it 'produces a key whose public key matches PublicKey#derive_child' do
      alice = described_class.generate
      bob = described_class.generate
      child_priv = alice.derive_child(bob.public_key, 'invoice-1')
      child_pub = alice.public_key.derive_child(bob, 'invoice-1')
      expect(child_priv.public_key).to eq(child_pub)
    end
  end
end
