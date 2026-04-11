# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'json'

RSpec.describe BSV::Wallet::WhatsOnChainProvider do
  # Minimal HTTP client double that returns a configurable response.
  let(:mock_http) do
    Class.new do
      attr_reader :last_uri

      def initialize(responses = {})
        @responses = responses
      end

      def request(uri, _request)
        @last_uri = uri.to_s
        body = @responses[uri.path] || @responses[:default] || ''
        Struct.new(:code, :body).new('200', body)
      end
    end
  end

  let(:utxo_response) do
    [{ 'tx_hash' => 'abc123', 'tx_pos' => 0, 'value' => 5000, 'height' => 800_000 }].to_json
  end

  # A minimal raw transaction: version(4) + vin_count(1) + vout_count(1) +
  # one P2PKH output + locktime(4). We build a real transaction so the hex
  # is valid and parseable.
  let(:source_tx) do
    key = BSV::Primitives::PrivateKey.generate
    tx = BSV::Transaction::Transaction.new
    tx.add_output(
      BSV::Transaction::TransactionOutput.new(
        satoshis: 5000,
        locking_script: BSV::Script::Script.p2pkh_lock(key.public_key.hash160)
      )
    )
    tx
  end

  let(:tx_hex) { source_tx.to_hex }

  let(:http_with_utxos) do
    mock_http.new(
      '/v1/bsv/main/address/1TestAddress/unspent' => utxo_response
    )
  end

  let(:provider_with_utxos) do
    described_class.new(network: :main, http_client: http_with_utxos)
  end

  # -------------------------------------------------------------------------
  # #get_utxos
  # -------------------------------------------------------------------------
  describe '#get_utxos' do
    it 'returns an array of hashes with :tx_hash, :tx_pos, and :value' do
      result = provider_with_utxos.get_utxos('1TestAddress')

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first).to eq({ tx_hash: 'abc123', tx_pos: 0, value: 5000 })
    end

    it 'returns an empty array when the address has no UTXOs' do
      http = mock_http.new('/v1/bsv/main/address/1Empty/unspent' => '[]')
      provider = described_class.new(network: :main, http_client: http)

      expect(provider.get_utxos('1Empty')).to eq([])
    end

    it 'uses the test network path when network: :test' do
      http = mock_http.new(
        '/v1/bsv/test/address/mTestAddr/unspent' => utxo_response
      )
      provider = described_class.new(network: :test, http_client: http)
      result = provider.get_utxos('mTestAddr')

      expect(result.first[:tx_hash]).to eq('abc123')
      expect(http.last_uri).to include('/test/')
    end
  end

  # -------------------------------------------------------------------------
  # #get_transaction
  # -------------------------------------------------------------------------
  describe '#get_transaction' do
    it 'returns the raw transaction hex string' do
      http = mock_http.new("/v1/bsv/main/tx/#{source_tx.txid_hex}/hex" => tx_hex)
      provider = described_class.new(network: :main, http_client: http)

      result = provider.get_transaction(source_tx.txid_hex)

      expect(result).to be_a(String)
      expect(result).to eq(tx_hex)
    end
  end

  # -------------------------------------------------------------------------
  # #get_height and #get_header (not yet implemented)
  # -------------------------------------------------------------------------
  describe '#get_height' do
    it 'raises NotImplementedError' do
      provider = described_class.new
      expect { provider.get_height }.to raise_error(NotImplementedError)
    end
  end

  describe '#get_header' do
    it 'raises NotImplementedError' do
      provider = described_class.new
      expect { provider.get_header(800_000) }.to raise_error(NotImplementedError)
    end
  end
end

# -------------------------------------------------------------------------
# NullChainProvider — new methods
# -------------------------------------------------------------------------
RSpec.describe BSV::Wallet::NullChainProvider do
  let(:provider) { described_class.new }

  describe '#get_utxos' do
    it 'raises UnsupportedActionError' do
      expect { provider.get_utxos('1Address') }.to raise_error(BSV::Wallet::UnsupportedActionError)
    end
  end

  describe '#get_transaction' do
    it 'raises UnsupportedActionError' do
      expect { provider.get_transaction('deadbeef') }.to raise_error(BSV::Wallet::UnsupportedActionError)
    end
  end
end

