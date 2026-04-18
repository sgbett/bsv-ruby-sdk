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
        get_tx get_tx_details get_output_script get_opreturn
        get_merkle_path broadcast decode_tx get_tx_status get_tx_hex_bulk
        get_utxos is_utxo is_utxo_bulk valid_root
        get_script_unspent get_script_history get_script_all_unspent get_script_unspent_bulk
        get_balance get_unconfirmed_balance get_history is_address_used
        get_exchange_rate get_fee_recommendation get_mempool_info
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
      { 'index' => 3, 'txOrId' => 'abc123', 'target' => 'deadbeef' }.to_json
    end

    it 'returns parsed JSON proof' do
      http_client = fake(200, proof_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_merkle_path, 'abc123')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_a(Hash)
      expect(result.data['index']).to eq(3)
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
      [
        { 'tx_hash' => 'abc', 'tx_pos' => 0, 'value' => 50_000, 'height' => 800_000 },
        { 'tx_hash' => 'def', 'tx_pos' => 1, 'value' => 100_000, 'height' => 800_001 }
      ].to_json
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
      http_client = fake(200, '[]')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_utxos, '1EmptyAddress')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq([])
    end

    it 'sends GET to the confirmed/unspent path' do
      http_client = fake(200, '[]')
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
  # is_utxo — spent status (escape hatch)
  # ---------------------------------------------------------------------------

  describe '#call(:is_utxo)' do
    it 'returns true when the output is unspent' do
      http_client = fake(200, '{"spent":false}')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_utxo, 'abc123', 0)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be(true)
    end

    it 'returns false when the output is spent' do
      http_client = fake(200, '{"spent":true}')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_utxo, 'abc123', 1)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be(false)
    end

    it 'sends GET to /tx/{txid}/{vout}/spent' do
      http_client = fake(200, '{"spent":false}')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)
      txid = 'c' * 64

      protocol.call(:is_utxo, txid, 2)

      expect(http_client.last_uri.path).to end_with("/tx/#{txid}/2/spent")
    end

    it 'accepts script_hash: keyword without error' do
      http_client = fake(200, '{"spent":false}')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      expect { protocol.call(:is_utxo, 'abc', 0, script_hash: 'deadbeef') }.not_to raise_error
    end

    it 'returns Result::NotFound when the txid is unknown' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_utxo, 'unknown', 0)

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'error')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_utxo, 'abc', 0)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end

    it 'returns Result::Error when the spent field is absent from the response' do
      http_client = fake(200, '{"something_else":true}')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_utxo, 'abc123', 0)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.message).to include('missing spent field')
    end

    it 'returns Result::Error when the response body is not a Hash' do
      http_client = fake(200, '"just a string"')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_utxo, 'abc123', 0)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.message).to include('missing spent field')
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
        { 'txid' => first_txid, 'vout' => 0, 'spent' => false },
        { 'txid' => second_txid, 'vout' => 1, 'spent' => true }
      ].to_json
      http_client = fake(200, response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:is_utxo_bulk, [{ txid: first_txid, vout: 0 }, { txid: second_txid, vout: 1 }])

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data["#{first_txid}.0"]).to be(true)
      expect(result.data["#{second_txid}.1"]).to be(false)
    end

    it 'sends POST to /utxos/spent with correct body format' do
      response = [{ 'txid' => first_txid, 'vout' => 0, 'spent' => false }].to_json
      http_client = fake(200, response)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:is_utxo_bulk, [{ txid: first_txid, vout: 0 }])

      expect(http_client.last_uri.path).to end_with('/utxos/spent')
      expect(http_client.last_request).to be_a(Net::HTTP::Post)
      body = JSON.parse(http_client.last_request.body)
      expect(body).to be_an(Array)
      expect(body.first).to include('txid' => first_txid, 'vout' => 0)
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
      response = [{ 'txid' => first_txid, 'vout' => 0, 'spent' => false }].to_json
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
    let(:utxo_array)  { [{ 'tx_hash' => 'aaa', 'tx_pos' => 0, 'value' => 5000, 'height' => 1 }].to_json }

    it 'returns a JSON array on success' do
      http_client = fake(200, utxo_array)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_script_unspent, script_hash)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data.length).to eq(1)
    end

    it 'sends GET to /script/{script_hash}/confirmed/unspent' do
      http_client = fake(200, '[]')
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
      body = '{"confirmed":50000,"unconfirmed":0}'
      http_client = fake(200, body)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_balance, '1AddressBSV')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['confirmed']).to eq(50_000)
    end

    it 'sends GET to /address/{address}/confirmed/balance' do
      http_client = fake(200, '{"confirmed":0}')
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

      expect(http_client.last_uri.path).to end_with('/health')
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
      body = '{"unconfirmed":25000}'
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
      [
        { 'tx_hash' => 'abc123', 'height' => 800_000 },
        { 'tx_hash' => 'def456', 'height' => 800_001 }
      ].to_json
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
      http_client = fake(200, '[]')
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
      body = '{"miningFee":{"satoshis":1,"bytes":1000}}'
      http_client = fake(200, body)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_fee_recommendation)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['miningFee']).to be_a(Hash)
    end

    it 'sends GET to /feerecommendation' do
      http_client = fake(200, '{"miningFee":{}}')
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
    let(:op_json) { '{"data":"68656c6c6f","type":"OP_RETURN"}' }

    it 'returns parsed JSON OP_RETURN data on success' do
      http_client = fake(200, op_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_opreturn, txid)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['data']).to eq('68656c6c6f')
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

    it 'sends a bare JSON array of txid strings as the body' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_tx_hex_bulk, txids)

      body = JSON.parse(http_client.last_request.body)
      expect(body).to be_an(Array)
      expect(body).to eq(txids)
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
    let(:script_hash)   { 'e' * 64 }
    let(:history_array) { [{ 'tx_hash' => 'abc', 'height' => 800_000 }].to_json }

    it 'returns a JSON array of history entries on success' do
      http_client = fake(200, history_array)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_script_history, script_hash)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data.first['tx_hash']).to eq('abc')
    end

    it 'sends GET to /script/{script_hash}/confirmed/history' do
      http_client = fake(200, '[]')
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
    let(:utxo_array)  { [{ 'tx_hash' => 'fff', 'tx_pos' => 1, 'value' => 9_000, 'height' => 0 }].to_json }

    it 'returns a JSON array of UTXOs on success' do
      http_client = fake(200, utxo_array)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      result = protocol.call(:get_script_all_unspent, script_hash)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data.length).to eq(1)
    end

    it 'sends GET to /script/{script_hash}/unspent/all' do
      http_client = fake(200, '[]')
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

    it 'sends a bare JSON array of script hash strings as the body' do
      http_client = fake(200, bulk_json)
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:get_script_unspent_bulk, hashes)

      body = JSON.parse(http_client.last_request.body)
      expect(body).to be_an(Array)
      expect(body).to eq(hashes)
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
  # API key auth
  # ---------------------------------------------------------------------------

  describe 'API key authentication' do
    it 'sends Bearer auth header when api_key is provided' do
      http_client = fake(200, '{"blocks":800000}')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, api_key: 'my-woc-key', http_client: http_client)

      protocol.call(:current_height)

      expect(http_client.last_request['Authorization']).to eq('Bearer my-woc-key')
    end

    it 'omits Authorization header when api_key is not provided' do
      http_client = fake(200, '{"blocks":800000}')
      protocol = described_class.new(base_url: 'https://api.whatsonchain.com/v1/bsv/main', network: :main, http_client: http_client)

      protocol.call(:current_height)

      expect(http_client.last_request['Authorization']).to be_nil
    end
  end
end
