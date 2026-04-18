# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::Protocols::WoCREST do # rubocop:disable RSpec/SpecFilePathFormat
  subject(:woc) { described_class.new(network: :main, http_client: http) }

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
    it 'resolves :main to "main" in the base URL' do
      protocol = described_class.new(network: :main, http_client: fake(200, ''))
      expect(protocol.base_url).to eq('https://api.whatsonchain.com/v1/bsv/main')
    end

    it 'resolves :mainnet to "main"' do
      protocol = described_class.new(network: :mainnet, http_client: fake(200, ''))
      expect(protocol.base_url).to include('/main')
    end

    it 'resolves :test to "test"' do
      protocol = described_class.new(network: :test, http_client: fake(200, ''))
      expect(protocol.base_url).to include('/test')
    end

    it 'resolves :testnet to "test"' do
      protocol = described_class.new(network: :testnet, http_client: fake(200, ''))
      expect(protocol.base_url).to include('/test')
    end

    it 'resolves :stn to "stn"' do
      protocol = described_class.new(network: :stn, http_client: fake(200, ''))
      expect(protocol.base_url).to include('/stn')
    end

    it 'resolves string "main"' do
      protocol = described_class.new(network: 'main', http_client: fake(200, ''))
      expect(protocol.base_url).to include('/main')
    end

    it 'exposes network_name' do
      protocol = described_class.new(network: :mainnet, http_client: fake(200, ''))
      expect(protocol.network_name).to eq('main')
    end

    it 'raises ArgumentError for an unknown network' do
      expect { described_class.new(network: :unknown) }
        .to raise_error(ArgumentError, /unknown network/)
    end
  end

  # ---------------------------------------------------------------------------
  # base_url override
  # ---------------------------------------------------------------------------

  describe '#initialize — base_url override' do
    it 'uses the default BASE_URL when base_url: is omitted' do
      protocol = described_class.new(network: :main, http_client: fake(200, ''))
      expect(protocol.base_url).to eq('https://api.whatsonchain.com/v1/bsv/main')
    end

    it 'uses a fully-qualified override when base_url: is provided without {network}' do
      protocol = described_class.new(base_url: 'https://my.woc.example', network: :main, http_client: fake(200, ''))
      expect(protocol.base_url).to eq('https://my.woc.example')
    end

    it 'still interpolates {network} in an overridden URL template' do
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
    it 'declares all 12 expected commands' do
      expected = %i[
        current_height get_block_header
        get_tx get_merkle_path broadcast get_tx_status
        get_utxos is_utxo valid_root
        get_script_unspent get_balance health
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
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:current_height)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq(812_345)
    end

    it 'sends GET to /chain/info' do
      body = '{"blocks":800000}'
      http_client = fake(200, body)
      protocol = described_class.new(network: :main, http_client: http_client)

      protocol.call(:current_height)

      expect(http_client.last_uri.path).to end_with('/chain/info')
    end

    it 'returns Result::Error on 500' do
      http_client = fake(500, 'server error')
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:current_height)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end

    it 'returns Result::Error on 429 (rate limited)' do
      http_client = fake(429, 'rate limited')
      protocol = described_class.new(network: :main, http_client: http_client)

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
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:get_block_header, 800_000)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['height']).to eq(800_000)
    end

    it 'sends GET to /block/{height}/header' do
      http_client = fake(200, header_json)
      protocol = described_class.new(network: :main, http_client: http_client)

      protocol.call(:get_block_header, 800_000)

      expect(http_client.last_uri.path).to end_with('/block/800000/header')
    end

    it 'returns Result::NotFound for an unknown height' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(network: :main, http_client: http_client)

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
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:get_tx, 'abc123' * 10)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq(hex)
    end

    it 'sends GET to /tx/{txid}/hex' do
      http_client = fake(200, '01000000')
      protocol = described_class.new(network: :main, http_client: http_client)
      txid = 'a' * 64

      protocol.call(:get_tx, txid)

      expect(http_client.last_uri.path).to end_with("/tx/#{txid}/hex")
    end

    it 'returns Result::NotFound for unknown txid' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(network: :main, http_client: http_client)

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
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:get_merkle_path, 'abc123')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_a(Hash)
      expect(result.data['index']).to eq(3)
    end

    it 'sends GET to /tx/{txid}/proof/tsc' do
      http_client = fake(200, proof_json)
      protocol = described_class.new(network: :main, http_client: http_client)
      txid = 'b' * 64

      protocol.call(:get_merkle_path, txid)

      expect(http_client.last_uri.path).to end_with("/tx/#{txid}/proof/tsc")
    end

    it 'returns Result::NotFound when proof does not exist' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:get_merkle_path, 'unconfirmed_txid')

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'internal error')
      protocol = described_class.new(network: :main, http_client: http_client)

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
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:get_utxos, '1AddressBSV')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data[0][:satoshis]).to eq(50_000)
      expect(result.data[1][:satoshis]).to eq(100_000)
    end

    it 'does not include a value key in remapped entries' do
      http_client = fake(200, woc_response)
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:get_utxos, '1AddressBSV')

      expect(result.data[0]).not_to have_key(:value)
      expect(result.data[0]).not_to have_key('value')
    end

    it 'preserves tx_hash, tx_pos, and height fields as symbol keys' do
      http_client = fake(200, woc_response)
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:get_utxos, '1AddressBSV')

      entry = result.data[0]
      expect(entry[:tx_hash]).to eq('abc')
      expect(entry[:tx_pos]).to eq(0)
      expect(entry[:height]).to eq(800_000)
    end

    it 'returns an empty array when the address has no UTXOs' do
      http_client = fake(200, '[]')
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:get_utxos, '1EmptyAddress')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq([])
    end

    it 'sends GET to the confirmed/unspent path' do
      http_client = fake(200, '[]')
      protocol = described_class.new(network: :main, http_client: http_client)

      protocol.call(:get_utxos, '1CheckPath')

      expect(http_client.last_uri.path).to end_with('/address/1CheckPath/confirmed/unspent')
    end

    it 'returns Result::NotFound on 404' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:get_utxos, '1UnknownAddress')

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'server error')
      protocol = described_class.new(network: :main, http_client: http_client)

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
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:is_utxo, 'abc123', 0)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be(true)
    end

    it 'returns false when the output is spent' do
      http_client = fake(200, '{"spent":true}')
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:is_utxo, 'abc123', 1)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be(false)
    end

    it 'sends GET to /tx/{txid}/{vout}/spent' do
      http_client = fake(200, '{"spent":false}')
      protocol = described_class.new(network: :main, http_client: http_client)
      txid = 'c' * 64

      protocol.call(:is_utxo, txid, 2)

      expect(http_client.last_uri.path).to end_with("/tx/#{txid}/2/spent")
    end

    it 'accepts script_hash: keyword without error' do
      http_client = fake(200, '{"spent":false}')
      protocol = described_class.new(network: :main, http_client: http_client)

      expect { protocol.call(:is_utxo, 'abc', 0, script_hash: 'deadbeef') }.not_to raise_error
    end

    it 'returns Result::NotFound when the txid is unknown' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:is_utxo, 'unknown', 0)

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'error')
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:is_utxo, 'abc', 0)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end

    it 'returns Result::Error when the spent field is absent from the response' do
      http_client = fake(200, '{"something_else":true}')
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:is_utxo, 'abc123', 0)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.message).to include('missing spent field')
    end

    it 'returns Result::Error when the response body is not a Hash' do
      http_client = fake(200, '"just a string"')
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:is_utxo, 'abc123', 0)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.message).to include('missing spent field')
    end
  end

  # ---------------------------------------------------------------------------
  # broadcast — plain text txid response (escape hatch)
  # ---------------------------------------------------------------------------

  describe '#call(:broadcast)' do
    let(:raw_txid) { 'a' * 64 }

    it 'returns a hash with the txid on success' do
      http_client = fake(200, raw_txid)
      protocol = described_class.new(network: :main, http_client: http_client)
      tx = double('tx', to_hex: '01000000') # rubocop:disable RSpec/VerifiedDoubles

      result = protocol.call(:broadcast, tx)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data[:txid]).to eq(raw_txid)
    end

    it 'strips whitespace from the txid response' do
      http_client = fake(200, "#{raw_txid}\n")
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:broadcast, '01000000')

      expect(result.data[:txid]).to eq(raw_txid)
    end

    it 'uses txhex as the body field name' do
      http_client = fake(200, raw_txid)
      protocol = described_class.new(network: :main, http_client: http_client)

      protocol.call(:broadcast, '01000000')

      body = JSON.parse(http_client.last_request.body)
      expect(body).to have_key('txhex')
      expect(body).not_to have_key('rawTx')
    end

    it 'calls to_hex on a transaction object' do
      http_client = fake(200, raw_txid)
      protocol = described_class.new(network: :main, http_client: http_client)
      tx = double('tx', to_hex: 'deadbeef') # rubocop:disable RSpec/VerifiedDoubles

      protocol.call(:broadcast, tx)

      body = JSON.parse(http_client.last_request.body)
      expect(body['txhex']).to eq('deadbeef')
    end

    it 'uses the string directly when tx does not respond to to_hex' do
      http_client = fake(200, raw_txid)
      protocol = described_class.new(network: :main, http_client: http_client)

      protocol.call(:broadcast, 'cafebabe')

      body = JSON.parse(http_client.last_request.body)
      expect(body['txhex']).to eq('cafebabe')
    end

    it 'sends POST to /tx/raw' do
      http_client = fake(200, raw_txid)
      protocol = described_class.new(network: :main, http_client: http_client)

      protocol.call(:broadcast, '01000000')

      expect(http_client.last_uri.path).to end_with('/tx/raw')
      expect(http_client.last_request).to be_a(Net::HTTP::Post)
    end

    it 'returns Result::Error on 400' do
      http_client = fake(400, 'bad request')
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:broadcast, '01000000')

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(false)
    end

    it 'returns Result::Error(retryable: true) on 500' do
      http_client = fake(500, 'server error')
      protocol = described_class.new(network: :main, http_client: http_client)

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
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:valid_root, merkle_root, 800_000)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be(true)
    end

    it 'returns false when the root does not match' do
      http_client = fake(200, header_json)
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:valid_root, 'wrong_root', 800_000)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be(false)
    end

    it 'is case-insensitive in comparison' do
      upper_root = merkle_root.upcase
      http_client = fake(200, { 'merkleroot' => merkle_root.downcase }.to_json)
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:valid_root, upper_root, 800_000)

      expect(result.data).to be(true)
    end

    it 'returns Result::NotFound when the block height is unknown' do
      http_client = fake(404, 'not found')
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:valid_root, merkle_root, 99_999_999)

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end

    it 'returns Result::Error on 500' do
      http_client = fake(500, 'error')
      protocol = described_class.new(network: :main, http_client: http_client)

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
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:get_script_unspent, script_hash)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data.length).to eq(1)
    end

    it 'sends GET to /script/{script_hash}/confirmed/unspent' do
      http_client = fake(200, '[]')
      protocol = described_class.new(network: :main, http_client: http_client)

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
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:get_balance, '1AddressBSV')

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['confirmed']).to eq(50_000)
    end

    it 'sends GET to /address/{address}/confirmed/balance' do
      http_client = fake(200, '{"confirmed":0}')
      protocol = described_class.new(network: :main, http_client: http_client)

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
      protocol = described_class.new(network: :main, http_client: http_client)

      result = protocol.call(:health)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq('Whats On Chain')
    end

    it 'sends GET to /health' do
      http_client = fake(200, 'ok')
      protocol = described_class.new(network: :main, http_client: http_client)

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
      protocol = described_class.new(network: :main, http_client: http_client)

      protocol.call(:get_tx_status, body: '[{"txid":"abc"}]')

      expect(http_client.last_uri.path).to end_with('/txs/status')
      expect(http_client.last_request).to be_a(Net::HTTP::Post)
    end
  end

  # ---------------------------------------------------------------------------
  # API key auth
  # ---------------------------------------------------------------------------

  describe 'API key authentication' do
    it 'sends Bearer auth header when api_key is provided' do
      http_client = fake(200, '{"blocks":800000}')
      protocol = described_class.new(network: :main, api_key: 'my-woc-key', http_client: http_client)

      protocol.call(:current_height)

      expect(http_client.last_request['Authorization']).to eq('Bearer my-woc-key')
    end

    it 'omits Authorization header when api_key is not provided' do
      http_client = fake(200, '{"blocks":800000}')
      protocol = described_class.new(network: :main, http_client: http_client)

      protocol.call(:current_height)

      expect(http_client.last_request['Authorization']).to be_nil
    end
  end
end
