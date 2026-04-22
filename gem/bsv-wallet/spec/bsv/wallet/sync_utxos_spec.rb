# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::Client do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:storage) { BSV::Wallet::Store::Memory.new }
  let(:chain_data_source) { double('chain_data_source') } # rubocop:disable RSpec/VerifiedDoubles

  def make_utxo(tx_hash, tx_pos, satoshis)
    BSV::Network::UTXO.new(tx_hash: tx_hash, tx_pos: tx_pos, satoshis: satoshis)
  end

  def make_tx(output_count: 1, satoshis: 1000)
    tx = BSV::Transaction::Transaction.new
    output_count.times do
      locking_script = BSV::Script::Script.p2pkh_lock(private_key.public_key.hash160)
      tx.add_output(BSV::Transaction::TransactionOutput.new(satoshis: satoshis, locking_script: locking_script))
    end
    tx
  end

  describe '#sync_utxos' do
    context 'when neither substrate nor chain_data_source is configured' do
      subject(:client) { described_class.new(private_key, storage: storage, allow_memory_store: true) }

      it 'raises UnsupportedActionError' do
        expect { client.sync_utxos }.to raise_error(BSV::Wallet::UnsupportedActionError)
      end

      it 'includes a helpful message' do
        expect { client.sync_utxos }
          .to raise_error(BSV::Wallet::UnsupportedActionError, /chain_data_source or remote substrate/)
      end
    end

    context 'with chain_data_source and no chain UTXOs' do
      subject(:client) do
        described_class.new(
          private_key,
          storage: storage,
          chain_data_source: chain_data_source,
          allow_memory_store: true
        )
      end

      before do
        allow(chain_data_source).to receive(:fetch_utxos).and_return([])
        allow(chain_data_source).to receive(:fetch_transaction)
      end

      it 'returns 0' do
        expect(client.sync_utxos).to eq(0)
      end

      it 'does not call fetch_transaction' do
        client.sync_utxos

        expect(chain_data_source).not_to have_received(:fetch_transaction)
      end
    end

    context 'with chain_data_source and UTXOs not yet in storage' do
      subject(:client) do
        described_class.new(
          private_key,
          storage: storage,
          chain_data_source: chain_data_source,
          allow_memory_store: true
        )
      end

      let(:tx_a) { make_tx(satoshis: 1000) }
      let(:tx_b) { make_tx(satoshis: 2000) }

      before do
        allow(chain_data_source).to receive(:fetch_utxos).and_return([
                                                                       make_utxo('aaa', 0, 1000),
                                                                       make_utxo('bbb', 0, 2000)
                                                                     ])
        allow(chain_data_source).to receive(:fetch_transaction).with('aaa').and_return(tx_a)
        allow(chain_data_source).to receive(:fetch_transaction).with('bbb').and_return(tx_b)
      end

      it 'returns the number of UTXOs imported' do
        expect(client.sync_utxos).to eq(2)
      end

      it 'stores each output with derivation_type :identity' do
        client.sync_utxos

        types = storage.find_outputs({ include_spent: false }).map { |o| o[:derivation_type].to_s }
        expect(types).to all(eq('identity'))
      end

      it 'stores each output with state :spendable' do
        client.sync_utxos

        states = storage.find_outputs({ include_spent: false }).map { |o| o[:state].to_s }
        expect(states).to all(eq('spendable'))
      end

      it 'stores each output with basket default' do
        client.sync_utxos

        baskets = storage.find_outputs({ include_spent: false }).map { |o| o[:basket] }
        expect(baskets).to all(eq('default'))
      end

      it 'stores the correct satoshis' do
        client.sync_utxos

        satoshis = storage.find_outputs({ include_spent: false }).map { |o| o[:satoshis] }.sort
        expect(satoshis).to eq([1000, 2000])
      end

      it 'stores the raw transactions' do
        client.sync_utxos

        expect(storage.find_transaction('aaa')).to eq(tx_a.to_hex)
        expect(storage.find_transaction('bbb')).to eq(tx_b.to_hex)
      end
    end

    context 'with chain_data_source, idempotent when all UTXOs already stored' do
      subject(:client) do
        described_class.new(
          private_key,
          storage: storage,
          chain_data_source: chain_data_source,
          allow_memory_store: true
        )
      end

      before do
        tx_a = make_tx(satoshis: 1000)
        tx_b = make_tx(satoshis: 2000)
        allow(chain_data_source).to receive(:fetch_utxos).and_return([
                                                                       make_utxo('aaa', 0, 1000),
                                                                       make_utxo('bbb', 0, 2000)
                                                                     ])
        allow(chain_data_source).to receive(:fetch_transaction).with('aaa').and_return(tx_a)
        allow(chain_data_source).to receive(:fetch_transaction).with('bbb').and_return(tx_b)
      end

      it 'returns 2 on first import, 0 on second' do
        expect(client.sync_utxos).to eq(2)
        expect(client.sync_utxos).to eq(0)
      end

      it 'partially imports new UTXOs while skipping known ones' do
        # Import aaa and bbb
        client.sync_utxos

        # Chain now also has ccc
        tx_c = make_tx(satoshis: 3000)
        allow(chain_data_source).to receive(:fetch_utxos).and_return([
                                                                       make_utxo('aaa', 0, 1000),
                                                                       make_utxo('bbb', 0, 2000),
                                                                       make_utxo('ccc', 0, 3000)
                                                                     ])
        allow(chain_data_source).to receive(:fetch_transaction).with('ccc').and_return(tx_c)

        expect(client.sync_utxos).to eq(1)
      end
    end

    context 'with chain_data_source and out-of-bounds tx_pos' do
      subject(:client) do
        described_class.new(
          private_key,
          storage: storage,
          chain_data_source: chain_data_source,
          allow_memory_store: true
        )
      end

      it 'raises WalletError when tx_pos exceeds output count' do
        tx = make_tx(output_count: 1)
        allow(chain_data_source).to receive(:fetch_utxos).and_return([make_utxo('aaa', 5, 1000)])
        allow(chain_data_source).to receive(:fetch_transaction).with('aaa').and_return(tx)

        expect { client.sync_utxos }.to raise_error(BSV::Wallet::WalletError, /Invalid tx_pos/)
      end

      it 'raises WalletError when tx_pos is negative' do
        tx = make_tx(output_count: 2)
        allow(chain_data_source).to receive(:fetch_utxos).and_return([make_utxo('aaa', -1, 1000)])
        allow(chain_data_source).to receive(:fetch_transaction).with('aaa').and_return(tx)

        expect { client.sync_utxos }.to raise_error(BSV::Wallet::WalletError, /Invalid tx_pos/)
      end

      it 'accepts tx_pos 0 (first output)' do
        tx = make_tx(output_count: 2)
        allow(chain_data_source).to receive(:fetch_utxos).and_return([make_utxo('aaa', 0, 1000)])
        allow(chain_data_source).to receive(:fetch_transaction).with('aaa').and_return(tx)

        expect(client.sync_utxos).to eq(1)
      end
    end

    context 'with chain_data_source and satoshis mismatch' do
      subject(:client) do
        described_class.new(
          private_key,
          storage: storage,
          chain_data_source: chain_data_source,
          allow_memory_store: true
        )
      end

      it 'raises WalletError when UTXO API value differs from transaction output' do
        tx = make_tx(output_count: 1, satoshis: 1000)
        # UTXO API reports 9999 but the actual output has 1000
        allow(chain_data_source).to receive(:fetch_utxos).and_return([make_utxo('aaa', 0, 9999)])
        allow(chain_data_source).to receive(:fetch_transaction).with('aaa').and_return(tx)

        expect { client.sync_utxos }.to raise_error(BSV::Wallet::WalletError, /UTXO value mismatch/)
      end

      it 'accepts when UTXO API value matches transaction output' do
        tx = make_tx(output_count: 1, satoshis: 5000)
        allow(chain_data_source).to receive(:fetch_utxos).and_return([make_utxo('aaa', 0, 5000)])
        allow(chain_data_source).to receive(:fetch_transaction).with('aaa').and_return(tx)

        expect(client.sync_utxos).to eq(1)
      end
    end

    context 'with chain_data_source and network errors' do
      subject(:client) do
        described_class.new(
          private_key,
          storage: storage,
          chain_data_source: chain_data_source,
          allow_memory_store: true
        )
      end

      it 'propagates errors from fetch_utxos' do
        allow(chain_data_source).to receive(:fetch_utxos).and_raise(StandardError, 'network error')

        expect { client.sync_utxos }.to raise_error(StandardError, 'network error')
      end

      it 'propagates errors from fetch_transaction' do
        allow(chain_data_source).to receive(:fetch_utxos).and_return([make_utxo('aaa', 0, 1000)])
        allow(chain_data_source).to receive(:fetch_transaction).and_raise(StandardError, 'network error')

        expect { client.sync_utxos }.to raise_error(StandardError, 'network error')
      end
    end

    context 'when substrate is configured (takes priority)' do
      subject(:client) do
        described_class.new(
          private_key,
          storage: storage,
          substrate: substrate,
          chain_data_source: chain_data_source,
          allow_memory_store: true
        )
      end

      let(:substrate) { double('substrate') } # rubocop:disable RSpec/VerifiedDoubles

      it 'delegates to the substrate and returns its result' do
        allow(substrate).to receive(:sync_utxos).and_return(3)

        expect(client.sync_utxos).to eq(3)
      end

      it 'does not call chain_data_source when substrate is set' do
        allow(substrate).to receive(:sync_utxos).and_return(0)
        allow(chain_data_source).to receive(:fetch_utxos)

        client.sync_utxos

        expect(chain_data_source).not_to have_received(:fetch_utxos)
      end
    end
  end
end
