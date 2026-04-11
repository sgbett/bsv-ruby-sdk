# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Primitives::ECIES do
  let(:alice) { BSV::Primitives::PrivateKey.generate }
  let(:bob) { BSV::Primitives::PrivateKey.generate }

  describe '.bitcore_encrypt / .bitcore_decrypt' do
    it 'round-trips a message' do
      ciphertext = described_class.bitcore_encrypt('hello world', bob.public_key)
      plaintext = described_class.bitcore_decrypt(ciphertext, bob)
      expect(plaintext).to eq('hello world'.b)
    end

    it 'round-trips an empty message' do
      ciphertext = described_class.bitcore_encrypt('', bob.public_key)
      plaintext = described_class.bitcore_decrypt(ciphertext, bob)
      expect(plaintext).to eq(''.b)
    end

    it 'round-trips binary data' do
      data = (0..255).to_a.pack('C*')
      ciphertext = described_class.bitcore_encrypt(data, bob.public_key)
      plaintext = described_class.bitcore_decrypt(ciphertext, bob)
      expect(plaintext).to eq(data)
    end

    it 'produces different ciphertext each time (random IV)' do
      ct1 = described_class.bitcore_encrypt('same', bob.public_key)
      ct2 = described_class.bitcore_encrypt('same', bob.public_key)
      expect(ct1).not_to eq(ct2)
    end

    it 'accepts an explicit ephemeral key' do
      ephemeral = BSV::Primitives::PrivateKey.generate
      ciphertext = described_class.bitcore_encrypt('test', bob.public_key, private_key: ephemeral)
      plaintext = described_class.bitcore_decrypt(ciphertext, bob)
      expect(plaintext).to eq('test'.b)
    end
  end

  describe 'wire format' do
    it 'starts with the ephemeral public key (33 bytes)' do
      ciphertext = described_class.bitcore_encrypt('test', bob.public_key, private_key: alice)
      first_byte = ciphertext.getbyte(0)
      expect(first_byte).to eq(0x02).or eq(0x03)
      expect(ciphertext.bytesize).to be >= 97 # 33 + 16 + 16 + 32
    end

    it 'has no BIE1 magic prefix' do
      ciphertext = described_class.bitcore_encrypt('test', bob.public_key)
      expect(ciphertext[0, 4]).not_to eq('BIE1'.b)
    end

    it 'ends with a 32-byte HMAC' do
      ciphertext = described_class.bitcore_encrypt('test', bob.public_key)
      # HMAC is over IV + ciphertext, not including ephemeral pubkey
      expect(ciphertext.bytesize).to be >= 97
    end
  end

  describe 'error handling' do
    it 'raises ArgumentError for data too short' do
      expect { described_class.bitcore_decrypt('short'.b, bob) }.to raise_error(ArgumentError, /too short/)
    end

    it 'raises DecryptionError for tampered HMAC' do
      ciphertext = described_class.bitcore_encrypt('test', bob.public_key)
      tampered = ciphertext.dup
      tampered[-1] = (tampered.getbyte(-1) ^ 0xFF).chr
      expect { described_class.bitcore_decrypt(tampered, bob) }.to raise_error(BSV::Primitives::ECIES::DecryptionError, /HMAC/)
    end

    it 'raises DecryptionError for wrong key' do
      ciphertext = described_class.bitcore_encrypt('test', bob.public_key)
      wrong_key = BSV::Primitives::PrivateKey.generate
      expect { described_class.bitcore_decrypt(ciphertext, wrong_key) }.to raise_error(BSV::Primitives::ECIES::DecryptionError)
    end

    it 'raises DecryptionError for tampered ciphertext' do
      ciphertext = described_class.bitcore_encrypt('test', bob.public_key)
      tampered = ciphertext.dup
      tampered[50] = (tampered.getbyte(50) ^ 0xFF).chr
      expect { described_class.bitcore_decrypt(tampered, bob) }.to raise_error(BSV::Primitives::ECIES::DecryptionError)
    end
  end

  describe 'cross-variant isolation' do
    it 'Electrum ciphertext cannot be decrypted with Bitcore' do
      electrum_ct = described_class.encrypt('test', bob.public_key)
      expect { described_class.bitcore_decrypt(electrum_ct, bob) }.to raise_error(StandardError)
    end

    it 'Bitcore ciphertext cannot be decrypted with Electrum' do
      bitcore_ct = described_class.bitcore_encrypt('test', bob.public_key)
      expect { described_class.decrypt(bitcore_ct, bob) }.to raise_error(StandardError)
    end
  end
end
