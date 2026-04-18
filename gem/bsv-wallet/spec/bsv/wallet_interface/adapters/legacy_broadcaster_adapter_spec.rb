# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::LegacyBroadcasterAdapter do
  subject(:adapter) { described_class.new(broadcaster) }

  let(:broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles
  let(:tx)          { BSV::Transaction::Transaction.new }

  describe 'capabilities' do
    it 'provides :broadcast' do
      expect(described_class.capabilities).to include(:broadcast)
    end

    it 'is a BSV::Network::Provider subclass' do
      expect(described_class.ancestors).to include(BSV::Network::Provider)
    end
  end

  describe '#call(:broadcast, tx)' do
    context 'when the broadcaster succeeds' do
      let(:response) { BSV::Network::BroadcastResponse.new(txid: 'abc123', tx_status: 'RECEIVED') }

      before { allow(broadcaster).to receive(:broadcast).with(tx).and_return(response) }

      it 'returns Result::Success wrapping the BroadcastResponse' do
        result = adapter.call(:broadcast, tx)
        expect(result).to be_a(BSV::Network::Result::Success)
        expect(result.data).to eq(response)
      end
    end

    context 'when the broadcaster raises BroadcastError' do
      before do
        allow(broadcaster).to receive(:broadcast).and_raise(
          BSV::Network::BroadcastError.new('rejected by miner')
        )
      end

      it 'returns Result::Error with the error message' do
        result = adapter.call(:broadcast, tx)
        expect(result).to be_a(BSV::Network::Result::Error)
        expect(result.message).to eq('rejected by miner')
        expect(result.retryable?).to be(false)
      end
    end

    context 'when the broadcaster raises an unexpected error' do
      before { allow(broadcaster).to receive(:broadcast).and_raise(RuntimeError, 'connection refused') }

      it 'returns Result::Error with the exception message' do
        result = adapter.call(:broadcast, tx)
        expect(result).to be_a(BSV::Network::Result::Error)
        expect(result.message).to eq('connection refused')
        expect(result.retryable?).to be(false)
      end
    end
  end
end
