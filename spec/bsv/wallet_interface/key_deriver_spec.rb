# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::KeyDeriver do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:deriver) { described_class.new(private_key) }
  let(:protocol_id) { [0, 'hello world'] }
  let(:key_id) { 'test key 1' }

  describe '#initialize' do
    it 'accepts a PrivateKey and stores it as root_key' do
      expect(deriver.root_key).to eq(private_key)
    end

    it 'accepts "anyone" and creates a PrivateKey with BN(1)' do
      anyone_deriver = described_class.new('anyone')
      expect(anyone_deriver.root_key).to be_a(BSV::Primitives::PrivateKey)
    end
  end

  describe '#identity_key' do
    it 'returns a 66-character lowercase hex string' do
      key = deriver.identity_key
      expect(key).to be_a(String)
      expect(key.length).to eq(66)
      expect(key).to match(/\A[0-9a-f]{66}\z/)
    end

    it 'matches the compressed public key of the root key' do
      expect(deriver.identity_key).to eq(private_key.public_key.to_hex)
    end

    it 'returns different values for different root keys' do
      other_deriver = described_class.new(BSV::Primitives::PrivateKey.generate)
      expect(deriver.identity_key).not_to eq(other_deriver.identity_key)
    end
  end

  describe '#derive_public_key' do
    it 'returns a PublicKey instance' do
      pub = deriver.derive_public_key(protocol_id, key_id, 'self')
      expect(pub).to be_a(BSV::Primitives::PublicKey)
    end

    it 'derives different keys for different key IDs' do
      pub1 = deriver.derive_public_key(protocol_id, 'key1', 'self')
      pub2 = deriver.derive_public_key(protocol_id, 'key2', 'self')
      expect(pub1.to_hex).not_to eq(pub2.to_hex)
    end

    it 'derives different keys for different security levels' do
      pub1 = deriver.derive_public_key([0, 'hello world'], key_id, 'self')
      pub2 = deriver.derive_public_key([1, 'hello world'], key_id, 'self')
      expect(pub1.to_hex).not_to eq(pub2.to_hex)
    end

    it 'derives different keys for different protocol names' do
      pub1 = deriver.derive_public_key([0, 'hello world'], key_id, 'self')
      pub2 = deriver.derive_public_key([0, 'other proto'], key_id, 'self')
      expect(pub1.to_hex).not_to eq(pub2.to_hex)
    end

    it 'raises InvalidParameterError for an invalid protocol ID' do
      expect { deriver.derive_public_key([3, 'hello world'], key_id, 'self') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError for an empty key ID' do
      expect { deriver.derive_public_key(protocol_id, '', 'self') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'accepts "anyone" as the counterparty' do
      pub = deriver.derive_public_key(protocol_id, key_id, 'anyone')
      expect(pub).to be_a(BSV::Primitives::PublicKey)
    end

    it 'accepts a real counterparty public key hex' do
      cp_hex = BSV::Primitives::PrivateKey.generate.public_key.to_hex
      pub = deriver.derive_public_key(protocol_id, key_id, cp_hex)
      expect(pub).to be_a(BSV::Primitives::PublicKey)
    end
  end

  describe '#derive_private_key' do
    it 'returns a PrivateKey instance' do
      priv = deriver.derive_private_key(protocol_id, key_id, 'self')
      expect(priv).to be_a(BSV::Primitives::PrivateKey)
    end

    it 'derives a key whose public key matches derive_public_key with for_self: true' do
      priv = deriver.derive_private_key(protocol_id, key_id, 'self')
      pub = deriver.derive_public_key(protocol_id, key_id, 'self', for_self: true)
      expect(priv.public_key.to_hex).to eq(pub.to_hex)
    end

    it 'derives different private keys for different key IDs' do
      priv1 = deriver.derive_private_key(protocol_id, 'key1', 'self')
      priv2 = deriver.derive_private_key(protocol_id, 'key2', 'self')
      expect(priv1.to_hex).not_to eq(priv2.to_hex)
    end
  end

  describe '#derive_symmetric_key' do
    it 'returns a SymmetricKey instance' do
      sym = deriver.derive_symmetric_key(protocol_id, key_id, 'self')
      expect(sym).to be_a(BSV::Primitives::SymmetricKey)
    end

    it 'derives different keys for different key IDs' do
      sym1 = deriver.derive_symmetric_key(protocol_id, 'key1', 'self')
      sym2 = deriver.derive_symmetric_key(protocol_id, 'key2', 'self')
      expect(sym1.to_bytes).not_to eq(sym2.to_bytes)
    end

    it 'produces a key that can round-trip encrypt and decrypt' do
      sym = deriver.derive_symmetric_key(protocol_id, key_id, 'self')
      plaintext = 'hello bsv wallet'
      ciphertext = sym.encrypt(plaintext)
      expect(sym.decrypt(ciphertext)).to eq(plaintext)
    end

    it 'raises InvalidParameterError for an invalid protocol ID' do
      expect { deriver.derive_symmetric_key([99, 'hello world'], key_id, 'self') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  describe '#reveal_counterparty_secret' do
    let(:counterparty_key) { BSV::Primitives::PrivateKey.generate }

    it 'returns a binary string' do
      secret = deriver.reveal_counterparty_secret(counterparty_key.public_key.to_hex)
      expect(secret).to be_a(String)
      expect(secret.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it 'returns a 33-byte compressed point (the ECDH shared secret)' do
      secret = deriver.reveal_counterparty_secret(counterparty_key.public_key.to_hex)
      expect(secret.bytesize).to eq(33)
    end

    it 'raises InvalidParameterError for "self" as counterparty' do
      expect { deriver.reveal_counterparty_secret('self') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'returns different secrets for different counterparties' do
      cp2 = BSV::Primitives::PrivateKey.generate
      s1 = deriver.reveal_counterparty_secret(counterparty_key.public_key.to_hex)
      s2 = deriver.reveal_counterparty_secret(cp2.public_key.to_hex)
      expect(s1).not_to eq(s2)
    end
  end

  describe '#reveal_specific_secret' do
    let(:counterparty_key) { BSV::Primitives::PrivateKey.generate }

    it 'returns a 32-byte binary string' do
      secret = deriver.reveal_specific_secret(counterparty_key.public_key.to_hex, protocol_id, key_id)
      expect(secret).to be_a(String)
      expect(secret.bytesize).to eq(32)
    end

    it 'returns different secrets for different key IDs' do
      cp_hex = counterparty_key.public_key.to_hex
      s1 = deriver.reveal_specific_secret(cp_hex, protocol_id, 'key1')
      s2 = deriver.reveal_specific_secret(cp_hex, protocol_id, 'key2')
      expect(s1).not_to eq(s2)
    end

    it 'returns different secrets for different protocol IDs' do
      cp_hex = counterparty_key.public_key.to_hex
      s1 = deriver.reveal_specific_secret(cp_hex, [0, 'hello world'], key_id)
      s2 = deriver.reveal_specific_secret(cp_hex, [1, 'hello world'], key_id)
      expect(s1).not_to eq(s2)
    end

    it 'returns different secrets for different counterparties' do
      cp2 = BSV::Primitives::PrivateKey.generate
      s1 = deriver.reveal_specific_secret(counterparty_key.public_key.to_hex, protocol_id, key_id)
      s2 = deriver.reveal_specific_secret(cp2.public_key.to_hex, protocol_id, key_id)
      expect(s1).not_to eq(s2)
    end
  end
end
