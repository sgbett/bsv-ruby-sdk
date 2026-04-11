# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Primitives::SignedMessage do
  let(:sender) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(15)) }
  let(:recipient) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(21)) }
  let(:message) { [1, 2, 4, 8, 16, 32].pack('C*') }

  describe '.sign / .verify (specific recipient)' do
    it 'round-trips sign and verify' do
      sig = described_class.sign(message, sender, recipient.public_key)
      expect(described_class.verify(message, sig, recipient)).to be true
    end

    it 'produces binary output with correct header' do
      sig = described_class.sign(message, sender, recipient.public_key)
      # VERSION(4) + sender_pub(33) + recipient_pub(33) + key_id(32) + DER sig (variable)
      expect(sig.bytesize).to be >= 102
      expect(sig.byteslice(0, 4)).to eq("\x42\x42\x33\x01".b)
    end

    it 'includes sender public key in wire format' do
      sig = described_class.sign(message, sender, recipient.public_key)
      sender_pub_bytes = sig.byteslice(4, 33)
      expect(sender_pub_bytes).to eq(sender.public_key.compressed)
    end

    it 'includes recipient public key in wire format' do
      sig = described_class.sign(message, sender, recipient.public_key)
      recipient_pub_bytes = sig.byteslice(37, 33)
      expect(recipient_pub_bytes).to eq(recipient.public_key.compressed)
    end

    it 'produces unique key IDs each time' do
      sig1 = described_class.sign(message, sender, recipient.public_key)
      sig2 = described_class.sign(message, sender, recipient.public_key)
      key_id1 = sig1.byteslice(70, 32)
      key_id2 = sig2.byteslice(70, 32)
      expect(key_id1).not_to eq(key_id2)
    end

    it 'fails with tampered message' do
      sig = described_class.sign(message, sender, recipient.public_key)
      expect(described_class.verify('tampered'.b, sig, recipient)).to be false
    end

    it 'fails with wrong recipient' do
      sig = described_class.sign(message, sender, recipient.public_key)
      wrong = BSV::Primitives::PrivateKey.generate
      expect { described_class.verify(message, sig, wrong) }
        .to raise_error(ArgumentError, /recipient public key/)
    end

    it 'raises when recipient is required but not provided' do
      sig = described_class.sign(message, sender, recipient.public_key)
      expect { described_class.verify(message, sig) }
        .to raise_error(ArgumentError, /specific private key/)
    end
  end

  describe '.sign / .verify (anyone-can-verify)' do
    it 'round-trips sign and verify without recipient' do
      sig = described_class.sign(message, sender)
      expect(described_class.verify(message, sig)).to be true
    end

    it 'uses 0x00 marker for anyone mode' do
      sig = described_class.sign(message, sender)
      expect(sig.getbyte(37)).to eq(0)
    end

    it 'has shorter wire format than specific-recipient' do
      sig_anyone = described_class.sign(message, sender)
      sig_specific = described_class.sign(message, sender, recipient.public_key)
      # Anyone: VERSION(4) + sender(33) + 0x00(1) + key_id(32) + sig
      # Specific: VERSION(4) + sender(33) + recipient(33) + key_id(32) + sig
      expect(sig_anyone.bytesize).to be < sig_specific.bytesize
    end

    it 'anyone signature is verifiable even with a recipient param' do
      sig = described_class.sign(message, sender)
      # Passing a recipient should still work — anyone-can-verify ignores it
      expect(described_class.verify(message, sig, recipient)).to be true
    end

    it 'fails with tampered message' do
      sig = described_class.sign(message, sender)
      expect(described_class.verify('tampered'.b, sig)).to be false
    end
  end

  describe 'error handling' do
    it 'raises on version mismatch' do
      sig = described_class.sign(message, sender)
      tampered = "\x00\x00\x00\x00".b + sig.byteslice(4, sig.bytesize - 4)
      expect { described_class.verify(message, tampered) }
        .to raise_error(ArgumentError, /version mismatch/)
    end

    it 'raises on truncated signature' do
      expect { described_class.verify(message, "\x42\x42\x33\x01".b) }
        .to raise_error(ArgumentError, /too short/)
    end
  end

  describe 'different messages produce different signatures' do
    it 'signs different messages with different results' do
      sig1 = described_class.sign('hello', sender, recipient.public_key)
      sig2 = described_class.sign('world', sender, recipient.public_key)
      expect(sig1).not_to eq(sig2)
    end
  end

  describe 'different senders produce verifiable signatures' do
    it 'verifies with the correct sender identity' do
      other_sender = BSV::Primitives::PrivateKey.generate
      sig = described_class.sign(message, other_sender, recipient.public_key)
      expect(described_class.verify(message, sig, recipient)).to be true
    end
  end
end
