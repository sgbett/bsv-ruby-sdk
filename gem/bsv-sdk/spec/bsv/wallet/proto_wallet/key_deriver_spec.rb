# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Wallet::ProtoWallet::KeyDeriver do
  subject(:deriver) { described_class.new(private_key) }

  let(:private_key) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(42)) }

  describe '#identity_key' do
    it 'returns the 66-char compressed-pubkey hex' do
      expect(deriver.identity_key).to eq(private_key.public_key.to_hex)
      expect(deriver.identity_key).to match(/\A0[23][0-9a-fA-F]{64}\z/)
    end

    it 'memoises the hex form' do
      first  = deriver.identity_key
      second = deriver.identity_key
      expect(second).to equal(first)
    end
  end

  describe '#identity_key_bytes' do
    # Per ADR-001 pubkeys are hex-canonical, but a binary accessor
    # mirrors the bsv-wallet KeyDeriver shape for sites that consume
    # the bytes directly (e.g. hash160).
    it 'returns the 33-byte compressed-pubkey binary' do
      expect(deriver.identity_key_bytes).to eq(private_key.public_key.compressed)
      expect(deriver.identity_key_bytes.bytesize).to eq(33)
    end

    it 'is the binary form of #identity_key' do
      expect(deriver.identity_key_bytes.unpack1('H*')).to eq(deriver.identity_key)
    end

    it 'memoises the binary form' do
      first  = deriver.identity_key_bytes
      second = deriver.identity_key_bytes
      expect(second).to equal(first)
    end
  end
end
