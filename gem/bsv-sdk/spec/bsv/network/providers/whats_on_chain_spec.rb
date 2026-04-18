# frozen_string_literal: true

RSpec.describe 'BSV::Network::Providers::WhatsOnChain' do
  require 'spec_helper'

  subject(:provider) { BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: mock_http) }

  # Minimal mock HTTP client — stores the last request for inspection.
  let(:mock_http_class) do
    Class.new do
      attr_reader :last_uri, :last_request

      def initialize(code, body)
        @code = code
        @body = body
      end

      def request(uri, req)
        @last_uri = uri
        @last_request = req
        Struct.new(:code, :body).new(@code.to_s, @body)
      end
    end
  end

  let(:mock_http) { mock_http_class.new(200, '{}') }

  def http_stub(code, body)
    mock_http_class.new(code, body)
  end

  # ---------------------------------------------------------------------------
  # Shared examples
  # ---------------------------------------------------------------------------

  shared_examples 'retryable on 429' do |command, *args|
    it 'returns retryable error on HTTP 429' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(429, 'Rate limited'))
      result = p.call(command, *args)
      expect(result).to be_error
      expect(result.retryable?).to be true
    end
  end

  shared_examples 'retryable on 500' do |command, *args|
    it 'returns retryable error on HTTP 500' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(500, 'Server error'))
      result = p.call(command, *args)
      expect(result).to be_error
      expect(result.retryable?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Capabilities
  # ---------------------------------------------------------------------------

  describe '.capabilities' do
    it 'includes the four core commands' do
      expect(BSV::Network::Providers::WhatsOnChain.capabilities).to include(:get_tx, :get_utxos, :current_height, :valid_root)
    end
  end

  # ---------------------------------------------------------------------------
  # Constructor
  # ---------------------------------------------------------------------------

  describe '#initialize' do
    it 'accepts :main network' do
      expect { BSV::Network::Providers::WhatsOnChain.new(network: :main) }.not_to raise_error
    end

    it 'accepts :mainnet as an alias for :main' do
      expect { BSV::Network::Providers::WhatsOnChain.new(network: :mainnet) }.not_to raise_error
    end

    it 'accepts :test network' do
      expect { BSV::Network::Providers::WhatsOnChain.new(network: :test) }.not_to raise_error
    end

    it 'accepts :testnet as an alias for :test' do
      expect { BSV::Network::Providers::WhatsOnChain.new(network: :testnet) }.not_to raise_error
    end

    it 'accepts :stn network' do
      expect { BSV::Network::Providers::WhatsOnChain.new(network: :stn) }.not_to raise_error
    end

    it 'raises ArgumentError for unknown network' do
      expect { BSV::Network::Providers::WhatsOnChain.new(network: :regtest) }.to raise_error(ArgumentError, /unknown network/)
    end
  end

  # ---------------------------------------------------------------------------
  # API key header
  # ---------------------------------------------------------------------------

  describe 'API key header' do
    let(:txid) { 'abc123' }

    it 'sends Authorization header when api_key is provided' do
      http = http_stub(200, 'deadbeef')
      BSV::Network::Providers::WhatsOnChain.new(network: :main, api_key: 'my-key', http_client: http)
                                           .call(:get_tx, txid)
      expect(http.last_request['Authorization']).to eq('my-key')
    end

    it 'omits Authorization header when api_key is nil' do
      http = http_stub(200, 'deadbeef')
      BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http)
                                           .call(:get_tx, txid)
      expect(http.last_request['Authorization']).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # :get_tx
  # ---------------------------------------------------------------------------

  describe '#call_get_tx' do
    let(:txid) { 'f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16' }
    let(:hex_body) { 'deadbeef01020304' }

    it 'returns success with raw hex string on 200' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, hex_body))
      result = p.call(:get_tx, txid)
      expect(result).to be_success
      expect(result.data).to eq(hex_body)
    end

    it 'strips whitespace from the hex response' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, "#{hex_body}\n"))
      result = p.call(:get_tx, txid)
      expect(result.data).to eq(hex_body)
    end

    it 'returns not_found on HTTP 404' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(404, 'Not found'))
      result = p.call(:get_tx, txid)
      expect(result).to be_not_found
    end

    it 'sends GET to the correct mainnet URL' do
      http = http_stub(200, hex_body)
      BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http).call(:get_tx, txid)
      expect(http.last_uri.to_s).to eq("https://api.whatsonchain.com/v1/bsv/main/tx/#{txid}/hex")
    end

    it 'sends GET to the correct testnet URL when network is :test' do
      http = http_stub(200, hex_body)
      BSV::Network::Providers::WhatsOnChain.new(network: :test, http_client: http).call(:get_tx, txid)
      expect(http.last_uri.to_s).to include('/v1/bsv/test/')
    end

    it_behaves_like 'retryable on 429', :get_tx, 'abc123'
    it_behaves_like 'retryable on 500', :get_tx, 'abc123'

    it 'returns non-retryable error on HTTP 400' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(400, 'Bad request'))
      result = p.call(:get_tx, txid)
      expect(result).to be_error
      expect(result.retryable?).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # :get_utxos
  # ---------------------------------------------------------------------------

  describe '#call_get_utxos' do
    let(:address) { '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa' }
    let(:utxo_body) do
      [
        { 'tx_hash' => 'aabb11', 'tx_pos' => 0, 'value' => 50_000, 'height' => 800_000 },
        { 'tx_hash' => 'ccdd22', 'tx_pos' => 1, 'value' => 25_000, 'height' => 0 }
      ].to_json
    end

    it 'returns success with array of UTXO hashes on 200' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, utxo_body))
      result = p.call(:get_utxos, address)
      expect(result).to be_success
      expect(result.data.length).to eq(2)
    end

    it 'maps WoC "value" field to :satoshis' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, utxo_body))
      result = p.call(:get_utxos, address)
      first = result.data.first
      expect(first[:tx_hash]).to eq('aabb11')
      expect(first[:tx_pos]).to eq(0)
      expect(first[:satoshis]).to eq(50_000)
      expect(first[:height]).to eq(800_000)
    end

    it 'returns success with empty array on 404' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(404, ''))
      result = p.call(:get_utxos, address)
      expect(result).to be_success
      expect(result.data).to eq([])
    end

    it 'returns success with empty array when response body is "[]"' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, '[]'))
      result = p.call(:get_utxos, address)
      expect(result).to be_success
      expect(result.data).to eq([])
    end

    it 'sends GET to the correct URL' do
      http = http_stub(200, utxo_body)
      BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http).call(:get_utxos, address)
      expect(http.last_uri.to_s).to eq("https://api.whatsonchain.com/v1/bsv/main/address/#{address}/unspent")
    end

    it 'returns non-retryable error on malformed JSON' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, 'not-json'))
      result = p.call(:get_utxos, address)
      expect(result).to be_error
      expect(result.retryable?).to be false
    end

    it_behaves_like 'retryable on 429', :get_utxos, '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa'
    it_behaves_like 'retryable on 500', :get_utxos, '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa'
  end

  # ---------------------------------------------------------------------------
  # :current_height
  # ---------------------------------------------------------------------------

  describe '#call_current_height' do
    let(:chain_info_body) { '{"blocks":850123,"headers":850123,"bestblockhash":"abc"}' }

    it 'returns success with integer block height on 200' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, chain_info_body))
      result = p.call(:current_height)
      expect(result).to be_success
      expect(result.data).to eq(850_123)
    end

    it 'sends GET to the correct URL' do
      http = http_stub(200, chain_info_body)
      BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http).call(:current_height)
      expect(http.last_uri.to_s).to eq('https://api.whatsonchain.com/v1/bsv/main/chain/info')
    end

    it 'returns non-retryable error when "blocks" field is missing' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, '{"headers":100}'))
      result = p.call(:current_height)
      expect(result).to be_error
      expect(result.retryable?).to be false
    end

    it 'returns non-retryable error on malformed JSON' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, 'bad json'))
      result = p.call(:current_height)
      expect(result).to be_error
      expect(result.retryable?).to be false
    end

    it_behaves_like 'retryable on 429', :current_height
    it_behaves_like 'retryable on 500', :current_height
  end

  # ---------------------------------------------------------------------------
  # :valid_root
  # ---------------------------------------------------------------------------

  describe '#call_valid_root' do
    let(:height) { 800_000 }
    let(:merkle_root) { 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890' }
    let(:header_body) { { 'merkleroot' => merkle_root, 'hash' => 'blockhashabc' }.to_json }

    it 'returns success(true) when merkle roots match' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, header_body))
      result = p.call(:valid_root, merkle_root, height)
      expect(result).to be_success
      expect(result.data).to be true
    end

    it 'returns success(false) when merkle roots do not match' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, header_body))
      result = p.call(:valid_root, 'aaaa0000', height)
      expect(result).to be_success
      expect(result.data).to be false
    end

    it 'performs case-insensitive comparison' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, header_body))
      result = p.call(:valid_root, merkle_root.upcase, height)
      expect(result).to be_success
      expect(result.data).to be true
    end

    it 'returns not_found on HTTP 404' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(404, ''))
      result = p.call(:valid_root, merkle_root, height)
      expect(result).to be_not_found
    end

    it 'handles block height 0 (genesis)' do
      genesis_root = '4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b'
      body = { 'merkleroot' => genesis_root }.to_json
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, body))
      result = p.call(:valid_root, genesis_root, 0)
      expect(result).to be_success
      expect(result.data).to be true
    end

    it 'sends GET to the correct URL including block height' do
      http = http_stub(200, header_body)
      BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http).call(:valid_root, merkle_root, height)
      expect(http.last_uri.to_s).to eq("https://api.whatsonchain.com/v1/bsv/main/block/#{height}/header")
    end

    it 'returns non-retryable error when "merkleroot" field is missing' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, '{"hash":"abc"}'))
      result = p.call(:valid_root, merkle_root, height)
      expect(result).to be_error
      expect(result.retryable?).to be false
    end

    it 'returns non-retryable error on malformed JSON' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, 'bad json'))
      result = p.call(:valid_root, merkle_root, height)
      expect(result).to be_error
      expect(result.retryable?).to be false
    end

    it_behaves_like 'retryable on 429', :valid_root, 'root', 100
    it_behaves_like 'retryable on 500', :valid_root, 'root', 100
  end

  # ---------------------------------------------------------------------------
  # Network URL selection
  # ---------------------------------------------------------------------------

  describe 'network URL selection' do
    let(:txid) { 'abc123' }

    { main: 'main', mainnet: 'main', test: 'test', testnet: 'test', stn: 'stn' }.each do |sym, segment|
      it "maps :#{sym} to '#{segment}' in URL" do
        http = http_stub(200, 'hex')
        BSV::Network::Providers::WhatsOnChain.new(network: sym, http_client: http).call(:get_tx, txid)
        expect(http.last_uri.to_s).to include("/v1/bsv/#{segment}/")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # .capabilities (extended)
  # ---------------------------------------------------------------------------

  describe '.capabilities (extended)' do
    it 'includes the three advanced commands' do
      caps = BSV::Network::Providers::WhatsOnChain.capabilities
      expect(caps).to include(:is_utxo, :get_merkle_path, :get_script_unspent)
    end
  end

  # ---------------------------------------------------------------------------
  # :get_script_unspent
  # ---------------------------------------------------------------------------

  describe '#call_get_script_unspent' do
    let(:script_hash) { 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890' }
    let(:unspent_body) do
      [
        { 'tx_hash' => 'aabb11', 'tx_pos' => 0, 'value' => 10_000, 'height' => 800_000 },
        { 'tx_hash' => 'ccdd22', 'tx_pos' => 2, 'value' => 5_000,  'height' => 800_001 }
      ].to_json
    end

    it 'returns success with array of UTXO hashes on 200' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, unspent_body))
      result = p.call(:get_script_unspent, script_hash)
      expect(result).to be_success
      expect(result.data.length).to eq(2)
    end

    it 'maps fields correctly including value -> satoshis' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, unspent_body))
      result = p.call(:get_script_unspent, script_hash)
      first = result.data.first
      expect(first[:tx_hash]).to eq('aabb11')
      expect(first[:tx_pos]).to eq(0)
      expect(first[:satoshis]).to eq(10_000)
      expect(first[:height]).to eq(800_000)
    end

    it 'returns success with empty array when result is empty' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, '[]'))
      result = p.call(:get_script_unspent, script_hash)
      expect(result).to be_success
      expect(result.data).to eq([])
    end

    it 'returns success with empty array on 404' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(404, ''))
      result = p.call(:get_script_unspent, script_hash)
      expect(result).to be_success
      expect(result.data).to eq([])
    end

    it 'sends GET to the correct URL' do
      http = http_stub(200, unspent_body)
      BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http)
                                           .call(:get_script_unspent, script_hash)
      expect(http.last_uri.to_s).to eq("https://api.whatsonchain.com/v1/bsv/main/script/#{script_hash}/unspent")
    end

    it 'returns non-retryable error on malformed JSON' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, 'not-json'))
      result = p.call(:get_script_unspent, script_hash)
      expect(result).to be_error
      expect(result.retryable?).to be false
    end

    it_behaves_like 'retryable on 429', :get_script_unspent, 'deadbeef'
    it_behaves_like 'retryable on 500', :get_script_unspent, 'deadbeef'
  end

  # ---------------------------------------------------------------------------
  # :is_utxo
  # ---------------------------------------------------------------------------

  describe '#call_is_utxo' do
    let(:txid) { 'f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16' }
    let(:vout) { 0 }
    let(:script_hash) { 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890' }
    let(:unspent_body_with_match) do
      [{ 'tx_hash' => txid, 'tx_pos' => vout, 'value' => 5_000, 'height' => 800_000 }].to_json
    end
    let(:unspent_body_without_match) do
      [{ 'tx_hash' => 'othertx', 'tx_pos' => 0, 'value' => 1_000, 'height' => 800_000 }].to_json
    end

    context 'with script_hash: provided (single-call path)' do
      it 'returns success(true) when outpoint is in unspent set' do
        p = BSV::Network::Providers::WhatsOnChain.new(network: :main,
                                                      http_client: http_stub(200, unspent_body_with_match))
        result = p.call(:is_utxo, txid, vout, script_hash: script_hash)
        expect(result).to be_success
        expect(result.data).to be true
      end

      it 'returns success(false) when outpoint is not in unspent set (spent)' do
        p = BSV::Network::Providers::WhatsOnChain.new(network: :main,
                                                      http_client: http_stub(200, unspent_body_without_match))
        result = p.call(:is_utxo, txid, vout, script_hash: script_hash)
        expect(result).to be_success
        expect(result.data).to be false
      end

      it 'returns success(false) when unspent set is empty' do
        p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, '[]'))
        result = p.call(:is_utxo, txid, vout, script_hash: script_hash)
        expect(result).to be_success
        expect(result.data).to be false
      end

      it 'returns success(false) when outpoint tx_pos does not match' do
        body = [{ 'tx_hash' => txid, 'tx_pos' => 1, 'value' => 1_000, 'height' => 0 }].to_json
        p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, body))
        result = p.call(:is_utxo, txid, vout, script_hash: script_hash)
        expect(result).to be_success
        expect(result.data).to be false
      end

      it 'returns retryable error on HTTP 429' do
        p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(429, 'Rate limited'))
        result = p.call(:is_utxo, txid, vout, script_hash: script_hash)
        expect(result).to be_error
        expect(result.retryable?).to be true
      end

      it 'returns retryable error on HTTP 500' do
        p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(500, 'Server error'))
        result = p.call(:is_utxo, txid, vout, script_hash: script_hash)
        expect(result).to be_error
        expect(result.retryable?).to be true
      end
    end

    context 'without script_hash: (two-call fallback)' do
      # Minimal valid P2PKH transaction serialised in raw hex.
      # Built to exercise the fallback path: get_tx -> parse -> compute hash -> get_script_unspent.
      let(:real_txid) { 'f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16' }

      # Build a minimal raw transaction with a single P2PKH output so we can
      # compute the expected script hash without pulling in the full SDK stack here.
      let(:locking_script_hex) do
        # OP_DUP OP_HASH160 <20-byte hash> OP_EQUALVERIFY OP_CHECKSIG
        "76a914#{'aa' * 20}88ac"
      end

      let(:raw_tx_hex) do
        # version (4 LE) | input count (varint) | ... | output count | value (8 LE) | script len | script | locktime
        version = '01000000'
        # one input: prev hash (32), prev index (4), script len (0), sequence (4)
        inputs = "01#{'00' * 32}ffffffff00ffffffff"
        # one output: value (8 LE) = 5000 sat, script
        script_bytes = [locking_script_hex].pack('H*')
        value_le = [5000].pack('Q<').unpack1('H*')
        script_len = [script_bytes.bytesize].pack('C').unpack1('H*')
        outputs = "01#{value_le}#{script_len}#{locking_script_hex}"
        locktime = '00000000'
        version + inputs + outputs + locktime
      end

      let(:expected_script_hash) do
        script_bytes = [locking_script_hex].pack('H*')
        digest = OpenSSL::Digest::SHA256.digest(script_bytes)
        digest.reverse.unpack1('H*')
      end

      it 'makes two HTTP calls: one for tx hex, one for script unspent' do
        call_count = 0
        responses = [
          Struct.new(:code, :body).new('200', raw_tx_hex),
          Struct.new(:code, :body).new('200', unspent_body_with_match)
        ]

        multi_http = Class.new do
          define_method(:request) do |_uri, _req|
            call_count += 1
            responses[call_count - 1]
          end
        end.new

        p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: multi_http)
        result = p.call(:is_utxo, real_txid, vout)
        expect(result).to be_success
        expect(call_count).to eq(2)
      end

      it 'returns success(true) when outpoint is found in unspent set' do
        call_count = 0
        responses = [
          Struct.new(:code, :body).new('200', raw_tx_hex),
          Struct.new(:code, :body).new('200', unspent_body_with_match)
        ]

        multi_http = Class.new do
          define_method(:request) do |_uri, _req|
            call_count += 1
            responses[call_count - 1]
          end
        end.new

        p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: multi_http)
        result = p.call(:is_utxo, real_txid, vout)
        expect(result).to be_success
        expect(result.data).to be true
      end

      it 'returns success(false) when outpoint is not in unspent set' do
        call_count = 0
        responses = [
          Struct.new(:code, :body).new('200', raw_tx_hex),
          Struct.new(:code, :body).new('200', '[]')
        ]

        multi_http = Class.new do
          define_method(:request) do |_uri, _req|
            call_count += 1
            responses[call_count - 1]
          end
        end.new

        p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: multi_http)
        result = p.call(:is_utxo, real_txid, vout)
        expect(result).to be_success
        expect(result.data).to be false
      end

      it 'returns not_found when the tx itself is not found (404 on hex fetch)' do
        p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(404, 'Not found'))
        result = p.call(:is_utxo, real_txid, vout)
        expect(result).to be_not_found
      end

      it 'returns non-retryable error when vout is beyond output count' do
        call_count = 0
        responses = [
          Struct.new(:code, :body).new('200', raw_tx_hex),
          Struct.new(:code, :body).new('200', '[]')
        ]

        multi_http = Class.new do
          define_method(:request) do |_uri, _req|
            call_count += 1
            responses[call_count - 1]
          end
        end.new

        p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: multi_http)
        result = p.call(:is_utxo, real_txid, 99)
        expect(result).to be_error
        expect(result.retryable?).to be false
      end
    end
  end

  # ---------------------------------------------------------------------------
  # :get_merkle_path
  # ---------------------------------------------------------------------------

  describe '#call_get_merkle_path' do
    let(:txid) { 'f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16' }
    let(:tsc_body) do
      [{
        'index' => 3,
        'txOrId' => txid,
        'target' => 'blockhashdeadbeef',
        'nodes' => %w[node1 node2 node3]
      }].to_json
    end

    it 'returns success with normalised TSC proof hash on 200' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, tsc_body))
      result = p.call(:get_merkle_path, txid)
      expect(result).to be_success
      expect(result.data[:index]).to eq(3)
      expect(result.data[:tx_or_id]).to eq(txid)
      expect(result.data[:target]).to eq('blockhashdeadbeef')
      expect(result.data[:nodes]).to eq(%w[node1 node2 node3])
    end

    it 'takes the first element when WoC returns multiple proofs in the array' do
      body = [
        { 'index' => 1, 'txOrId' => txid, 'target' => 'first',  'nodes' => [] },
        { 'index' => 2, 'txOrId' => txid, 'target' => 'second', 'nodes' => [] }
      ].to_json
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, body))
      result = p.call(:get_merkle_path, txid)
      expect(result).to be_success
      expect(result.data[:target]).to eq('first')
    end

    it 'returns not_found when WoC returns null (unconfirmed transaction)' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, 'null'))
      result = p.call(:get_merkle_path, txid)
      expect(result).to be_not_found
    end

    it 'returns not_found on HTTP 404' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(404, 'Not found'))
      result = p.call(:get_merkle_path, txid)
      expect(result).to be_not_found
    end

    it 'sends GET to the correct URL' do
      http = http_stub(200, tsc_body)
      BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http)
                                           .call(:get_merkle_path, txid)
      expect(http.last_uri.to_s).to eq("https://api.whatsonchain.com/v1/bsv/main/tx/#{txid}/proof/tsc")
    end

    it 'returns non-retryable error on malformed JSON' do
      p = BSV::Network::Providers::WhatsOnChain.new(network: :main, http_client: http_stub(200, 'bad json'))
      result = p.call(:get_merkle_path, txid)
      expect(result).to be_error
      expect(result.retryable?).to be false
    end

    it_behaves_like 'retryable on 429', :get_merkle_path, 'txid'
    it_behaves_like 'retryable on 500', :get_merkle_path, 'txid'
  end
end