# -------------------------------------------------------------------------
# WalletClient#sync_utxos
# -------------------------------------------------------------------------
RSpec.describe BSV::Wallet::WalletClient, '#sync_utxos' do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:storage) { BSV::Wallet::MemoryStore.new }

  # Build real source transactions with a P2PKH output to the wallet's
  # identity address so the locking script is consistent with chain data.
  let(:identity_address) { private_key.public_key.address(network: :mainnet) }

  # Provider whose get_utxos and get_transaction are controlled by stubs
  let(:chain_provider) { instance_double(BSV::Wallet::ChainProvider) }

  let(:tx_small)  { build_source_tx(1000) }
  let(:tx_medium) { build_source_tx(2000) }
  let(:tx_large)  { build_source_tx(3000) }

  let(:wallet) do
    described_class.new(
      private_key,
      storage: storage,
      chain_provider: chain_provider
    )
  end

  let(:three_utxo_response) do
    [
      { tx_hash: tx_small.txid_hex,  tx_pos: 0, value: 1000 },
      { tx_hash: tx_medium.txid_hex, tx_pos: 0, value: 2000 },
      { tx_hash: tx_large.txid_hex,  tx_pos: 0, value: 3000 }
    ]
  end

  def build_source_tx(satoshis)
    tx = BSV::Transaction::Transaction.new
    tx.add_output(
      BSV::Transaction::TransactionOutput.new(
        satoshis: satoshis,
        locking_script: BSV::Script::Script.p2pkh_lock(private_key.public_key.hash160)
      )
    )
    tx
  end

  before do
    allow(chain_provider).to receive(:get_utxos).with(identity_address).and_return(three_utxo_response)
    allow(chain_provider).to receive(:get_transaction).with(tx_small.txid_hex).and_return(tx_small.to_hex)
    allow(chain_provider).to receive(:get_transaction).with(tx_medium.txid_hex).and_return(tx_medium.to_hex)
    allow(chain_provider).to receive(:get_transaction).with(tx_large.txid_hex).and_return(tx_large.to_hex)
  end

  it 'imports all discovered UTXOs as :spendable in the default basket' do
    wallet.sync_utxos

    spendable = storage.find_spendable_outputs(basket: 'default')
    expect(spendable.length).to eq(3)
    expect(spendable.map { |o| o[:state] }.uniq).to eq([:spendable])
    expect(spendable.map { |o| o[:basket] }.uniq).to eq(['default'])
  end

  it 'returns the count of new UTXOs imported' do
    expect(wallet.sync_utxos).to eq(3)
  end

  it 'tags each imported output with derivation_type: :identity' do
    wallet.sync_utxos

    spendable = storage.find_spendable_outputs(basket: 'default')
    expect(spendable.map { |o| o[:derivation_type] }.uniq).to eq([:identity])
  end

  it 'is idempotent — calling twice produces no duplicates' do
    wallet.sync_utxos
    wallet.sync_utxos

    spendable = storage.find_spendable_outputs(basket: 'default')
    expect(spendable.length).to eq(3)
  end

  it 'returns 0 on the second call when no new UTXOs have appeared' do
    wallet.sync_utxos
    expect(wallet.sync_utxos).to eq(0)
  end

  context 'when the address has no UTXOs' do
    before do
      allow(chain_provider).to receive(:get_utxos).with(identity_address).and_return([])
    end

    it 'does not raise' do
      expect { wallet.sync_utxos }.not_to raise_error
    end

    it 'returns 0' do
      expect(wallet.sync_utxos).to eq(0)
    end
  end

  it 'stores the source transaction hex alongside each output' do
    wallet.sync_utxos

    spendable = storage.find_spendable_outputs(basket: 'default')
    expect(spendable.map { |o| o[:source_tx_hex] }).to contain_exactly(
      tx_small.to_hex, tx_medium.to_hex, tx_large.to_hex
    )
  end

  it 'stores the transaction in the transaction index' do
    wallet.sync_utxos

    expect(storage.find_transaction(tx_small.txid_hex)).to eq(tx_small.to_hex)
    expect(storage.find_transaction(tx_medium.txid_hex)).to eq(tx_medium.to_hex)
    expect(storage.find_transaction(tx_large.txid_hex)).to eq(tx_large.to_hex)
  end
end
