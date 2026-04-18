# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::LegacyChainProviderAdapter do
  subject(:adapter) { described_class.new(chain_provider) }

  let(:chain_provider) { double('chain_provider') } # rubocop:disable RSpec/VerifiedDoubles

  describe 'capabilities' do
    it 'provides :get_utxos, :get_tx, :current_height' do
      expect(described_class.capabilities).to include(:get_utxos, :get_tx, :current_height)
    end

    it 'is a BSV::Network::Provider subclass' do
      expect(described_class.ancestors).to include(BSV::Network::Provider)
    end
  end

  describe '#call(:get_utxos, address)' do
    context 'when the chain provider succeeds' do
      let(:utxos) { [{ tx_hash: 'abc', tx_pos: 0, value: 1000 }] }

      before { allow(chain_provider).to receive(:get_utxos).with('1address').and_return(utxos) }

      it 'returns Result::Success wrapping the utxo list' do
        result = adapter.call(:get_utxos, '1address')
        expect(result).to be_a(BSV::Network::Result::Success)
        expect(result.data).to eq(utxos)
      end
    end

    context 'when the chain provider raises' do
      before { allow(chain_provider).to receive(:get_utxos).and_raise(RuntimeError, 'network timeout') }

      it 'returns Result::Error with the exception message' do
        result = adapter.call(:get_utxos, '1address')
        expect(result).to be_a(BSV::Network::Result::Error)
        expect(result.message).to eq('network timeout')
        expect(result.retryable?).to be(false)
      end
    end
  end

  describe '#call(:get_tx, txid)' do
    context 'when the chain provider succeeds' do
      before { allow(chain_provider).to receive(:get_transaction).with('deadbeef').and_return('rawhex') }

      it 'returns Result::Success wrapping the raw hex' do
        result = adapter.call(:get_tx, 'deadbeef')
        expect(result).to be_a(BSV::Network::Result::Success)
        expect(result.data).to eq('rawhex')
      end
    end

    context 'when the chain provider raises' do
      before { allow(chain_provider).to receive(:get_transaction).and_raise(StandardError, 'not found') }

      it 'returns Result::Error' do
        result = adapter.call(:get_tx, 'deadbeef')
        expect(result).to be_a(BSV::Network::Result::Error)
        expect(result.message).to eq('not found')
      end
    end
  end

  describe '#call(:current_height)' do
    context 'when the chain provider succeeds' do
      before { allow(chain_provider).to receive(:get_height).and_return(850_000) }

      it 'returns Result::Success wrapping the height integer' do
        result = adapter.call(:current_height)
        expect(result).to be_a(BSV::Network::Result::Success)
        expect(result.data).to eq(850_000)
      end
    end

    context 'when the chain provider raises' do
      before { allow(chain_provider).to receive(:get_height).and_raise(RuntimeError, 'unavailable') }

      it 'returns Result::Error' do
        result = adapter.call(:current_height)
        expect(result).to be_a(BSV::Network::Result::Error)
        expect(result.message).to eq('unavailable')
      end
    end
  end

  describe 'registration in Registry' do
    it 'can be registered and dispatched through a Registry' do
      allow(chain_provider).to receive(:get_height).and_return(100)
      registry = BSV::Network::Registry.new
      registry.register(adapter)
      result = registry.call(:current_height)
      expect(result.success?).to be(true)
      expect(result.data).to eq(100)
    end
  end
end
