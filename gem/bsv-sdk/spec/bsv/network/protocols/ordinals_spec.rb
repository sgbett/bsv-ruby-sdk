# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::Protocols::Ordinals do
  let(:txid) { 'deadbeefcafe0123456789abcdef0123456789abcdef0123456789abcdef0123' }

  let(:mock_http) do
    Class.new do
      attr_reader :last_uri, :last_request

      def initialize(code, body)
        @code = code
        @body = body
      end

      def request(uri, req)
        @last_uri     = uri
        @last_request = req
        Struct.new(:code, :body).new(@code.to_s, @body)
      end
    end
  end

  def make_instance(code, body, api_key: nil)
    http = mock_http.new(code, body)
    instance = described_class.new(base_url: 'https://ordinals.gorillapool.io', api_key: api_key, http_client: http)
    [instance, http]
  end

  describe '.commands' do
    it 'returns the correct set of commands' do
      expect(described_class.commands).to eq(Set[:get_tx, :get_merkle_path])
    end
  end

  describe ':get_tx' do
    let(:hex_body) { '01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff' }

    it 'returns raw hex string on success' do
      instance, _http = make_instance(200, hex_body)
      result = instance.call(:get_tx, txid: txid)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq(hex_body)
    end

    it 'returns a String, not a parsed object' do
      instance, _http = make_instance(200, hex_body)
      result = instance.call(:get_tx, txid: txid)

      expect(result.data).to be_a(String)
    end

    it 'builds the correct URL' do
      instance, http = make_instance(200, hex_body)
      instance.call(:get_tx, txid: txid)

      expect(http.last_uri.to_s).to eq("https://ordinals.gorillapool.io/api/tx/#{txid}/hex")
    end

    it 'returns Result::NotFound on 404' do
      instance, _http = make_instance(404, 'not found')
      result = instance.call(:get_tx, txid: txid)

      expect(result).to be_a(BSV::Network::Result::NotFound)
      expect(result.not_found?).to be(true)
    end

    it 'accepts txid as a positional argument' do
      instance, http = make_instance(200, hex_body)
      instance.call(:get_tx, txid)

      expect(http.last_uri.to_s).to eq("https://ordinals.gorillapool.io/api/tx/#{txid}/hex")
    end
  end

  describe ':get_merkle_path' do
    let(:proof_body) do
      { 'index' => 42, 'txOrId' => txid, 'path' => [%w[abc R], %w[def L]] }.to_json
    end

    it 'returns parsed JSON on success' do
      instance, _http = make_instance(200, proof_body)
      result = instance.call(:get_merkle_path, txid: txid)

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_a(Hash)
      expect(result.data['index']).to eq(42)
    end

    it 'builds the correct URL' do
      instance, http = make_instance(200, proof_body)
      instance.call(:get_merkle_path, txid: txid)

      expect(http.last_uri.to_s).to eq("https://ordinals.gorillapool.io/api/tx/#{txid}/proof")
    end

    it 'returns Result::NotFound on 404' do
      instance, _http = make_instance(404, 'not found')
      result = instance.call(:get_merkle_path, txid: txid)

      expect(result).to be_a(BSV::Network::Result::NotFound)
    end

    it 'returns Result::Error with retryable true on 5xx' do
      instance, _http = make_instance(500, 'internal server error')
      result = instance.call(:get_merkle_path, txid: txid)

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end
  end

  describe 'base_url' do
    let(:hex_body) { '01000000' }

    it 'raises ArgumentError when base_url: is omitted' do
      expect { described_class.new(http_client: mock_http.new(200, hex_body)) }
        .to raise_error(ArgumentError)
    end

    it 'uses the supplied base URL' do
      http = mock_http.new(200, hex_body)
      instance = described_class.new(base_url: 'https://my.ordinals.example', http_client: http)
      expect(instance.base_url).to eq('https://my.ordinals.example')
    end

    it 'uses the supplied base URL when building request URLs' do
      http = mock_http.new(200, hex_body)
      instance = described_class.new(base_url: 'https://my.ordinals.example', http_client: http)
      instance.call(:get_tx, txid)
      expect(http.last_uri.to_s).to start_with('https://my.ordinals.example')
    end
  end

  describe 'authentication' do
    let(:hex_body) { '01000000' }

    it 'sends Authorization: Bearer header when api_key is set' do
      instance, http = make_instance(200, hex_body, api_key: 'secret-key')
      instance.call(:get_tx, txid: txid)

      expect(http.last_request['Authorization']).to eq('Bearer secret-key')
    end

    it 'omits Authorization header when api_key is nil' do
      instance, http = make_instance(200, hex_body)
      instance.call(:get_tx, txid: txid)

      expect(http.last_request['Authorization']).to be_nil
    end
  end
end
