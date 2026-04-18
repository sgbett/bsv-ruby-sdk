# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::Network::Protocols::TAALBinary' do
  let(:described_class) { BSV::Network::Protocols::TAALBinary }

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

  def make_instance(code, body, api_key: 'mainnet_test_key')
    http     = mock_http.new(code, body)
    instance = described_class.new(
      base_url: 'https://api.taal.com',
      api_key: api_key,
      http_client: http
    )
    [instance, http]
  end

  describe '.commands' do
    it 'returns Set[:broadcast]' do
      expect(described_class.commands).to eq(Set[:broadcast])
    end
  end

  describe ':broadcast — success' do
    let(:success_body) { { 'txid' => 'deadbeef' * 8 }.to_json }

    it 'returns Result::Success with txid on 200' do
      instance, _http = make_instance(200, success_body)
      result = instance.call(:broadcast, "\x01\x00")

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data[:txid]).to eq('deadbeef' * 8)
    end

    it 'sends raw binary body as-is when given a String' do
      instance, http = make_instance(200, success_body)
      instance.call(:broadcast, "\xde\xad\xbe\xef")

      expect(http.last_request.body).to eq("\xde\xad\xbe\xef")
    end

    it 'calls #to_binary on a transaction object' do
      tx = double('tx') # rubocop:disable RSpec/VerifiedDoubles
      allow(tx).to receive(:respond_to?).with(:to_binary).and_return(true)
      allow(tx).to receive(:to_binary).and_return("\xca\xfe")

      instance, http = make_instance(200, success_body)
      instance.call(:broadcast, tx)

      expect(http.last_request.body).to eq("\xca\xfe")
    end
  end

  describe ':broadcast — Content-Type header' do
    let(:success_body) { { 'txid' => 'abc123' }.to_json }

    it 'sets Content-Type to application/octet-stream' do
      instance, http = make_instance(200, success_body)
      instance.call(:broadcast, "\x00")

      expect(http.last_request.content_type).to eq('application/octet-stream')
    end
  end

  describe ':broadcast — Authorization header' do
    let(:success_body) { { 'txid' => 'abc123' }.to_json }

    it 'sends the API key directly with no Bearer prefix' do
      instance, http = make_instance(200, success_body, api_key: 'mainnet_secret')
      instance.call(:broadcast, "\x00")

      expect(http.last_request['Authorization']).to eq('mainnet_secret')
    end

    it 'does not include "Bearer" in the header' do
      instance, http = make_instance(200, success_body, api_key: 'mykey')
      instance.call(:broadcast, "\x00")

      expect(http.last_request['Authorization']).not_to include('Bearer')
    end

    it 'omits Authorization header when api_key is nil' do
      instance, http = make_instance(200, success_body, api_key: nil)
      instance.call(:broadcast, "\x00")

      expect(http.last_request['Authorization']).to be_nil
    end
  end

  describe ':broadcast — txn-already-known quirk' do
    it 'treats txn-already-known error as Result::Success' do
      body = { 'txid' => 'abc123', 'error' => 'txn-already-known' }.to_json
      instance, _http = make_instance(400, body)
      result = instance.call(:broadcast, "\x00")

      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data[:txid]).to eq('abc123')
    end

    it 'treats txn-already-known in a 409 response as success' do
      body = { 'txid' => 'def456', 'error' => 'txn-already-known' }.to_json
      instance, _http = make_instance(409, body)
      result = instance.call(:broadcast, "\x00")

      expect(result).to be_a(BSV::Network::Result::Success)
    end

    it 'treats txn-already-known even when embedded in a longer error string' do
      body = { 'txid' => 'def456', 'error' => 'error: txn-already-known in mempool' }.to_json
      instance, _http = make_instance(400, body)
      result = instance.call(:broadcast, "\x00")

      expect(result).to be_a(BSV::Network::Result::Success)
    end
  end

  describe ':broadcast — error responses' do
    it 'returns Result::Error with the error field as message on 4xx' do
      body = { 'error' => 'txn-invalid-script' }.to_json
      instance, _http = make_instance(400, body)
      result = instance.call(:broadcast, "\x00")

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.message).to eq('txn-invalid-script')
    end

    it 'falls back to HTTP status message when no error field' do
      instance, _http = make_instance(400, '{}')
      result = instance.call(:broadcast, "\x00")

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.message).to eq('HTTP 400')
    end

    it 'returns retryable: false for 4xx errors' do
      body = { 'error' => 'bad input' }.to_json
      instance, _http = make_instance(400, body)
      result = instance.call(:broadcast, "\x00")

      expect(result.retryable?).to be(false)
    end

    it 'returns retryable: true for 429 responses' do
      instance, _http = make_instance(429, '{"error":"rate limited"}')
      result = instance.call(:broadcast, "\x00")

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end

    it 'returns retryable: true for 5xx responses' do
      instance, _http = make_instance(500, '{"error":"internal error"}')
      result = instance.call(:broadcast, "\x00")

      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end
  end

  describe ':broadcast — URL' do
    let(:success_body) { { 'txid' => 'abc123' }.to_json }

    it 'posts to /api/v1/broadcast' do
      instance, http = make_instance(200, success_body)
      instance.call(:broadcast, "\x00")

      expect(http.last_uri.to_s).to eq('https://api.taal.com/api/v1/broadcast')
    end
  end
end
