# frozen_string_literal: true

require 'spec_helper'
require 'pp'

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
        FakeHttpResponse.fake_http_response(@response_code, @response_body)
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
      body = { 'policy' => { 'fees' => { 'miningFee' => { 'satoshis' => 60, 'bytes' => 1000 } } } }.to_json
      h = mock_client.new(200, body)
      m = described_class.new(arc_url: arc_url, http_client: h)
      expect(m.current_rate).to eq(60)
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

  describe 'policy validation' do
    def rate_for(policy, fallback: 7)
      client = mock_client.new(200, { 'policy' => policy }.to_json)
      described_class.new(arc_url: arc_url, http_client: client, fallback_rate: fallback).current_rate
    end

    def mining_fee(satoshis, bytes)
      { 'miningFee' => { 'satoshis' => satoshis, 'bytes' => bytes } }
    end

    it 'scales the rate to sat/kB' do
      expect(rate_for(mining_fee(50, 500))).to eq(100)
    end

    it 'accepts a rate of exactly 1_000_000_000 sat/kB' do
      expect(rate_for(mining_fee(1_000_000, 1))).to eq(1_000_000_000)
    end

    it 'accepts whole-number JSON floats, as the TypeScript SDK does' do
      expect(rate_for(mining_fee(200.0, 1000.0))).to eq(200)
    end

    {
      'zero satoshis' => [0, 1000],
      'fractional satoshis' => [0.5, 1000],
      'huge satoshis' => [10**30, 1000],
      'satoshis above 21e14' => [2_100_000_000_000_001, 1_000_000_000],
      'string satoshis' => ['50', 1000],
      'zero bytes' => [50, 0],
      'tiny float bytes' => [50, 1e-300],
      'bytes above 1e9' => [50, 1_000_000_001],
      'rate above 1e9 sat/kB' => [1_000_001, 1]
    }.each do |label, (satoshis, bytes)|
      it "falls back for #{label}" do
        expect(rate_for(mining_fee(satoshis, bytes))).to eq(7)
      end
    end

    it 'falls back for a satPerKb of 5e9' do
      expect(rate_for({ 'satPerKb' => 5_000_000_000 })).to eq(7)
    end

    it 'falls back for a zero satPerKb' do
      expect(rate_for({ 'satPerKb' => 0 })).to eq(7)
    end

    it 'keeps the cached rate over the fallback when a later policy is invalid' do
      m = described_class.new(arc_url: arc_url, http_client: http, cache_ttl: 0, fallback_rate: 1)
      expect(m.current_rate).to eq(50)

      http.response_body = { 'policy' => mining_fee(0, 1000) }.to_json
      expect(m.current_rate).to eq(50)
    end
  end

  describe 'request shape' do
    let(:recorder) { stub_net_http('arc.gorillapool.io' => ->(_req) { [200, policy_response] }) }

    it '.default targets GorillaPool' do
      expect(described_class.default.arc_url).to eq('https://arc.gorillapool.io')
    end

    it '.default sends one unauthenticated GET to /v1/policy' do
      recorder
      expect(described_class.default.current_rate).to eq(50)

      expect(recorder.entries.map(&:path)).to eq(['/v1/policy'])
      expect(recorder.entries.first.request).to be_a(Net::HTTP::Get)
      expect(recorder.authorisation_for('arc.gorillapool.io')).to eq([nil])
    end

    it '.default no longer accepts an api_key' do
      expect { described_class.default(api_key: 'x') }.to raise_error(ArgumentError)
    end
  end

  describe '#inspect' do
    let(:keyed) { described_class.new(arc_url: 'https://arc.example.com/', api_key: 'SEKRET', http_client: http) }

    it 'shows scheme, host, fallback rate and cache TTL' do
      expected = '#<BSV::Transaction::FeeModels::LivePolicy scheme="https" host="arc.example.com" fallback_rate=100 cache_ttl=300>'
      expect(keyed.inspect).to eq(expected)
    end

    it 'never shows the api_key via inspect, to_s or pp' do
      keyed.current_rate

      expect(keyed.inspect).not_to include('SEKRET')
      expect(keyed.to_s).not_to include('SEKRET')
      expect(PP.pp(keyed, +'')).not_to include('SEKRET')
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
      tx = instance_double(BSV::Transaction::Tx, estimated_size: 250)
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
          FakeHttpResponse.fake_http_response(200, policy_response)
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
