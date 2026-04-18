# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::RegistryBroadcaster do
  subject(:broadcaster) { described_class.new(registry) }

  let(:registry) { BSV::Network::Registry.new }
  let(:tx)       { BSV::Transaction::Transaction.new }

  describe '#broadcast(tx)' do
    context 'when the registry returns Result::Success with a hash' do
      let(:provider) do
        p = double('provider') # rubocop:disable RSpec/VerifiedDoubles
        allow(p).to receive(:class).and_return(Class.new(BSV::Network::Provider) { provides :broadcast })
        allow(p).to receive(:call).with(:broadcast, anything).and_return(
          BSV::Network::Result::Success.new(data: { txid: 'abc123', status: 'RECEIVED' })
        )
        p
      end

      before { registry.register(provider) }

      it 'returns a BroadcastResponse with the txid' do
        response = broadcaster.broadcast(tx)
        expect(response).to be_a(BSV::Network::BroadcastResponse)
        expect(response.txid).to eq('abc123')
      end
    end

    context 'when the registry returns Result::Success with a BroadcastResponse' do
      let(:broadcast_response) { BSV::Network::BroadcastResponse.new(txid: 'deadbeef', tx_status: 'MINED') }
      let(:provider) do
        p = double('provider') # rubocop:disable RSpec/VerifiedDoubles
        allow(p).to receive(:class).and_return(Class.new(BSV::Network::Provider) { provides :broadcast })
        allow(p).to receive(:call).with(:broadcast, anything).and_return(
          BSV::Network::Result::Success.new(data: broadcast_response)
        )
        p
      end

      before { registry.register(provider) }

      it 'passes the BroadcastResponse through unchanged' do
        response = broadcaster.broadcast(tx)
        expect(response).to be(broadcast_response)
      end
    end

    context 'when the registry returns Result::Error' do
      let(:provider) do
        p = double('provider') # rubocop:disable RSpec/VerifiedDoubles
        allow(p).to receive(:class).and_return(Class.new(BSV::Network::Provider) { provides :broadcast })
        allow(p).to receive(:call).with(:broadcast, anything).and_return(
          BSV::Network::Result::Error.new('transaction rejected', retryable: false)
        )
        p
      end

      before { registry.register(provider) }

      it 'raises BroadcastError with the result message' do
        expect { broadcaster.broadcast(tx) }.to raise_error(BSV::Network::BroadcastError, 'transaction rejected')
      end
    end

    context 'when no provider is registered for :broadcast' do
      it 'raises BroadcastError (not NoProviderError)' do
        expect { broadcaster.broadcast(tx) }.to raise_error(BSV::Network::BroadcastError)
      end
    end
  end
end
