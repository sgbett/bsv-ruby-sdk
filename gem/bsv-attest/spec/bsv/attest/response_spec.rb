# frozen_string_literal: true

require 'spec_helper'

require 'bsv-attest'

RSpec.describe BSV::Attest::Response do
  subject(:response) do
    described_class.new(hash: hash_bytes, txid: txid)
  end

  let(:hash_bytes) { BSV::Primitives::Digest.sha256('test data') }
  let(:txid) { 'aa' * 32 }

  it 'stores the hash' do
    expect(response.hash).to eq(hash_bytes)
  end

  it 'stores the txid' do
    expect(response.txid).to eq(txid)
  end

  it 'does not respond to transaction' do
    expect(response).not_to respond_to(:transaction)
  end

  describe '#hash_hex' do
    it 'returns a 64-character hex string' do
      hex = response.hash_hex
      expect(hex).to be_a(String)
      expect(hex.length).to eq(64)
      expect(hex).to match(/\A[0-9a-f]+\z/)
    end

    it 'matches the hex encoding of the binary hash' do
      expect(response.hash_hex).to eq(hash_bytes.unpack1('H*'))
    end
  end
end
