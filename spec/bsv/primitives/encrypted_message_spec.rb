# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Primitives::EncryptedMessage do
  let(:sender) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(15)) }
  let(:recipient) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(21)) }
  let(:message) { [1, 2, 4, 8, 16, 32].pack('C*') }

  describe '.encrypt / .decrypt' do
    it 'round-trips encrypt and decrypt' do
      ct = described_class.encrypt(message, sender, recipient.public_key)
      expect(described_class.decrypt(ct, recipient)).to eq(message)
    end

    it 'produces binary output with correct header' do
      ct = described_class.encrypt(message, sender, recipient.public_key)
      # VERSION(4) + sender_pub(33) + recipient_pub(33) + key_id(32) + AES-GCM payload
      expect(ct.bytesize).to be >= 102
      expect(ct.byteslice(0, 4)).to eq("\x42\x42\x10\x33".b)
    end

    it 'includes sender public key in wire format' do
      ct = described_class.encrypt(message, sender, recipient.public_key)
      sender_pub_bytes = ct.byteslice(4, 33)
      expect(sender_pub_bytes).to eq(sender.public_key.compressed)
    end

    it 'includes recipient public key in wire format' do
      ct = described_class.encrypt(message, sender, recipient.public_key)
      recipient_pub_bytes = ct.byteslice(37, 33)
      expect(recipient_pub_bytes).to eq(recipient.public_key.compressed)
    end

    it 'produces unique key IDs each time' do
      ct1 = described_class.encrypt(message, sender, recipient.public_key)
      ct2 = described_class.encrypt(message, sender, recipient.public_key)
      key_id1 = ct1.byteslice(70, 32)
      key_id2 = ct2.byteslice(70, 32)
      expect(key_id1).not_to eq(key_id2)
    end

    it 'produces different ciphertext each time' do
      ct1 = described_class.encrypt(message, sender, recipient.public_key)
      ct2 = described_class.encrypt(message, sender, recipient.public_key)
      expect(ct1).not_to eq(ct2)
    end

    it 'round-trips an empty message' do
      ct = described_class.encrypt('', sender, recipient.public_key)
      expect(described_class.decrypt(ct, recipient)).to eq(''.b)
    end

    it 'round-trips a long message' do
      long_msg = SecureRandom.random_bytes(10_000)
      ct = described_class.encrypt(long_msg, sender, recipient.public_key)
      expect(described_class.decrypt(ct, recipient)).to eq(long_msg)
    end

    it 'round-trips UTF-8 text' do
      utf8_msg = 'üñîçø∂é'
      ct = described_class.encrypt(utf8_msg, sender, recipient.public_key)
      expect(described_class.decrypt(ct, recipient)).to eq(utf8_msg.b)
    end
  end

  describe '.decrypt error handling' do
    it 'raises on version mismatch' do
      ct = described_class.encrypt(message, sender, recipient.public_key)
      tampered = "\x00\x00\x00\x00".b + ct.byteslice(4, ct.bytesize - 4)
      expect { described_class.decrypt(tampered, recipient) }
        .to raise_error(ArgumentError, /version mismatch/)
    end

    it 'raises on truncated message' do
      expect { described_class.decrypt("\x42\x42\x10\x33".b, recipient) }
        .to raise_error(ArgumentError, /too short/)
    end

    it 'raises on wrong recipient' do
      ct = described_class.encrypt(message, sender, recipient.public_key)
      wrong = BSV::Primitives::PrivateKey.generate
      expect { described_class.decrypt(ct, wrong) }
        .to raise_error(ArgumentError, /recipient public key/)
    end

    it 'raises on tampered ciphertext' do
      ct = described_class.encrypt(message, sender, recipient.public_key)
      tampered = ct.dup
      tampered.setbyte(110, tampered.getbyte(110) ^ 0xFF)
      expect { described_class.decrypt(tampered, recipient) }
        .to raise_error(OpenSSL::Cipher::CipherError)
    end

    it 'raises on tampered auth tag' do
      ct = described_class.encrypt(message, sender, recipient.public_key)
      tampered = ct.dup
      tampered.setbyte(-1, tampered.getbyte(-1) ^ 0xFF)
      expect { described_class.decrypt(tampered, recipient) }
        .to raise_error(OpenSSL::Cipher::CipherError)
    end
  end

  describe 'bidirectional communication' do
    it 'allows recipient to reply to sender' do
      reply = 'reply message'
      ct = described_class.encrypt(reply, recipient, sender.public_key)
      expect(described_class.decrypt(ct, sender)).to eq(reply.b)
    end
  end

  describe 'different key pairs' do
    it 'works with generated keys' do
      alice = BSV::Primitives::PrivateKey.generate
      bob = BSV::Primitives::PrivateKey.generate
      ct = described_class.encrypt('secret', alice, bob.public_key)
      expect(described_class.decrypt(ct, bob)).to eq('secret'.b)
    end

    it 'different senders produce different ciphertexts' do
      other_sender = BSV::Primitives::PrivateKey.generate
      ct1 = described_class.encrypt(message, sender, recipient.public_key)
      ct2 = described_class.encrypt(message, other_sender, recipient.public_key)
      # Different sender keys in header
      expect(ct1.byteslice(4, 33)).not_to eq(ct2.byteslice(4, 33))
    end
  end
end
