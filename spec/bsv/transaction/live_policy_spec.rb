# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Transaction::FeeModels::LivePolicy do
  let(:arc_url) { 'https://arc.example.com' }

  # Mock HTTP client that returns a configurable response
  let(:mock_client) do
    Class.new do
      attr_accessor :response_code, :response_body, :call_count

      def initialize(code, body)
        @response_code = code
        @response_body = body
        @call_count = 0
      end

      def request(_uri, _request)
        @call_count += 1
        response = Struct.new(:code, :body).new
        response.code = @response_code.to_s
        response.body = @response_body
        response
      end
    end
  end

  let(:policy_response) do
    {
      'policy' => {
        'fees' => {
          'miningFee' => { 'satoshis' => 50, 'bytes' => 1000 }
        }
      }
    }.to_json
  end

  let(:http) { mock_client.new(200, policy_response) }

  let(:model) do
    described_class.new(arc_url: arc_url, http_client: http, cache_ttl: 60)
  end

  describe '#current_rate' do
    it 'fetches the rate from the ARC policy endpoint' do
      expect(model.current_rate).to eq(50)
      expect(http.call_count).to eq(1)
    end

    it 'parses policy.fees.miningFee with satoshis/bytes' do
      body = { 'policy' => { 'fees' => { 'miningFee' => { 'satoshis' => 100, 'bytes' => 1000 } } } }.to_json
      h = mock_client.new(200, body)
      m = described_class.new(arc_url: arc_url, http_client: h)
      expect(m.current_rate).to eq(100)
    end

    it 'parses policy.miningFee directly' do
      body = { 'policy' => { 'miningFee' => { 'satoshis' => 25, 'bytes' => 1000 } } }.to_json
      h = mock_client.new(200, body)
      m = described_class.new(arc_url: arc_url, http_client: h)
      expect(m.current_rate).to eq(25)
    end

    it 'parses policy.satPerKb fallback' do
      body = { 'policy' => { 'satPerKb' => 75 } }.to_json
      h = mock_client.new(200, body)
      m = described_class.new(arc_url: arc_url, http_client: h)
      expect(m.current_rate).to eq(75)
    end

    it 'unwraps a data envelope' do
      body = { 'data' => { 'policy' => { 'satPerKb' => 42 } } }.to_json
      h = mock_client.new(200, body)
      m = described_class.new(arc_url: arc_url, http_client: h)
      expect(m.current_rate).to eq(42)
    end

    it 'ensures minimum rate of 1 sat/kB' do
      body = { 'policy' => { 'fees' => { 'miningFee' => { 'satoshis' => 1, 'bytes' => 100_000 } } } }.to_json
      h = mock_client.new(200, body)
      m = described_class.new(arc_url: arc_url, http_client: h)
      expect(m.current_rate).to eq(1)
    end
  end

  describe 'caching' do
    it 'does not re-fetch while cache is valid' do
      model.current_rate
      model.current_rate
      model.current_rate
      expect(http.call_count).to eq(1)
    end

    it 're-fetches after cache expires' do
      m = described_class.new(arc_url: arc_url, http_client: http, cache_ttl: 0)
      m.current_rate
      m.current_rate
      expect(http.call_count).to eq(2)
    end
  end

  describe 'fallback' do
    it 'returns fallback rate on HTTP error' do
      h = mock_client.new(500, 'Internal Server Error')
      m = described_class.new(arc_url: arc_url, http_client: h, fallback_rate: 99)
      expect(m.current_rate).to eq(99)
    end

    it 'returns fallback rate on invalid JSON' do
      h = mock_client.new(200, 'not json')
      m = described_class.new(arc_url: arc_url, http_client: h, fallback_rate: 77)
      expect(m.current_rate).to eq(77)
    end

    it 'returns fallback rate on missing policy key' do
      h = mock_client.new(200, { 'something' => 'else' }.to_json)
      m = described_class.new(arc_url: arc_url, http_client: h, fallback_rate: 55)
      expect(m.current_rate).to eq(55)
    end

    it 'returns stale cached rate over fallback when fetch fails' do
      m = described_class.new(arc_url: arc_url, http_client: http, cache_ttl: 0, fallback_rate: 1)
      expect(m.current_rate).to eq(50) # first fetch succeeds

      # Now make the endpoint fail
      http.response_code = 500
      http.response_body = 'error'
      expect(m.current_rate).to eq(50) # returns stale cached value
    end
  end

  describe '#compute_fee' do
    it 'computes fee using the live rate' do
      tx = instance_double(BSV::Transaction::Transaction, estimated_size: 250)
      fee = model.compute_fee(tx)
      # 250 / 1000 * 50 = 12.5, ceil = 13
      expect(fee).to eq(13)
    end
  end

  describe 'api_key' do
    it 'includes Authorization header when api_key is set' do
      # Use a recording client to verify headers
      recording_client = Class.new do
        define_method(:initialize) { |reqs| @reqs = reqs }
        define_method(:request) do |_uri, req|
          @reqs << req
          Struct.new(:code, :body).new('200', policy_response)
        end
      end

      reqs = []
      h = recording_client.new(reqs)
      m = described_class.new(arc_url: arc_url, http_client: h, api_key: 'test-key')
      m.current_rate

      expect(reqs.first['Authorization']).to eq('Bearer test-key')
    end
  end
end
