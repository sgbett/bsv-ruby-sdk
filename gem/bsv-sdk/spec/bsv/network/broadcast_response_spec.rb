# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::BroadcastResponse do
  describe '#initialize' do
    it 'accepts all ARC response fields' do
      response = described_class.new(
        txid: 'aa' * 32,
        tx_status: 'SEEN_ON_NETWORK',
        message: 'success',
        extra_info: 'info',
        block_hash: '000000',
        block_height: 100,
        timestamp: '2025-01-01T00:00:00Z',
        competing_txs: ['def456']
      )

      expect(response.txid).to eq('aa' * 32)
      expect(response.tx_status).to eq('SEEN_ON_NETWORK')
      expect(response.message).to eq('success')
      expect(response.extra_info).to eq('info')
      expect(response.block_hash).to eq('000000')
      expect(response.block_height).to eq(100)
      expect(response.timestamp).to eq('2025-01-01T00:00:00Z')
      expect(response.competing_txs).to eq(['def456'])
    end

    it 'defaults all fields to nil' do
      response = described_class.new

      expect(response.txid).to be_nil
      expect(response.tx_status).to be_nil
      expect(response.message).to be_nil
    end
  end

  describe '#success?' do
    it 'returns true' do
      expect(described_class.new.success?).to be true
    end
  end

  describe '#mined?' do
    it 'returns true when tx_status is MINED' do
      response = described_class.new(tx_status: 'MINED')
      expect(response.mined?).to be true
    end

    it 'returns false for other statuses' do
      response = described_class.new(tx_status: 'SEEN_ON_NETWORK')
      expect(response.mined?).to be false
    end

    it 'returns false when tx_status is nil' do
      expect(described_class.new.mined?).to be false
    end
  end
end
