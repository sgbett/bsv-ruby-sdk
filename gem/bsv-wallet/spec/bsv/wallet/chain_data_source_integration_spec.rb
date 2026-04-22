# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'json'

RSpec.describe 'WhatsOnChain as chain_data_source integration' do
  # -----------------------------------------------------------------------
  # Routing HTTP mock
  #
  # Responds to request(uri, req) and returns a Struct with #code and #body.
  # Routes are registered as URI substring => [code, body].
  # -----------------------------------------------------------------------
  let(:routing_http) do
    Class.new do
      def initialize
        @routes = {}
      end

      # Register a URI substring pattern → [code, body] pair.
      def stub(pattern, code, body)
        @routes[pattern] = [code.to_s, body.to_s]
      end

      def request(uri, _req)
        uri_str = uri.to_s
        found = @routes.find { |pattern, _| uri_str.include?(pattern) }
        code, body = found ? found.last : ['404', 'not found']
        Struct.new(:code, :body).new(code, body)
      end
    end.new
  end
  # -----------------------------------------------------------------------
  # Shared WoC response bodies
  # -----------------------------------------------------------------------

  let(:chain_info_body) { JSON.generate('blocks' => 850_000) }
  let(:block_header_body) do
    JSON.generate(
      'hash' => '000000000000000002a4dc25b9ea1a2c327a6a2e7e1c98f0f00b12b8be85f9b',
      'merkleroot' => 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
      'previousblockhash' => '000000000000000001234567890abcdef1234567890abcdef1234567890abcd',
      'time' => 1_700_000_000,
      'nonce' => 12_345_678,
      'bits' => '1a123456',
      'version' => 536_870_912,
      'height' => 850_000
    )
  end

  let(:private_key) { BSV::Primitives::PrivateKey.generate }

  # Derive the address the client uses for sync_utxos.
  let(:address) do
    private_key.public_key.address(network: :mainnet)
  end

  # Build a real transaction with one P2PKH output to the wallet's address.
  let(:sample_tx) do
    tx = BSV::Transaction::Transaction.new
    tx.add_output(
      BSV::Transaction::TransactionOutput.new(
        satoshis: 75_000,
        locking_script: BSV::Script::Script.p2pkh_lock(private_key.public_key.hash160)
      )
    )
    tx
  end

  let(:sample_txid) { sample_tx.txid_hex }
  let(:sample_tx_hex) { sample_tx.to_hex }

  # Second transaction for idempotency and multi-UTXO tests.
  let(:sample_tx2) do
    tx = BSV::Transaction::Transaction.new
    tx.add_output(
      BSV::Transaction::TransactionOutput.new(
        satoshis: 30_000,
        locking_script: BSV::Script::Script.p2pkh_lock(private_key.public_key.hash160)
      )
    )
    tx
  end

  let(:sample_tx2id) { sample_tx2.txid_hex }
  let(:sample_tx2_hex) { sample_tx2.to_hex }

  # -----------------------------------------------------------------------
  # Helpers
  # -----------------------------------------------------------------------

  def make_woc(http)
    BSV::Network::WhatsOnChain.new(http_client: http)
  end

  def make_client(woc, storage = nil)
    storage ||= BSV::Wallet::Store::Memory.new
    BSV::Wallet::Client.new(
      private_key,
      storage: storage,
      chain_data_source: woc,
      allow_memory_store: true
    )
  end

  def utxo_body_for(*txids_and_positions)
    entries = txids_and_positions.map do |(txid, pos, satoshis)|
      { 'tx_hash' => txid, 'tx_pos' => pos, 'value' => satoshis, 'height' => 800_000 }
    end
    JSON.generate(entries)
  end

  # -----------------------------------------------------------------------
  # 1. get_height integration
  # -----------------------------------------------------------------------

  describe 'get_height end-to-end' do
    it 'returns height from stubbed WoC /chain/info response' do
      routing_http.stub('/chain/info', 200, chain_info_body)
      client = make_client(make_woc(routing_http))

      expect(client.get_height).to eq({ height: 850_000 })
    end

    it 'propagates ChainProviderError when WoC returns 500' do
      routing_http.stub('/chain/info', 500, 'Internal Server Error')
      client = make_client(make_woc(routing_http))

      expect { client.get_height }.to raise_error(BSV::Network::ChainProviderError)
    end
  end

  # -----------------------------------------------------------------------
  # 2. get_header_for_height integration
  # -----------------------------------------------------------------------

  describe 'get_header_for_height end-to-end' do
    it 'returns header data from stubbed WoC block header response' do
      routing_http.stub('/block/', 200, block_header_body)
      client = make_client(make_woc(routing_http))

      result = client.get_header_for_height({ height: 850_000 })
      expect(result).to have_key(:header)
      expect(result[:header]).to include('merkleroot')
      expect(result[:header]['height']).to eq(850_000)
    end

    it 'returns a hash keyed with :header' do
      routing_http.stub('/block/', 200, block_header_body)
      client = make_client(make_woc(routing_http))

      result = client.get_header_for_height({ height: 850_000 })
      expect(result).to be_a(Hash)
      expect(result.keys).to eq([:header])
    end

    it 'propagates ChainProviderError when WoC returns 404 for block header' do
      routing_http.stub('/block/', 404, 'Block not found')
      client = make_client(make_woc(routing_http))

      expect { client.get_header_for_height({ height: 9_999_999 }) }
        .to raise_error(BSV::Network::ChainProviderError)
    end
  end

  # -----------------------------------------------------------------------
  # 3. sync_utxos happy path — imports UTXOs into storage
  # -----------------------------------------------------------------------

  describe 'sync_utxos end-to-end — happy path' do
    before do
      routing_http.stub('/unspent', 200, utxo_body_for([sample_txid, 0, 75_000],
                                                       [sample_tx2id, 0, 30_000]))
      routing_http.stub(sample_txid, 200, sample_tx_hex)
      routing_http.stub(sample_tx2id, 200, sample_tx2_hex)
    end

    it 'imports 2 UTXOs and returns 2' do
      client = make_client(make_woc(routing_http))

      expect(client.sync_utxos).to eq(2)
    end

    it 'stores outputs with correct satoshis' do
      storage = BSV::Wallet::Store::Memory.new
      client = make_client(make_woc(routing_http), storage)
      client.sync_utxos

      satoshis = storage.find_outputs({ include_spent: false }).map { |o| o[:satoshis] }.sort
      expect(satoshis).to eq([30_000, 75_000])
    end

    it 'stores outputs in the default basket' do
      storage = BSV::Wallet::Store::Memory.new
      client = make_client(make_woc(routing_http), storage)
      client.sync_utxos

      baskets = storage.find_outputs({ include_spent: false }).map { |o| o[:basket] }
      expect(baskets).to all(eq('default'))
    end

    it 'stores outputs with state :spendable' do
      storage = BSV::Wallet::Store::Memory.new
      client = make_client(make_woc(routing_http), storage)
      client.sync_utxos

      states = storage.find_outputs({ include_spent: false }).map { |o| o[:state].to_s }
      expect(states).to all(eq('spendable'))
    end

    it 'stores outputs with derivation_type :identity' do
      storage = BSV::Wallet::Store::Memory.new
      client = make_client(make_woc(routing_http), storage)
      client.sync_utxos

      types = storage.find_outputs({ include_spent: false }).map { |o| o[:derivation_type].to_s }
      expect(types).to all(eq('identity'))
    end

    it 'stores raw transaction hex for each imported transaction' do
      storage = BSV::Wallet::Store::Memory.new
      client = make_client(make_woc(routing_http), storage)
      client.sync_utxos

      expect(storage.find_transaction(sample_txid)).to eq(sample_tx_hex)
      expect(storage.find_transaction(sample_tx2id)).to eq(sample_tx2_hex)
    end
  end

  # -----------------------------------------------------------------------
  # 4. sync_utxos idempotency — second call returns 0
  # -----------------------------------------------------------------------

  describe 'sync_utxos idempotency' do
    before do
      routing_http.stub('/unspent', 200, utxo_body_for([sample_txid, 0, 75_000]))
      routing_http.stub(sample_txid, 200, sample_tx_hex)
    end

    it 'returns 1 on first call and 0 on second' do
      client = make_client(make_woc(routing_http))

      expect(client.sync_utxos).to eq(1)
      expect(client.sync_utxos).to eq(0)
    end
  end

  # -----------------------------------------------------------------------
  # 5. sync_utxos with no UTXOs
  # -----------------------------------------------------------------------

  describe 'sync_utxos with no UTXOs on chain' do
    it 'returns 0 and makes no fetch_transaction calls' do
      routing_http.stub('/unspent', 200, '[]')
      client = make_client(make_woc(routing_http))

      expect(client.sync_utxos).to eq(0)
    end
  end

  # -----------------------------------------------------------------------
  # 6. Error cases — no chain_data_source
  # -----------------------------------------------------------------------

  describe 'error cases — no chain_data_source configured' do
    subject(:client) do
      BSV::Wallet::Client.new(
        private_key,
        storage: BSV::Wallet::Store::Memory.new,
        allow_memory_store: true
      )
    end

    it 'raises UnsupportedActionError for get_height' do
      expect { client.get_height }.to raise_error(BSV::Wallet::UnsupportedActionError)
    end

    it 'raises UnsupportedActionError for get_header_for_height' do
      expect { client.get_header_for_height({ height: 100 }) }
        .to raise_error(BSV::Wallet::UnsupportedActionError)
    end

    it 'raises UnsupportedActionError for sync_utxos' do
      expect { client.sync_utxos }.to raise_error(BSV::Wallet::UnsupportedActionError)
    end
  end

  # -----------------------------------------------------------------------
  # 7. Network error propagation — WoC returns 500
  # -----------------------------------------------------------------------

  describe 'sync_utxos network error propagation' do
    it 'propagates ChainProviderError when UTXO fetch returns 500' do
      routing_http.stub('/unspent', 500, 'Internal Server Error')
      client = make_client(make_woc(routing_http))

      expect { client.sync_utxos }.to raise_error(BSV::Network::ChainProviderError)
    end

    it 'propagates ChainProviderError when transaction fetch returns 500' do
      routing_http.stub('/unspent', 200, utxo_body_for([sample_txid, 0, 75_000]))
      routing_http.stub('/tx/', 500, 'Internal Server Error')
      client = make_client(make_woc(routing_http))

      expect { client.sync_utxos }.to raise_error(BSV::Network::ChainProviderError)
    end
  end
end
