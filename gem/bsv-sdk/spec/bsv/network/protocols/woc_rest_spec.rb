# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::Protocols::WoCREST do # rubocop:disable RSpec/SpecFilePathFormat
  subject(:woc) { described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/{network}', network: :main, http_client: http) }

  # Minimal fake HTTP client — configurable per example or using the shared
  # queue-style helper below.
  let(:http) { FakeHttp.new(200, '{}') }

  # Simple fake HTTP client that returns a canned response.
  # Stores the last URI and request for assertion.
  let(:fake_http_class) do
    Class.new do
      attr_reader :last_uri, :last_request

      def initialize(code, body)
        @code = code.to_s
        @body = body
      end

      def request(uri, req)
        @last_uri     = uri
        @last_request = req
        Struct.new(:code, :body).new(@code, @body)
      end
    end
  end

  # Convenience helper — creates a FakeHttp instance with given code and body.
  def fake(code, body)
    fake_http_class.new(code, body)
  end

  # Use FakeHttp as a named alias for the anonymous class.
  before { stub_const('FakeHttp', fake_http_class) }

  # ---------------------------------------------------------------------------
  # Constructor / network resolution
  # ---------------------------------------------------------------------------

  describe '#initialize — network resolution' do
    let(:template_url) { 'https://api.whatsonchain.com/v1/bsv/{network}' }

    it 'resolves :main to "main" in the base URL' do
      protocol = described_class.new(base_url: template_url, network: :main, http_client: fake(200, ''))
      expect(protocol.base_url).to eq('https://api.whatsonchain.com/v1/bsv/main')
    end

    it 'resolves :mainnet to "main"' do
      protocol = described_class.new(base_url: template_url, network: :mainnet, http_client: fake(200, ''))
      expect(protocol.base_url).to include('/main')
    end

    it 'resolves :test to "test"' do
      protocol = described_class.new(base_url: template_url, network: :test, http_client: fake(200, ''))
      expect(protocol.base_url).to include('/test')
    end

    it 'resolves :testnet to "test"' do
      protocol = described_class.new(base_url: template_url, network: :testnet, http_client: fake(200, ''))
      expect(protocol.base_url).to include('/test')
    end

    it 'resolves :stn to "stn"' do
      protocol = described_class.new(base_url: template_url, network: :stn, http_client: fake(200, ''))
      expect(protocol.base_url).to include('/stn')
    end

    it 'resolves string "main"' do
      protocol = described_class.new(base_url: template_url, network: 'main', http_client: fake(200, ''))
      expect(protocol.base_url).to include('/main')
    end

    it 'exposes network_name' do
      protocol = described_class.new(base_url: template_url, network: :mainnet, http_client: fake(200, ''))
      expect(protocol.network_name).to eq('main')
    end

    it 'raises ArgumentError for an unknown network' do
      expect { described_class.new(base_url: template_url, network: :unknown) }
        .to raise_error(ArgumentError, /unknown network/)
    end
  end

  # ---------------------------------------------------------------------------
  # base_url override
  # ---------------------------------------------------------------------------

  describe '#initialize — base_url' do
    it 'raises ArgumentError when base_url: is omitted' do
      expect { described_class.new(network: :main, http_client: fake(200, '')) }
        .to raise_error(ArgumentError)
    end

    it 'uses a fully-qualified URL when base_url: is provided without {network}' do
      protocol = described_class.new(base_url: 'https://my.woc.example', network: :main, http_client: fake(200, ''))
      expect(protocol.base_url).to eq('https://my.woc.example')
    end

    it 'interpolates {network} in a URL template' do
      protocol = described_class.new(
        base_url: 'https://staging.woc.example/v2/bsv/{network}',
        network: :test,
        http_client: fake(200, '')
      )
      expect(protocol.base_url).to eq('https://staging.woc.example/v2/bsv/test')
    end
  end

  # ---------------------------------------------------------------------------
  # Declared commands
  # ---------------------------------------------------------------------------

  describe '.commands' do
    it 'declares all expected commands' do
      expected = %i[
        current_height get_chain_info get_block_header get_block_headers
        get_circulating_supply get_chain_tips get_peer_info
        get_tx get_tx_details get_output_script get_opreturn
        get_merkle_path broadcast decode_tx get_tx_status get_tx_hex_bulk
        get_tx_binary get_tx_by_block_index get_tx_propagation
        get_bulk_tx_details get_bulk_output_scripts
        get_utxos get_utxos_all is_utxo is_utxo_bulk valid_root
        get_unconfirmed_utxos get_confirmed_spent get_unconfirmed_spent
        get_bulk_address_utxos get_bulk_address_unconfirmed_utxos
        get_script_unspent get_script_history get_script_all_unspent get_script_unspent_bulk
        get_script_unconfirmed_unspent get_bulk_script_unconfirmed_unspent
        get_balance get_unconfirmed_balance get_history is_address_used
        get_exchange_rate get_fee_recommendation get_mempool_info
        get_exchange_rate_historical get_mempool_raw
        search_links
        get_block_stats get_block_stats_by_hash get_miner_block_stats
        get_miner_fees get_miner_summary get_block_tag_count
        health
      ]
      expected.each do |cmd|
        expect(described_class.commands).to include(cmd),
                                            "expected commands to include :#{cmd}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # current_height — lambda extracts blocks from chain info JSON
  # ---------------------------------------------------------------------------

  describe '#call(:current_height)' do
    it 'extracts the blocks field from chain info JSON' do
      body = '{"chain":"main","blocks":812345,"bestblockhash":"abcd"}'
      http_client = fake(200, body)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:current_height)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq(812_345)
    end

    it 'sends GET to /chain/info' do
      body = '{"blocks":800000}'
      http_client = fake(200, body)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:current_height)

      expect(http_client.last_uri.path).to end_with('/chain/info')
    end

    it 'returns Result::Error on 500' do
      http_client = fake(500, 'server error')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:current_height)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end

    it 'returns Result::Error on 429 (rate limited)' do
      http_client = fake(429, 'rate limited')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:current_height)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # get_block_header
  # ---------------------------------------------------------------------------

  describe '#call(:get_block_header)' do
    let(:header_json) do
      {
        'hash' => 'abc123',
        'height' => 800_000,
        'merkleroot' => 'deadbeef00000000' * 4
      }.to_json
    end

    it 'returns JSON header for a given height' do
      http_client = fake(200, header_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_block_header, 800_000)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['height']).to eq(800_000)
    end

    it 'sends GET to /block/{height}/header' do
      http_client = fake(200, header_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_block_header, 800_000)

      expect(http_client.last_uri.path).to end_with('/block/800000/header')
    end

    it 'returns Result::NotFound for an unknown height' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_block_header, 99_999_999)

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end
  end

  # ---------------------------------------------------------------------------
  # get_tx — returns raw hex
  # ---------------------------------------------------------------------------

  describe '#call(:get_tx)' do
    it 'returns raw hex body on success' do
      hex = "01000000#{'00' * 100}"
      http_client = fake(200, hex)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_tx, 'abc123' * 10)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq(hex)
    end

    it 'sends GET to /tx/{txid}/hex' do
      http_client = fake(200, '01000000')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)
      txid = 'a' * 64

      protocol.call(:get_tx, txid)

      expect(http_client.last_uri.path).to end_with("/tx/#{txid}/hex")
    end

    it 'returns Result::NotFound for unknown txid' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_tx, 'unknown_txid')

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end
  end

  # ---------------------------------------------------------------------------
  # get_merkle_path
  # ---------------------------------------------------------------------------

  describe '#call(:get_merkle_path)' do
    let(:proof_json) do
      [{ 'index' => 3, 'txOrId' => 'abc123', 'target' => 'deadbeef', 'nodes' => %w[aaa bbb] }].to_json
    end

    it 'returns parsed JSON proof' do
      http_client = fake(200, proof_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_merkle_path, 'abc123')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_a(Array)
      expect(result.data.first['index']).to eq(3)
    end

    it 'sends GET to /tx/{txid}/proof/tsc' do
      http_client = fake(200, proof_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)
      txid = 'b' * 64

      protocol.call(:get_merkle_path, txid)

      expect(http_client.last_uri.path).to end_with("/tx/#{txid}/proof/tsc")
    end

    it 'returns Result::NotFound when proof does not exist' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_merkle_path, 'unconfirmed_txid')

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'internal error')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_merkle_path, 'abc')

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # get_utxos — value → satoshis remapping (escape hatch)
  # ---------------------------------------------------------------------------

  describe '#call(:get_utxos)' do
    let(:woc_response) do
      {
        'address' => '1AzDmXHX891VQovic5A7iqrW3AnikSf6tm',
        'script' => '2673c96e7c5ab126b5f99251882d74c84997a52df85ae6c8ddbd843a7d322ad1',
        'result' => [
          { 'tx_hash' => 'abc', 'tx_pos' => 0, 'value' => 50_000, 'height' => 800_000, 'isSpentInMempoolTx' => false },
          { 'tx_hash' => 'def', 'tx_pos' => 1, 'value' => 100_000, 'height' => 800_001, 'isSpentInMempoolTx' => false }
        ],
        'error' => ''
      }.to_json
    end

    it 'remaps value to satoshis in the result' do
      http_client = fake(200, woc_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_utxos, '1AddressBSV')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data[0][:satoshis]).to eq(50_000)
      expect(result.data[1][:satoshis]).to eq(100_000)
    end

    it 'does not include a value key in remapped entries' do
      http_client = fake(200, woc_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_utxos, '1AddressBSV')

      expect(result.data[0]).not_to have_key(:value)
      expect(result.data[0]).not_to have_key('value')
    end

    it 'preserves tx_hash, tx_pos, and height fields as symbol keys' do
      http_client = fake(200, woc_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_utxos, '1AddressBSV')

      entry = result.data[0]
      expect(entry[:tx_hash]).to eq('abc')
      expect(entry[:tx_pos]).to eq(0)
      expect(entry[:height]).to eq(800_000)
    end

    it 'returns an empty array when the address has no UTXOs' do
      empty_response = { 'address' => '1EmptyAddress', 'script' => 'deadbeef', 'result' => [], 'error' => '' }.to_json
      http_client = fake(200, empty_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_utxos, '1EmptyAddress')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq([])
    end

    it 'sends GET to the confirmed/unspent path' do
      empty_response = { 'address' => '1CheckPath', 'script' => 'deadbeef', 'result' => [], 'error' => '' }.to_json
      http_client = fake(200, empty_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_utxos, '1CheckPath')

      expect(http_client.last_uri.path).to end_with('/address/1CheckPath/confirmed/unspent')
    end

    it 'returns Result::NotFound on 404' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_utxos, '1UnknownAddress')

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'server error')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_utxos, '1Addr')

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # get_utxos_all — includes unconfirmed (escape hatch)
  # ---------------------------------------------------------------------------

  describe '#call(:get_utxos_all)' do
    let(:woc_response) do
      {
        'address' => '1AzDmXHX891VQovic5A7iqrW3AnikSf6tm',
        'script' => '2673c96e7c5ab126b5f99251882d74c84997a52df85ae6c8ddbd843a7d322ad1',
        'result' => [
          { 'tx_hash' => 'abc', 'tx_pos' => 0, 'value' => 50_000, 'height' => 800_000, 'isSpentInMempoolTx' => false, 'status' => 'confirmed' },
          { 'tx_hash' => 'def', 'tx_pos' => 1, 'value' => 100_000, 'height' => 0, 'isSpentInMempoolTx' => false, 'status' => 'unconfirmed' }
        ],
        'error' => ''
      }.to_json
    end

    it 'remaps value to satoshis in the result' do
      http_client = fake(200, woc_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_utxos_all, '1AddressBSV')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data[0][:satoshis]).to eq(50_000)
      expect(result.data[1][:satoshis]).to eq(100_000)
    end

    it 'does not include a value key in remapped entries' do
      http_client = fake(200, woc_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_utxos_all, '1AddressBSV')

      expect(result.data[0]).not_to have_key(:value)
      expect(result.data[0]).not_to have_key('value')
    end

    it 'preserves tx_hash, tx_pos, and height fields as symbol keys' do
      http_client = fake(200, woc_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_utxos_all, '1AddressBSV')

      entry = result.data[0]
      expect(entry[:tx_hash]).to eq('abc')
      expect(entry[:tx_pos]).to eq(0)
      expect(entry[:height]).to eq(800_000)
    end

    it 'returns an empty array when the address has no UTXOs' do
      empty_response = { 'address' => '1EmptyAddress', 'script' => 'deadbeef', 'result' => [], 'error' => '' }.to_json
      http_client = fake(200, empty_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_utxos_all, '1EmptyAddress')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq([])
    end

    it 'sends GET to the unspent/all path' do
      empty_response = '{"address":"1CheckPath","script":"deadbeef","result":[],"error":""}'
      http_client = fake(200, empty_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_utxos_all, '1CheckPath')

      expect(http_client.last_uri.path).to end_with('/address/1CheckPath/unspent/all')
    end

    it 'returns Result::NotFound on 404' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_utxos_all, '1UnknownAddress')

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'server error')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_utxos_all, '1Addr')

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # is_utxo — spent status (escape hatch)
  # ---------------------------------------------------------------------------

  describe '#call(:is_utxo)' do
    # WoC API contract: 200 with spending tx details = spent, 404 = unspent
    let(:spent_response) do
      '{"txid":"4a97bc492e6604660654e53faabfc7ff615db7608a9fd3c7d74da0d9914e65e5","vin":1,"status":"confirmed"}'
    end

    it 'returns true when the output is unspent (404 from WoC)' do
      http_client = fake(404, 'Not Found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_utxo, 'abc123', 0)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be(true)
    end

    it 'returns false when the output is spent (200 with spending tx)' do
      http_client = fake(200, spent_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_utxo, 'abc123', 1)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be(false)
    end

    it 'sends GET to /tx/{txid}/{vout}/spent' do
      http_client = fake(200, spent_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)
      txid = 'c' * 64

      protocol.call(:is_utxo, txid, 2)

      expect(http_client.last_uri.path).to end_with("/tx/#{txid}/2/spent")
    end

    it 'accepts script_hash: keyword without error' do
      http_client = fake(404, 'Not Found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      expect { protocol.call(:is_utxo, 'abc', 0, script_hash: 'deadbeef') }.not_to raise_error
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'error')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_utxo, 'abc', 0)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end

    it 'returns Result::Error(retryable: true) on 429' do
      http_client = fake(429, 'rate limited')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_utxo, 'abc', 0)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # is_utxo_bulk — bulk spent check (escape hatch)
  # ---------------------------------------------------------------------------

  describe '#call(:is_utxo_bulk)' do
    let(:first_txid) { 'a' * 64 }
    let(:second_txid) { 'b' * 64 }

    it 'returns a hash mapping outpoints to booleans — mix of spent and unspent' do
      response = [
        { 'utxo' => { 'txid' => first_txid, 'vout' => 0 }, 'error' => '' },
        { 'utxo' => { 'txid' => second_txid, 'vout' => 1 }, 'spentIn' => { 'txid' => 'deadbeef', 'vin' => 0, 'status' => 'confirmed' }, 'error' => '' }
      ].to_json
      http_client = fake(200, response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_utxo_bulk, [{ txid: first_txid, vout: 0 }, { txid: second_txid, vout: 1 }])

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data["#{first_txid}.0"]).to be(true)
      expect(result.data["#{second_txid}.1"]).to be(false)
    end

    it 'sends POST to /utxos/spent with utxos-wrapped body format' do
      response = [{ 'utxo' => { 'txid' => first_txid, 'vout' => 0 }, 'error' => '' }].to_json
      http_client = fake(200, response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:is_utxo_bulk, [{ txid: first_txid, vout: 0 }])

      expect(http_client.last_uri.path).to end_with('/utxos/spent')
      expect(http_client.last_request).to be_a(Net::HTTP::Post)
      body = JSON.parse(http_client.last_request.body)
      expect(body).to be_a(Hash)
      expect(body).to have_key('utxos')
      expect(body['utxos']).to be_an(Array)
      expect(body['utxos'].first).to include('txid' => first_txid, 'vout' => 0)
    end

    it 'returns an empty hash for an empty input array without making an HTTP request' do
      http_client = fake(500, 'should not be called')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_utxo_bulk, [])

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq({})
    end

    it 'treats outpoints absent from the response as spent (false)' do
      # Response only includes one of the two queried outpoints
      response = [{ 'utxo' => { 'txid' => first_txid, 'vout' => 0 }, 'error' => '' }].to_json
      http_client = fake(200, response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_utxo_bulk, [{ txid: first_txid, vout: 0 }, { txid: second_txid, vout: 1 }])

      expect(result.data["#{first_txid}.0"]).to be(true)
      expect(result.data["#{second_txid}.1"]).to be(false)
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'server error')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_utxo_bulk, [{ txid: first_txid, vout: 0 }])

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end

    it 'returns Result::NotFound on 404' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_utxo_bulk, [{ txid: first_txid, vout: 0 }])

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end

    it 'returns Result::Error on malformed (non-array) response body' do
      http_client = fake(200, '{"not":"an array"}')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_utxo_bulk, [{ txid: first_txid, vout: 0 }])

      expect(result).to be_a(BSV::Network::Result::Error)
    end
  end

  # ---------------------------------------------------------------------------
  # broadcast — plain text txid response (escape hatch)
  # ---------------------------------------------------------------------------

  describe '#call(:broadcast)' do
    let(:raw_txid) { 'a' * 64 }

    it 'returns a hash with the txid on success' do
      http_client = fake(200, raw_txid)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)
      tx = double('tx', to_hex: '01000000') # rubocop:disable RSpec/VerifiedDoubles

      result = protocol.call(:broadcast, tx)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data[:txid]).to eq(raw_txid)
    end

    it 'strips whitespace from the txid response' do
      http_client = fake(200, "#{raw_txid}\n")
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:broadcast, '01000000')

      expect(result.data[:txid]).to eq(raw_txid)
    end

    it 'uses txhex as the body field name' do
      http_client = fake(200, raw_txid)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:broadcast, '01000000')

      body = JSON.parse(http_client.last_request.body)
      expect(body).to have_key('txhex')
      expect(body).not_to have_key('rawTx')
    end

    it 'calls to_hex on a transaction object' do
      http_client = fake(200, raw_txid)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)
      tx = double('tx', to_hex: 'deadbeef') # rubocop:disable RSpec/VerifiedDoubles

      protocol.call(:broadcast, tx)

      body = JSON.parse(http_client.last_request.body)
      expect(body['txhex']).to eq('deadbeef')
    end

    it 'uses the string directly when tx does not respond to to_hex' do
      http_client = fake(200, raw_txid)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:broadcast, 'cafebabe')

      body = JSON.parse(http_client.last_request.body)
      expect(body['txhex']).to eq('cafebabe')
    end

    it 'sends POST to /tx/raw' do
      http_client = fake(200, raw_txid)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:broadcast, '01000000')

      expect(http_client.last_uri.path).to end_with('/tx/raw')
      expect(http_client.last_request).to be_a(Net::HTTP::Post)
    end

    it 'returns Result::Error on 400' do
      http_client = fake(400, 'bad request')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:broadcast, '01000000')

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(false)
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'server error')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:broadcast, '01000000')

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # valid_root — merkle root comparison (escape hatch)
  # ---------------------------------------------------------------------------

  describe '#call(:valid_root)' do
    let(:merkle_root) { 'abcdef1234567890' * 4 }
    let(:header_json) { { 'height' => 800_000, 'merkleroot' => merkle_root }.to_json }

    it 'returns true when the root matches' do
      http_client = fake(200, header_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:valid_root, merkle_root, 800_000)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be(true)
    end

    it 'returns false when the root does not match' do
      http_client = fake(200, header_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:valid_root, 'wrong_root', 800_000)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be(false)
    end

    it 'is case-insensitive in comparison' do
      upper_root = merkle_root.upcase
      http_client = fake(200, { 'merkleroot' => merkle_root.downcase }.to_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:valid_root, upper_root, 800_000)

      expect(result.data).to be(true)
    end

    it 'returns Result::NotFound when the block height is unknown' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:valid_root, merkle_root, 99_999_999)

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end

    it 'returns Result::Error on 500' do
      http_client = fake(500, 'error')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:valid_root, merkle_root, 800_000)

      expect(result).to be_a(BSV::Network::Result::Error)
    end
  end

  # ---------------------------------------------------------------------------
  # get_script_unspent
  # ---------------------------------------------------------------------------

  describe '#call(:get_script_unspent)' do
    let(:script_hash) { 'f' * 64 }
    let(:utxo_array) do
      {
        'script' => 'f' * 64,
        'result' => [{ 'tx_hash' => 'aaa', 'tx_pos' => 0, 'value' => 5000, 'height' => 1, 'isSpentInMempoolTx' => false }],
        'error' => ''
      }.to_json
    end

    it 'returns a JSON array on success' do
      http_client = fake(200, utxo_array)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_script_unspent, script_hash)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data.length).to eq(1)
    end

    it 'sends GET to /script/{script_hash}/confirmed/unspent' do
      empty_response = { 'script' => script_hash, 'result' => [], 'error' => '' }.to_json
      http_client = fake(200, empty_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_script_unspent, script_hash)

      expect(http_client.last_uri.path).to end_with("/script/#{script_hash}/confirmed/unspent")
    end
  end

  # ---------------------------------------------------------------------------
  # get_balance
  # ---------------------------------------------------------------------------

  describe '#call(:get_balance)' do
    it 'returns parsed JSON balance object' do
      body = '{"address":"1AddressBSV","script":"deadbeef","confirmed":50000,"error":"","associatedScripts":[{"script":"deadbeef","type":"pubkeyhash"}]}'
      http_client = fake(200, body)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_balance, '1AddressBSV')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['confirmed']).to eq(50_000)
    end

    it 'sends GET to /address/{address}/confirmed/balance' do
      body = '{"address":"1TestAddr","script":"deadbeef","confirmed":0,"error":""}'
      http_client = fake(200, body)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_balance, '1TestAddr')

      expect(http_client.last_uri.path).to end_with('/address/1TestAddr/confirmed/balance')
    end
  end

  # ---------------------------------------------------------------------------
  # health
  # ---------------------------------------------------------------------------

  describe '#call(:health)' do
    it 'returns raw body string on success' do
      http_client = fake(200, 'Whats On Chain')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:health)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq('Whats On Chain')
    end

    it 'sends GET to /health' do
      http_client = fake(200, 'ok')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:health)

      expect(http_client.last_uri.path).to end_with('/woc')
    end
  end

  # ---------------------------------------------------------------------------
  # get_tx_status
  # ---------------------------------------------------------------------------

  describe '#call(:get_tx_status)' do
    it 'sends POST to /txs/status' do
      body = '[{"txid":"abc","status":"mined"}]'
      http_client = fake(200, body)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_tx_status, body: '[{"txid":"abc"}]')

      expect(http_client.last_uri.path).to end_with('/txs/status')
      expect(http_client.last_request).to be_a(Net::HTTP::Post)
    end
  end

  # ---------------------------------------------------------------------------
  # get_chain_info — full chain info object
  # ---------------------------------------------------------------------------

  describe '#call(:get_chain_info)' do
    let(:chain_info_json) { '{"chain":"main","blocks":812345,"bestblockhash":"abcd1234"}' }

    it 'returns parsed JSON chain info on success' do
      http_client = fake(200, chain_info_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_chain_info)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['blocks']).to eq(812_345)
      expect(result.data['bestblockhash']).to eq('abcd1234')
    end

    it 'sends GET to /chain/info' do
      http_client = fake(200, chain_info_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_chain_info)

      expect(http_client.last_uri.path).to end_with('/chain/info')
    end

    it 'returns Result::NotFound on 404' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_chain_info)

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end
  end

  # ---------------------------------------------------------------------------
  # get_block_headers — bulk header sync
  # ---------------------------------------------------------------------------

  describe '#call(:get_block_headers)' do
    let(:headers_json) do
      [
        { 'hash' => 'abc', 'height' => 800_000, 'merkleroot' => 'dead' },
        { 'hash' => 'def', 'height' => 800_001, 'merkleroot' => 'beef' }
      ].to_json
    end

    it 'returns a JSON array of block headers on success' do
      http_client = fake(200, headers_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_block_headers)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data.length).to eq(2)
      expect(result.data[0]['height']).to eq(800_000)
    end

    it 'sends GET to /block/headers' do
      http_client = fake(200, headers_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_block_headers)

      expect(http_client.last_uri.path).to end_with('/block/headers')
    end

    it 'returns Result::NotFound on 404' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_block_headers)

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end
  end

  # ---------------------------------------------------------------------------
  # get_unconfirmed_balance
  # ---------------------------------------------------------------------------

  describe '#call(:get_unconfirmed_balance)' do
    it 'returns parsed JSON balance object on success' do
      body = '{"address":"1AddressBSV","script":"deadbeef","unconfirmed":25000,"error":""}'
      http_client = fake(200, body)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_unconfirmed_balance, '1AddressBSV')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['unconfirmed']).to eq(25_000)
    end

    it 'sends GET to /address/{address}/unconfirmed/balance' do
      http_client = fake(200, '{"unconfirmed":0}')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_unconfirmed_balance, '1TestAddr')

      expect(http_client.last_uri.path).to end_with('/address/1TestAddr/unconfirmed/balance')
    end

    it 'returns Result::NotFound on 404' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_unconfirmed_balance, '1UnknownAddress')

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end
  end

  # ---------------------------------------------------------------------------
  # get_history — confirmed transaction history
  # ---------------------------------------------------------------------------

  describe '#call(:get_history)' do
    let(:history_json) do
      {
        'address' => '1AzDmXHX891VQovic5A7iqrW3AnikSf6tm',
        'script' => '2673c96e7c5ab126b5f99251882d74c84997a52df85ae6c8ddbd843a7d322ad1',
        'result' => [
          { 'tx_hash' => 'abc123', 'height' => 800_000 },
          { 'tx_hash' => 'def456', 'height' => 800_001 }
        ],
        'error' => ''
      }.to_json
    end

    it 'returns a JSON array of history entries on success' do
      http_client = fake(200, history_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_history, '1AddressBSV')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data.length).to eq(2)
      expect(result.data[0]['tx_hash']).to eq('abc123')
    end

    it 'sends GET to /address/{address}/confirmed/history' do
      empty_response = { 'address' => '1TestAddr', 'script' => 'deadbeef', 'result' => [], 'error' => '' }.to_json
      http_client = fake(200, empty_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_history, '1TestAddr')

      expect(http_client.last_uri.path).to end_with('/address/1TestAddr/confirmed/history')
    end

    it 'returns Result::NotFound on 404' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_history, '1UnknownAddress')

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end
  end

  # ---------------------------------------------------------------------------
  # is_address_used — HD wallet gap detection
  # ---------------------------------------------------------------------------

  describe '#call(:is_address_used)' do
    it 'returns parsed JSON response on success' do
      http_client = fake(200, 'true')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_address_used, '1AddressBSV')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be(true)
    end

    it 'sends GET to /address/{address}/used' do
      http_client = fake(200, 'false')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:is_address_used, '1TestAddr')

      expect(http_client.last_uri.path).to end_with('/address/1TestAddr/used')
    end

    it 'returns Result::NotFound on 404' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_address_used, '1UnknownAddress')

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end
  end

  # ---------------------------------------------------------------------------
  # get_exchange_rate
  # ---------------------------------------------------------------------------

  describe '#call(:get_exchange_rate)' do
    it 'returns parsed JSON exchange rate on success' do
      body = '{"rate":62500.0,"currency":"USD"}'
      http_client = fake(200, body)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_exchange_rate)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['rate']).to eq(62_500.0)
    end

    it 'sends GET to /exchangerate' do
      http_client = fake(200, '{"rate":62500.0}')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_exchange_rate)

      expect(http_client.last_uri.path).to end_with('/exchangerate')
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'server error')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_exchange_rate)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # get_fee_recommendation
  # ---------------------------------------------------------------------------

  describe '#call(:get_fee_recommendation)' do
    it 'returns parsed JSON fee recommendation on success' do
      body = '{"fee_unit":"sat/KB","fee":100,"mempool_min_fee":100,"fee_usd":"0.00001641"}'
      http_client = fake(200, body)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_fee_recommendation)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['fee']).to eq(100)
    end

    it 'sends GET to /feerecommendation' do
      http_client = fake(200, '{"fee_unit":"sat/KB","fee":1}')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_fee_recommendation)

      expect(http_client.last_uri.path).to end_with('/feerecommendation')
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'server error')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_fee_recommendation)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # get_mempool_info
  # ---------------------------------------------------------------------------

  describe '#call(:get_mempool_info)' do
    it 'returns parsed JSON mempool info on success' do
      body = '{"size":1234,"bytes":5000000}'
      http_client = fake(200, body)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_mempool_info)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['size']).to eq(1234)
    end

    it 'sends GET to /mempool/info' do
      http_client = fake(200, '{"size":0}')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_mempool_info)

      expect(http_client.last_uri.path).to end_with('/mempool/info')
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'server error')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_mempool_info)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # get_tx_details — full transaction JSON
  # ---------------------------------------------------------------------------

  describe '#call(:get_tx_details)' do
    let(:txid) { 'a' * 64 }
    let(:tx_json) do
      { 'txid' => txid, 'blockhash' => 'b' * 64, 'confirmations' => 6 }.to_json
    end

    it 'returns parsed JSON transaction detail on success' do
      http_client = fake(200, tx_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_tx_details, txid)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['txid']).to eq(txid)
      expect(result.data['confirmations']).to eq(6)
    end

    it 'sends GET to /tx/hash/{txid}' do
      http_client = fake(200, tx_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_tx_details, txid)

      expect(http_client.last_uri.path).to end_with("/tx/hash/#{txid}")
    end

    it 'returns Result::NotFound for unknown txid' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_tx_details, 'unknown')

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'server error')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_tx_details, txid)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # get_output_script — single output script hex
  # ---------------------------------------------------------------------------

  describe '#call(:get_output_script)' do
    let(:txid)   { 'b' * 64 }
    let(:script) { '76a914deadbeef88ac' }

    it 'returns raw hex script on success' do
      http_client = fake(200, script)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_output_script, txid, 0)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq(script)
    end

    it 'sends GET to /tx/{txid}/out/{index}/hex' do
      http_client = fake(200, script)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_output_script, txid, 2)

      expect(http_client.last_uri.path).to end_with("/tx/#{txid}/out/2/hex")
    end

    it 'returns Result::NotFound for unknown txid or index' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_output_script, 'unknown', 0)

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end
  end

  # ---------------------------------------------------------------------------
  # get_opreturn — OP_RETURN data for a transaction
  # ---------------------------------------------------------------------------

  describe '#call(:get_opreturn)' do
    let(:txid)    { 'c' * 64 }
    let(:op_json) { [{ 'n' => 1, 'hex' => '6a0568656c6c6f' }].to_json }

    it 'returns parsed JSON OP_RETURN data on success' do
      http_client = fake(200, op_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_opreturn, txid)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data.first['hex']).to eq('6a0568656c6c6f')
    end

    it 'sends GET to /tx/{txid}/opreturn' do
      http_client = fake(200, op_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_opreturn, txid)

      expect(http_client.last_uri.path).to end_with("/tx/#{txid}/opreturn")
    end

    it 'returns Result::NotFound when no OP_RETURN output exists' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_opreturn, 'no_opreturn_txid')

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end
  end

  # ---------------------------------------------------------------------------
  # get_tx_hex_bulk — bulk raw hex fetch (escape hatch)
  # ---------------------------------------------------------------------------

  describe '#call(:get_tx_hex_bulk)' do
    let(:txids)     { ['a' * 64, 'b' * 64] }
    let(:bulk_json) { [{ 'txid' => 'a' * 64, 'hex' => '01000000' }].to_json }

    it 'returns parsed JSON array on success' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_tx_hex_bulk, txids)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
    end

    it 'sends POST to /txs/hex' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_tx_hex_bulk, txids)

      expect(http_client.last_uri.path).to end_with('/txs/hex')
      expect(http_client.last_request).to be_a(Net::HTTP::Post)
    end

    it 'sends txids wrapped in a JSON object' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_tx_hex_bulk, txids)

      body = JSON.parse(http_client.last_request.body)
      expect(body).to be_a(Hash)
      expect(body).to have_key('txids')
      expect(body['txids']).to eq(txids)
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'server error')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_tx_hex_bulk, txids)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # decode_tx — decode raw transaction (escape hatch)
  # ---------------------------------------------------------------------------

  describe '#call(:decode_tx)' do
    let(:decoded_json) { '{"txid":"abc","vin":[],"vout":[]}' }

    it 'returns parsed JSON decoded transaction on success' do
      http_client = fake(200, decoded_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:decode_tx, '01000000')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['txid']).to eq('abc')
    end

    it 'sends POST to /tx/decode' do
      http_client = fake(200, decoded_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:decode_tx, '01000000')

      expect(http_client.last_uri.path).to end_with('/tx/decode')
      expect(http_client.last_request).to be_a(Net::HTTP::Post)
    end

    it 'sends { txhex: ... } as the body' do
      http_client = fake(200, decoded_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:decode_tx, 'deadbeef')

      body = JSON.parse(http_client.last_request.body)
      expect(body).to have_key('txhex')
      expect(body['txhex']).to eq('deadbeef')
    end

    it 'returns Result::Error on 400 (malformed hex)' do
      http_client = fake(400, 'bad request')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:decode_tx, 'not_valid_hex')

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # get_script_history — confirmed transaction history for a script
  # ---------------------------------------------------------------------------

  describe '#call(:get_script_history)' do
    let(:script_hash) { 'e' * 64 }
    let(:history_array) do
      {
        'script' => 'e' * 64,
        'result' => [{ 'tx_hash' => 'abc', 'height' => 800_000 }],
        'error' => ''
      }.to_json
    end

    it 'returns a JSON array of history entries on success' do
      http_client = fake(200, history_array)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_script_history, script_hash)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data.first['tx_hash']).to eq('abc')
    end

    it 'sends GET to /script/{script_hash}/confirmed/history' do
      empty_response = { 'script' => script_hash, 'result' => [], 'error' => '' }.to_json
      http_client = fake(200, empty_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_script_history, script_hash)

      expect(http_client.last_uri.path).to end_with("/script/#{script_hash}/confirmed/history")
    end

    it 'returns Result::NotFound on 404' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_script_history, script_hash)

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'error')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_script_history, script_hash)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # get_script_all_unspent — all UTXOs (confirmed + unconfirmed) for a script
  # ---------------------------------------------------------------------------

  describe '#call(:get_script_all_unspent)' do
    let(:script_hash) { 'd' * 64 }
    let(:utxo_array) do
      {
        'script' => 'd' * 64,
        'result' => [{ 'tx_hash' => 'fff', 'tx_pos' => 1, 'value' => 9_000, 'height' => 0, 'isSpentInMempoolTx' => false, 'status' => 'confirmed' }],
        'error' => ''
      }.to_json
    end

    it 'returns a JSON array of UTXOs on success' do
      http_client = fake(200, utxo_array)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_script_all_unspent, script_hash)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data.length).to eq(1)
    end

    it 'sends GET to /script/{script_hash}/unspent/all' do
      empty_response = { 'script' => script_hash, 'result' => [], 'error' => '' }.to_json
      http_client = fake(200, empty_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_script_all_unspent, script_hash)

      expect(http_client.last_uri.path).to end_with("/script/#{script_hash}/unspent/all")
    end

    it 'returns Result::NotFound on 404' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_script_all_unspent, script_hash)

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end
  end

  # ---------------------------------------------------------------------------
  # get_script_unspent_bulk — confirmed UTXOs for multiple scripts (escape hatch)
  # ---------------------------------------------------------------------------

  describe '#call(:get_script_unspent_bulk)' do
    let(:hashes)    { ['a' * 64, 'b' * 64] }
    let(:bulk_json) { '{"aaa...":[],"bbb...":[]}' }

    it 'returns parsed JSON on success' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_script_unspent_bulk, hashes)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_a(Hash)
    end

    it 'sends POST to /scripts/confirmed/unspent' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_script_unspent_bulk, hashes)

      expect(http_client.last_uri.path).to end_with('/scripts/confirmed/unspent')
      expect(http_client.last_request).to be_a(Net::HTTP::Post)
    end

    it 'sends scripts wrapped in a JSON object' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_script_unspent_bulk, hashes)

      body = JSON.parse(http_client.last_request.body)
      expect(body).to be_a(Hash)
      expect(body).to have_key('scripts')
      expect(body['scripts']).to eq(hashes)
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'server error')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_script_unspent_bulk, hashes)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # get_circulating_supply
  # ---------------------------------------------------------------------------

  describe '#call(:get_circulating_supply)' do
    it 'returns raw circulating supply string on success' do
      http_client = fake(200, '19890434.375')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_circulating_supply)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq('19890434.375')
    end

    it 'sends GET to /circulatingsupply' do
      http_client = fake(200, '19890434.375')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_circulating_supply)

      expect(http_client.last_uri.path).to end_with('/circulatingsupply')
    end
  end

  # ---------------------------------------------------------------------------
  # get_chain_tips
  # ---------------------------------------------------------------------------

  describe '#call(:get_chain_tips)' do
    let(:chain_tips_json) do
      [{ 'height' => 948_246, 'hash' => '000' * 10, 'branchlen' => 0, 'status' => 'active' }].to_json
    end

    it 'returns a JSON array of chain tips on success' do
      http_client = fake(200, chain_tips_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_chain_tips)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data.first['status']).to eq('active')
    end

    it 'sends GET to /chain/tips' do
      http_client = fake(200, chain_tips_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_chain_tips)

      expect(http_client.last_uri.path).to end_with('/chain/tips')
    end
  end

  # ---------------------------------------------------------------------------
  # get_peer_info
  # ---------------------------------------------------------------------------

  describe '#call(:get_peer_info)' do
    let(:peer_info_json) do
      [{ 'addr' => '1.2.3.4:8333', 'services' => '0x01' }].to_json
    end

    it 'returns a JSON array of peer info on success' do
      http_client = fake(200, peer_info_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_peer_info)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data.first['addr']).to eq('1.2.3.4:8333')
    end

    it 'sends GET to /peer/info' do
      http_client = fake(200, peer_info_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_peer_info)

      expect(http_client.last_uri.path).to end_with('/peer/info')
    end
  end

  # ---------------------------------------------------------------------------
  # get_tx_binary
  # ---------------------------------------------------------------------------

  describe '#call(:get_tx_binary)' do
    let(:txid) { 'a' * 64 }

    it 'returns raw binary string on success' do
      binary = "\x01\x00\x00\x00\xde\xad\xbe\xef"
      http_client = fake(200, binary)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_tx_binary, txid)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_a(String)
    end

    it 'sends GET to /tx/{txid}/bin' do
      http_client = fake(200, "\x01\x00")
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_tx_binary, txid)

      expect(http_client.last_uri.path).to end_with("/tx/#{txid}/bin")
    end

    it 'returns Result::NotFound for unknown txid' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_tx_binary, 'unknown')

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end
  end

  # ---------------------------------------------------------------------------
  # get_tx_by_block_index
  # ---------------------------------------------------------------------------

  describe '#call(:get_tx_by_block_index)' do
    let(:tx_json) { '{"txid":"abc","hash":"abc","version":1}' }

    it 'returns parsed JSON transaction on success' do
      http_client = fake(200, tx_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_tx_by_block_index, 556_767, 0)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['txid']).to eq('abc')
    end

    it 'sends GET to /block/height/{height}/txindex/{txindex}' do
      http_client = fake(200, tx_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_tx_by_block_index, 556_767, 0)

      expect(http_client.last_uri.path).to end_with('/block/height/556767/txindex/0')
    end
  end

  # ---------------------------------------------------------------------------
  # get_tx_propagation
  # ---------------------------------------------------------------------------

  describe '#call(:get_tx_propagation)' do
    let(:txid) { 'd' * 64 }
    let(:propagation_json) { '{"propagation":"100%"}' }

    it 'returns parsed JSON propagation info on success' do
      http_client = fake(200, propagation_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_tx_propagation, txid)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['propagation']).to eq('100%')
    end

    it 'sends GET to /tx/hash/{txid}/propagation' do
      http_client = fake(200, propagation_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_tx_propagation, txid)

      expect(http_client.last_uri.path).to end_with("/tx/hash/#{txid}/propagation")
    end
  end

  # ---------------------------------------------------------------------------
  # get_bulk_tx_details — POST escape hatch
  # ---------------------------------------------------------------------------

  describe '#call(:get_bulk_tx_details)' do
    let(:txids)     { ['a' * 64, 'b' * 64] }
    let(:bulk_json) { [{ 'txid' => 'abc', 'version' => 1 }].to_json }

    it 'returns parsed JSON array on success' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_bulk_tx_details, txids)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data.first['txid']).to eq('abc')
    end

    it 'sends POST to /txs' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_bulk_tx_details, txids)

      expect(http_client.last_uri.path).to end_with('/txs')
      expect(http_client.last_request).to be_a(Net::HTTP::Post)
    end

    it 'sends txids wrapped in a JSON object' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_bulk_tx_details, txids)

      body = JSON.parse(http_client.last_request.body)
      expect(body).to be_a(Hash)
      expect(body).to have_key('txids')
      expect(body['txids']).to eq(txids)
    end
  end

  # ---------------------------------------------------------------------------
  # get_bulk_output_scripts — POST escape hatch
  # ---------------------------------------------------------------------------

  describe '#call(:get_bulk_output_scripts)' do
    let(:tx_vouts) { [{ txid: 'a' * 64, vouts: [0, 1] }] }
    let(:bulk_json) do
      [{ 'txid' => 'abc', 'vout' => { '0' => { 'scriptPubKey' => { 'hex' => '76a914deadbeef88ac' } } } }].to_json
    end

    it 'returns parsed JSON array on success' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_bulk_output_scripts, tx_vouts)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
    end

    it 'sends POST to /txs/vouts/hex' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_bulk_output_scripts, tx_vouts)

      expect(http_client.last_uri.path).to end_with('/txs/vouts/hex')
      expect(http_client.last_request).to be_a(Net::HTTP::Post)
    end

    it 'sends a txids array with nested vouts in the body' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_bulk_output_scripts, tx_vouts)

      body = JSON.parse(http_client.last_request.body)
      expect(body).to be_a(Hash)
      expect(body).to have_key('txids')
      expect(body['txids']).to be_an(Array)
      expect(body['txids'].first).to have_key('txid')
      expect(body['txids'].first).to have_key('vouts')
    end
  end

  # ---------------------------------------------------------------------------
  # get_unconfirmed_utxos
  # ---------------------------------------------------------------------------

  describe '#call(:get_unconfirmed_utxos)' do
    let(:address) { '1AzDmXHX891VQovic5A7iqrW3AnikSf6tm' }
    let(:utxo_response) do
      {
        'address' => address,
        'script' => 'deadbeef',
        'result' => [{ 'tx_hash' => 'abc', 'value' => 1000, 'height' => 0, 'hex' => '76a914deadbeef88ac' }],
        'error' => ''
      }.to_json
    end

    it 'returns a JSON array on success' do
      http_client = fake(200, utxo_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_unconfirmed_utxos, address)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data.first['tx_hash']).to eq('abc')
    end

    it 'sends GET to /address/{address}/unconfirmed/unspent' do
      http_client = fake(200, utxo_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_unconfirmed_utxos, address)

      expect(http_client.last_uri.path).to end_with("/address/#{address}/unconfirmed/unspent")
    end
  end

  # ---------------------------------------------------------------------------
  # get_confirmed_spent
  # ---------------------------------------------------------------------------

  describe '#call(:get_confirmed_spent)' do
    let(:txid) { 'e' * 64 }
    let(:spent_json) { '{"txid":"spending...","vin":0,"status":"confirmed"}' }

    it 'returns parsed JSON on success' do
      http_client = fake(200, spent_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_confirmed_spent, txid, 1)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['status']).to eq('confirmed')
    end

    it 'sends GET to /tx/{txid}/{vout}/confirmed/spent' do
      http_client = fake(200, spent_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_confirmed_spent, txid, 1)

      expect(http_client.last_uri.path).to end_with("/tx/#{txid}/1/confirmed/spent")
    end
  end

  # ---------------------------------------------------------------------------
  # get_unconfirmed_spent
  # ---------------------------------------------------------------------------

  describe '#call(:get_unconfirmed_spent)' do
    let(:txid) { 'f' * 64 }
    let(:spent_json) { '{"txid":"spending...","vin":0,"status":"unconfirmed"}' }

    it 'returns parsed JSON on success' do
      http_client = fake(200, spent_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_unconfirmed_spent, txid, 2)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['status']).to eq('unconfirmed')
    end

    it 'sends GET to /tx/{txid}/{vout}/unconfirmed/spent' do
      http_client = fake(200, spent_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_unconfirmed_spent, txid, 2)

      expect(http_client.last_uri.path).to end_with("/tx/#{txid}/2/unconfirmed/spent")
    end
  end

  # ---------------------------------------------------------------------------
  # get_bulk_address_utxos — POST escape hatch
  # ---------------------------------------------------------------------------

  describe '#call(:get_bulk_address_utxos)' do
    let(:addresses) { %w[1AddressOne 1AddressTwo] }
    let(:bulk_json) { '[{"address":"1AddressOne","utxos":[]}]' }

    it 'returns parsed JSON on success' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_bulk_address_utxos, addresses)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
    end

    it 'sends POST to /addresses/confirmed/unspent' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_bulk_address_utxos, addresses)

      expect(http_client.last_uri.path).to end_with('/addresses/confirmed/unspent')
      expect(http_client.last_request).to be_a(Net::HTTP::Post)
    end

    it 'sends addresses wrapped in a JSON object' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_bulk_address_utxos, addresses)

      body = JSON.parse(http_client.last_request.body)
      expect(body).to be_a(Hash)
      expect(body).to have_key('addresses')
      expect(body['addresses']).to eq(addresses)
    end
  end

  # ---------------------------------------------------------------------------
  # get_bulk_address_unconfirmed_utxos — POST escape hatch
  # ---------------------------------------------------------------------------

  describe '#call(:get_bulk_address_unconfirmed_utxos)' do
    let(:addresses) { %w[1AddressOne 1AddressTwo] }
    let(:bulk_json) { '[{"address":"1AddressOne","utxos":[]}]' }

    it 'returns parsed JSON on success' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_bulk_address_unconfirmed_utxos, addresses)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
    end

    it 'sends POST to /addresses/unconfirmed/unspent' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_bulk_address_unconfirmed_utxos, addresses)

      expect(http_client.last_uri.path).to end_with('/addresses/unconfirmed/unspent')
      expect(http_client.last_request).to be_a(Net::HTTP::Post)
    end

    it 'sends addresses wrapped in a JSON object' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_bulk_address_unconfirmed_utxos, addresses)

      body = JSON.parse(http_client.last_request.body)
      expect(body).to be_a(Hash)
      expect(body).to have_key('addresses')
      expect(body['addresses']).to eq(addresses)
    end
  end

  # ---------------------------------------------------------------------------
  # get_script_unconfirmed_unspent
  # ---------------------------------------------------------------------------

  describe '#call(:get_script_unconfirmed_unspent)' do
    let(:script_hash) { 'a' * 64 }
    let(:utxo_response) do
      {
        'script' => script_hash,
        'result' => [{ 'tx_hash' => 'abc', 'tx_pos' => 0, 'value' => 5000, 'height' => 0 }],
        'error' => ''
      }.to_json
    end

    it 'returns a JSON array on success' do
      http_client = fake(200, utxo_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_script_unconfirmed_unspent, script_hash)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data.first['tx_hash']).to eq('abc')
    end

    it 'sends GET to /script/{script_hash}/unconfirmed/unspent' do
      http_client = fake(200, utxo_response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_script_unconfirmed_unspent, script_hash)

      expect(http_client.last_uri.path).to end_with("/script/#{script_hash}/unconfirmed/unspent")
    end
  end

  # ---------------------------------------------------------------------------
  # get_bulk_script_unconfirmed_unspent — POST escape hatch
  # ---------------------------------------------------------------------------

  describe '#call(:get_bulk_script_unconfirmed_unspent)' do
    let(:hashes)    { ['a' * 64, 'b' * 64] }
    let(:bulk_json) { '{"aaa...":[]}' }

    it 'returns parsed JSON on success' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_bulk_script_unconfirmed_unspent, hashes)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_a(Hash)
    end

    it 'sends POST to /scripts/unconfirmed/unspent' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_bulk_script_unconfirmed_unspent, hashes)

      expect(http_client.last_uri.path).to end_with('/scripts/unconfirmed/unspent')
      expect(http_client.last_request).to be_a(Net::HTTP::Post)
    end

    it 'sends scripts wrapped in a JSON object' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_bulk_script_unconfirmed_unspent, hashes)

      body = JSON.parse(http_client.last_request.body)
      expect(body).to be_a(Hash)
      expect(body).to have_key('scripts')
      expect(body['scripts']).to eq(hashes)
    end
  end

  # ---------------------------------------------------------------------------
  # get_exchange_rate_historical
  # ---------------------------------------------------------------------------

  describe '#call(:get_exchange_rate_historical)' do
    let(:historical_json) do
      [{ 'rate' => 16.50, 'time' => 1_778_000_000 }, { 'rate' => 16.41, 'time' => 1_778_100_000 }].to_json
    end

    it 'returns a JSON array of historical rates on success' do
      http_client = fake(200, historical_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_exchange_rate_historical)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data.first['rate']).to eq(16.50)
    end

    it 'sends GET to /exchangerate/historical' do
      http_client = fake(200, historical_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_exchange_rate_historical)

      expect(http_client.last_uri.path).to end_with('/exchangerate/historical')
    end
  end

  # ---------------------------------------------------------------------------
  # get_mempool_raw
  # ---------------------------------------------------------------------------

  describe '#call(:get_mempool_raw)' do
    let(:mempool_json) { '["abc123","def456"]' }

    it 'returns a JSON array of txids on success' do
      http_client = fake(200, mempool_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_mempool_raw)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data).to include('abc123', 'def456')
    end

    it 'sends GET to /mempool/raw' do
      http_client = fake(200, mempool_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_mempool_raw)

      expect(http_client.last_uri.path).to end_with('/mempool/raw')
    end
  end

  # ---------------------------------------------------------------------------
  # search_links — POST escape hatch
  # ---------------------------------------------------------------------------

  describe '#call(:search_links)' do
    let(:search_json) { '{"results":[{"type":"address","url":"https://whatsonchain.com/address/1Addr"}]}' }

    it 'returns parsed JSON on success' do
      http_client = fake(200, search_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:search_links, '1Addr')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['results']).to be_an(Array)
    end

    it 'sends POST to /search/links' do
      http_client = fake(200, search_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:search_links, '1Addr')

      expect(http_client.last_uri.path).to end_with('/search/links')
      expect(http_client.last_request).to be_a(Net::HTTP::Post)
    end

    it 'sends query wrapped in a JSON object' do
      http_client = fake(200, search_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:search_links, 'my search term')

      body = JSON.parse(http_client.last_request.body)
      expect(body).to be_a(Hash)
      expect(body).to have_key('query')
      expect(body['query']).to eq('my search term')
    end
  end

  # ---------------------------------------------------------------------------
  # get_block_stats
  # ---------------------------------------------------------------------------

  describe '#call(:get_block_stats)' do
    let(:stats_json) { '{"height":556767,"txcount":1234}' }

    it 'returns parsed JSON block stats on success' do
      http_client = fake(200, stats_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_block_stats, 556_767)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['txcount']).to eq(1234)
    end

    it 'sends GET to /block/height/{height}/stats' do
      http_client = fake(200, stats_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_block_stats, 556_767)

      expect(http_client.last_uri.path).to end_with('/block/height/556767/stats')
    end
  end

  # ---------------------------------------------------------------------------
  # get_block_stats_by_hash
  # ---------------------------------------------------------------------------

  describe '#call(:get_block_stats_by_hash)' do
    let(:block_hash) { 'abc' * 20 }
    let(:stats_json) { '{"height":556767,"txcount":1234}' }

    it 'returns parsed JSON block stats on success' do
      http_client = fake(200, stats_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_block_stats_by_hash, block_hash)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['height']).to eq(556_767)
    end

    it 'sends GET to /block/hash/{hash}/stats' do
      http_client = fake(200, stats_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_block_stats_by_hash, block_hash)

      expect(http_client.last_uri.path).to end_with("/block/hash/#{block_hash}/stats")
    end
  end

  # ---------------------------------------------------------------------------
  # get_miner_block_stats
  # ---------------------------------------------------------------------------

  describe '#call(:get_miner_block_stats)' do
    let(:stats_json) { '{"miners":[{"name":"TAAL","blocks":100}]}' }

    it 'returns parsed JSON miner block stats on success' do
      http_client = fake(200, stats_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_miner_block_stats)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['miners']).to be_an(Array)
    end

    it 'sends GET to /miner/blocks/stats' do
      http_client = fake(200, stats_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_miner_block_stats)

      expect(http_client.last_uri.path).to end_with('/miner/blocks/stats')
    end
  end

  # ---------------------------------------------------------------------------
  # get_miner_fees
  # ---------------------------------------------------------------------------

  describe '#call(:get_miner_fees)' do
    let(:fees_json) { '{"fees":[{"height":948000,"fee_rate":100}]}' }

    it 'returns parsed JSON miner fees on success' do
      http_client = fake(200, fees_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_miner_fees)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['fees']).to be_an(Array)
    end

    it 'sends GET to /miner/fees' do
      http_client = fake(200, fees_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_miner_fees)

      expect(http_client.last_uri.path).to end_with('/miner/fees')
    end
  end

  # ---------------------------------------------------------------------------
  # get_miner_summary
  # ---------------------------------------------------------------------------

  describe '#call(:get_miner_summary)' do
    let(:summary_json) { '{"total_blocks":1000}' }

    it 'returns parsed JSON miner summary on success' do
      http_client = fake(200, summary_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_miner_summary)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['total_blocks']).to eq(1000)
    end

    it 'sends GET to /miner/summary/stats' do
      http_client = fake(200, summary_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_miner_summary)

      expect(http_client.last_uri.path).to end_with('/miner/summary/stats')
    end
  end

  # ---------------------------------------------------------------------------
  # get_block_tag_count
  # ---------------------------------------------------------------------------

  describe '#call(:get_block_tag_count)' do
    let(:tag_json) { '{"height":556767,"tags":{"OP_RETURN":500}}' }

    it 'returns parsed JSON block tag count on success' do
      http_client = fake(200, tag_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_block_tag_count, 556_767)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['tags']['OP_RETURN']).to eq(500)
    end

    it 'sends GET to /block/tagcount/height/{height}/stats' do
      http_client = fake(200, tag_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_block_tag_count, 556_767)

      expect(http_client.last_uri.path).to end_with('/block/tagcount/height/556767/stats')
    end
  end

  # ---------------------------------------------------------------------------
  # get_tx_status — escape hatch wraps txids array
  # ---------------------------------------------------------------------------

  describe '#call(:get_tx_status) — escape hatch' do
    let(:txids) { ['a' * 64, 'b' * 64] }
    let(:status_json) do
      [{ 'txid' => 'a' * 64, 'blockhash' => 'def' * 21, 'blockheight' => 612_251,
         'blocktime' => 1_575_841_517, 'confirmations' => 300_000 }].to_json
    end

    it 'returns parsed JSON status array on success' do
      http_client = fake(200, status_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_tx_status, txids)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data.first['confirmations']).to eq(300_000)
    end

    it 'sends txids wrapped in a JSON object' do
      http_client = fake(200, status_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_tx_status, txids)

      body = JSON.parse(http_client.last_request.body)
      expect(body).to be_a(Hash)
      expect(body).to have_key('txids')
      expect(body['txids']).to eq(txids)
    end
  end

  # ---------------------------------------------------------------------------
  # API key auth
  # ---------------------------------------------------------------------------

  describe 'API key authentication' do
    it 'sends Bearer auth header when api_key is provided' do
      http_client = fake(200, '{"blocks":800000}')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, api_key: 'my-woc-key', http_client: http_client)

      protocol.call(:current_height)

      expect(http_client.last_request['Authorization']).to eq('my-woc-key')
    end

    it 'omits Authorization header when api_key is not provided' do
      http_client = fake(200, '{"blocks":800000}')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:current_height)

      expect(http_client.last_request['Authorization']).to be_nil
    end
  end
end
