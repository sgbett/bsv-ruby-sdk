# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::Protocols::Ordinals do
  let(:txid) { 'deadbeefcafe0123456789abcdef0123456789abcdef0123456789abcdef0123' }
  let(:address) { '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa' }

  let(:mock_http) do
    Class.new do
      attr_reader :last_uri, :last_request

      def initialize(response)
        @response = response
      end

      def request(uri, req)
        @last_uri     = uri
        @last_request = req
        @response
      end
    end
  end

  def make_instance(code, body, api_key: nil)
    http = mock_http.new(fake_http_response(code, body))
    instance = described_class.new(base_url: 'https://ordinals.gorillapool.io', api_key: api_key, http_client: http)
    [instance, http]
  end

  describe '.commands' do
    it 'returns the correct set of commands' do
      expect(described_class.commands).to eq(
        Set[:get_tx, :get_tx_details, :get_tx_status,
            :get_merkle_path, :get_utxos, :get_balance,
            :get_spend, :get_chain_tip]
      )
    end
  end

  describe ':get_tx' do
    # The API returns binary data; the escape hatch converts to hex.
    let(:raw_bytes) { "\x01\x00\x00\x00\xFF\xFE".b }
    let(:expected_hex) { raw_bytes.unpack1('H*') }

    it 'returns hex string on success' do
      instance, _http = make_instance(200, raw_bytes)
      result = instance.call(:get_tx, txid: txid)

      expect(result).to be_success
      expect(result.data).to eq(expected_hex)
    end

    it 'returns a String' do
      instance, _http = make_instance(200, raw_bytes)
      result = instance.call(:get_tx, txid: txid)

      expect(result.data).to be_a(String)
    end

    it 'builds the correct URL using /raw path' do
      instance, http = make_instance(200, raw_bytes)
      instance.call(:get_tx, txid: txid)

      expect(http.last_uri.to_s).to eq("https://ordinals.gorillapool.io/api/tx/#{txid}/raw")
    end

    it 'accepts txid as a positional argument' do
      instance, http = make_instance(200, raw_bytes)
      instance.call(:get_tx, txid)

      expect(http.last_uri.to_s).to eq("https://ordinals.gorillapool.io/api/tx/#{txid}/raw")
    end

    it 'returns not_found on 404' do
      instance, _http = make_instance(404, 'not found')
      result = instance.call(:get_tx, txid: txid)

      expect(result).to be_not_found
    end
  end

  describe ':get_tx_details' do
    let(:tx_json) { { 'txid' => txid, 'height' => 800_000, 'idx' => 1 }.to_json }

    it 'returns parsed JSON on success' do
      instance, _http = make_instance(200, tx_json)
      result = instance.call(:get_tx_details, txid: txid)

      expect(result).to be_success
      expect(result.data).to be_a(Hash)
      expect(result.data['txid']).to eq(txid)
    end

    it 'builds the correct URL' do
      instance, http = make_instance(200, tx_json)
      instance.call(:get_tx_details, txid: txid)

      expect(http.last_uri.to_s).to eq("https://ordinals.gorillapool.io/api/tx/#{txid}")
    end

    it 'returns not_found on 404' do
      instance, _http = make_instance(404, 'not found')
      result = instance.call(:get_tx_details, txid: txid)

      expect(result).to be_not_found
    end
  end

  describe ':get_tx_status' do
    let(:status_json) { { 'height' => 800_000, 'idx' => 1, 'hash' => 'abc' }.to_json }

    it 'returns parsed JSON on success' do
      instance, _http = make_instance(200, status_json)
      result = instance.call(:get_tx_status, txid: txid)

      expect(result).to be_success
      expect(result.data['height']).to eq(800_000)
    end

    it 'builds the correct URL' do
      instance, http = make_instance(200, status_json)
      instance.call(:get_tx_status, txid: txid)

      expect(http.last_uri.to_s).to eq("https://ordinals.gorillapool.io/api/tx/#{txid}/status")
    end

    it 'returns not_found on 404' do
      instance, _http = make_instance(404, 'not found')
      result = instance.call(:get_tx_status, txid: txid)

      expect(result).to be_not_found
    end
  end

  describe ':get_merkle_path' do
    let(:binary_proof) { "\xDE\xAD\xBE\xEF\x00\x01\x02\x03".b }

    it 'returns raw binary body on success' do
      instance, _http = make_instance(200, binary_proof)
      result = instance.call(:get_merkle_path, txid: txid)

      expect(result).to be_success
      expect(result.data).to eq(binary_proof)
    end

    it 'returns binary data, not a parsed object' do
      instance, _http = make_instance(200, binary_proof)
      result = instance.call(:get_merkle_path, txid: txid)

      expect(result.data).to be_a(String)
    end

    it 'builds the correct URL' do
      instance, http = make_instance(200, binary_proof)
      instance.call(:get_merkle_path, txid: txid)

      expect(http.last_uri.to_s).to eq("https://ordinals.gorillapool.io/api/tx/#{txid}/proof")
    end

    it 'returns not_found on 404' do
      instance, _http = make_instance(404, 'not found')
      result = instance.call(:get_merkle_path, txid: txid)

      expect(result).to be_not_found
    end

    it 'returns error with retryable true on 5xx' do
      instance, _http = make_instance(500, 'internal server error')
      result = instance.call(:get_merkle_path, txid: txid)

      expect(result).to be_error
      expect(result.retryable?).to be(true)
    end
  end

  describe ':get_utxos' do
    let(:utxos_json) do
      [
        { 'txid' => txid, 'vout' => 0, 'satoshis' => 1_000_000 },
        { 'txid' => txid, 'vout' => 1, 'satoshis' => 500_000 }
      ].to_json
    end

    it 'returns parsed JSON array on success' do
      instance, _http = make_instance(200, utxos_json)
      result = instance.call(:get_utxos, address: address)

      expect(result).to be_success
      expect(result.data).to be_a(Array)
      expect(result.data.length).to eq(2)
    end

    it 'builds the correct URL' do
      instance, http = make_instance(200, utxos_json)
      instance.call(:get_utxos, address: address)

      expect(http.last_uri.to_s).to eq("https://ordinals.gorillapool.io/api/txos/address/#{address}/unspent")
    end

    it 'returns not_found on 404' do
      instance, _http = make_instance(404, 'not found')
      result = instance.call(:get_utxos, address: address)

      expect(result).to be_not_found
    end
  end

  describe ':get_balance' do
    # API returns a quoted integer string, e.g. "1000000"
    let(:balance_body) { '"1000000"' }

    it 'returns an Integer on success' do
      instance, _http = make_instance(200, balance_body)
      result = instance.call(:get_balance, address: address)

      expect(result).to be_success
      expect(result.data).to eq(1_000_000)
      expect(result.data).to be_a(Integer)
    end

    it 'builds the correct URL' do
      instance, http = make_instance(200, balance_body)
      instance.call(:get_balance, address: address)

      expect(http.last_uri.to_s).to eq("https://ordinals.gorillapool.io/api/txos/address/#{address}/balance")
    end

    it 'returns not_found on 404' do
      instance, _http = make_instance(404, 'not found')
      result = instance.call(:get_balance, address: address)

      expect(result).to be_not_found
    end
  end

  describe ':get_spend' do
    let(:outpoint) { "#{txid}_0" }

    context 'when unspent' do
      let(:unspent_body) { '""' }

      it 'returns { spent: false }' do
        instance, _http = make_instance(200, unspent_body)
        result = instance.call(:get_spend, outpoint: outpoint)

        expect(result).to be_success
        expect(result.data).to eq({ spent: false })
      end

      it 'builds the correct URL' do
        instance, http = make_instance(200, unspent_body)
        instance.call(:get_spend, outpoint: outpoint)

        expect(http.last_uri.to_s).to eq("https://ordinals.gorillapool.io/api/spends/#{outpoint}")
      end
    end

    context 'when spent' do
      let(:spending_txid) { 'cafebabe0123456789abcdef0123456789abcdef0123456789abcdef01234567' }
      let(:spent_body) { "\"#{spending_txid}\"" }

      it 'returns { spent: true, spending_txid: "..." }' do
        instance, _http = make_instance(200, spent_body)
        result = instance.call(:get_spend, outpoint: outpoint)

        expect(result).to be_success
        expect(result.data).to eq({ spent: true, spending_txid: spending_txid })
      end
    end

    it 'returns not_found on 404' do
      instance, _http = make_instance(404, 'not found')
      result = instance.call(:get_spend, outpoint: outpoint)

      expect(result).to be_not_found
    end
  end

  describe ':get_chain_tip' do
    let(:tip_json) { { 'hash' => 'abc', 'height' => 800_000, 'version' => 1 }.to_json }

    it 'returns parsed JSON on success' do
      instance, _http = make_instance(200, tip_json)
      result = instance.call(:get_chain_tip)

      expect(result).to be_success
      expect(result.data['height']).to eq(800_000)
    end

    it 'builds the correct URL' do
      instance, http = make_instance(200, tip_json)
      instance.call(:get_chain_tip)

      expect(http.last_uri.to_s).to eq('https://ordinals.gorillapool.io/api/blocks/tip')
    end

    it 'returns error with retryable true on 5xx' do
      instance, _http = make_instance(500, 'internal server error')
      result = instance.call(:get_chain_tip)

      expect(result).to be_error
      expect(result.retryable?).to be(true)
    end
  end

  describe 'base_url' do
    let(:raw_bytes) { "\x01\x00\x00\x00".b }

    it 'raises ArgumentError when base_url: is omitted' do
      expect { described_class.new(http_client: mock_http.new(fake_http_response(200, raw_bytes))) }
        .to raise_error(ArgumentError)
    end

    it 'uses the supplied base URL' do
      http = mock_http.new(fake_http_response(200, raw_bytes))
      instance = described_class.new(base_url: 'https://my.ordinals.example', http_client: http)
      expect(instance.base_url).to eq('https://my.ordinals.example')
    end

    it 'uses the supplied base URL when building request URLs' do
      http = mock_http.new(fake_http_response(200, raw_bytes))
      instance = described_class.new(base_url: 'https://my.ordinals.example', http_client: http)
      instance.call(:get_tx, txid)
      expect(http.last_uri.to_s).to start_with('https://my.ordinals.example')
    end
  end

  describe 'authentication' do
    let(:raw_bytes) { "\x01\x00\x00\x00".b }

    it 'sends Authorization: Bearer header when api_key is set' do
      instance, http = make_instance(200, raw_bytes, api_key: 'secret-key')
      instance.call(:get_tx, txid: txid)

      expect(http.last_request['Authorization']).to eq('Bearer secret-key')
    end

    it 'omits Authorization header when api_key is nil' do
      instance, http = make_instance(200, raw_bytes)
      instance.call(:get_tx, txid: txid)

      expect(http.last_request['Authorization']).to be_nil
    end
  end
end
