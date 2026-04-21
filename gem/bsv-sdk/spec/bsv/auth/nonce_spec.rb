# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Auth::Nonce do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:wallet) { BSV::Wallet::Client.new(private_key, storage: BSV::Wallet::Store::Memory.new, allow_memory_store: true) }

  describe '.create' do
    subject(:nonce) { described_class.create(wallet) }

    it 'returns a non-empty string' do
      expect(nonce).to be_a(String)
      expect(nonce).not_to be_empty
    end

    it 'returns a valid base64-encoded string' do
      expect { Base64.strict_decode64(nonce) }.not_to raise_error
    end

    it 'decodes to 48 bytes (16 random + 32 HMAC)' do
      decoded = Base64.strict_decode64(nonce)
      expect(decoded.bytesize).to eq(48)
    end

    it 'produces a unique nonce on each call' do
      nonce2 = described_class.create(wallet)
      expect(nonce).not_to eq(nonce2)
    end

    it 'uses counterparty "self" by default' do
      expect { nonce }.not_to raise_error
    end
  end

  describe '.verify' do
    let(:nonce) { described_class.create(wallet) }

    it 'returns true for a valid nonce from the same wallet' do
      expect(described_class.verify(nonce, wallet)).to be(true)
    end

    it 'returns false when the HMAC suffix is tampered' do
      decoded = Base64.strict_decode64(nonce)
      tampered_bytes = decoded.dup.bytes
      tampered_bytes[-1] ^= 0xFF
      tampered_nonce = Base64.strict_encode64(tampered_bytes.pack('C*'))
      expect(described_class.verify(tampered_nonce, wallet)).to be(false)
    end

    it 'returns false when the random prefix is altered' do
      decoded = Base64.strict_decode64(nonce)
      tampered_bytes = decoded.dup.bytes
      tampered_bytes[0] ^= 0xFF
      tampered_nonce = Base64.strict_encode64(tampered_bytes.pack('C*'))
      expect(described_class.verify(tampered_nonce, wallet)).to be(false)
    end

    it 'returns false when verified against a different wallet' do
      other_key    = BSV::Primitives::PrivateKey.generate
      other_wallet = BSV::Wallet::Client.new(other_key, storage: BSV::Wallet::Store::Memory.new, allow_memory_store: true)
      expect(described_class.verify(nonce, other_wallet)).to be(false)
    end

    it 'returns false for a nonce that is too short' do
      short_nonce = Base64.strict_encode64('tooshort')
      expect(described_class.verify(short_nonce, wallet)).to be(false)
    end
  end
end
