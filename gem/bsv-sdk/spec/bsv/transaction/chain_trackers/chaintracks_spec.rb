# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/MultipleDescribes

RSpec.describe BSV::Transaction::ChainTrackers::Chaintracks do
  let(:http_client) { instance_double(Net::HTTP) }
  let(:tracker) { described_class.new(http_client: http_client) }

  let(:merkle_root) { '4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b' }

  let(:header_json) do
    {
      'hash' => '000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f',
      'height' => 0,
      'merkleRoot' => merkle_root,
      'time' => 1_231_006_505
    }.to_json
  end

  def mock_response(code, body)
    instance_double(Net::HTTPResponse, code: code.to_s, body: body)
  end

  describe '#valid_root_for_height?' do
    it 'returns true when merkleRoot matches' do
      allow(http_client).to receive(:request).and_return(mock_response(200, header_json))

      expect(tracker.valid_root_for_height?(merkle_root, 0)).to be true
    end

    it 'returns true with case-insensitive comparison' do
      allow(http_client).to receive(:request).and_return(mock_response(200, header_json))

      expect(tracker.valid_root_for_height?(merkle_root.upcase, 0)).to be true
    end

    it 'returns false when root does not match' do
      allow(http_client).to receive(:request).and_return(mock_response(200, header_json))

      expect(tracker.valid_root_for_height?('0000' * 16, 0)).to be false
    end

    it 'returns false when response is missing merkleRoot field' do
      body = { 'height' => 0, 'hash' => 'abc' }.to_json
      allow(http_client).to receive(:request).and_return(mock_response(200, body))

      expect(tracker.valid_root_for_height?(merkle_root, 0)).to be false
    end

    it 'returns false on 404 (block not found)' do
      allow(http_client).to receive(:request).and_return(mock_response(404, 'Not Found'))

      expect(tracker.valid_root_for_height?(merkle_root, 999_999_999)).to be false
    end

    it 'raises ChainProviderError on server error' do
      allow(http_client).to receive(:request).and_return(mock_response(500, 'Internal Server Error'))

      expect { tracker.valid_root_for_height?(merkle_root, 0) }
        .to raise_error(BSV::Network::ChainProviderError) { |e| expect(e.status_code).to eq(500) }
    end

    it 'sends GET to correct URL path' do
      allow(http_client).to receive(:request).and_return(mock_response(200, header_json))

      tracker.valid_root_for_height?(merkle_root, 100)

      expect(http_client).to have_received(:request) do |uri, _req|
        expect(uri.to_s).to eq('https://arcade.gorillapool.io/chaintracks/v2/header/height/100')
      end
    end

    it 'sends Bearer auth header when api_key provided' do
      keyed_tracker = described_class.new(api_key: 'my-key', http_client: http_client)
      allow(http_client).to receive(:request).and_return(mock_response(200, header_json))

      keyed_tracker.valid_root_for_height?(merkle_root, 0)

      expect(http_client).to have_received(:request) do |_uri, req|
        expect(req['Authorization']).to eq('Bearer my-key')
      end
    end

    it 'does not send Authorization header when api_key is nil' do
      allow(http_client).to receive(:request).and_return(mock_response(200, header_json))

      tracker.valid_root_for_height?(merkle_root, 0)

      expect(http_client).to have_received(:request) do |_uri, req|
        expect(req['Authorization']).to be_nil
      end
    end
  end

  describe '#current_height' do
    let(:tip_json) { { 'height' => 800_123, 'hash' => 'abc' }.to_json }

    it 'returns the current block height' do
      allow(http_client).to receive(:request).and_return(mock_response(200, tip_json))

      expect(tracker.current_height).to eq(800_123)
    end

    it 'raises ChainProviderError on failure' do
      allow(http_client).to receive(:request).and_return(mock_response(503, 'Unavailable'))

      expect { tracker.current_height }
        .to raise_error(BSV::Network::ChainProviderError) { |e| expect(e.status_code).to eq(503) }
    end

    it 'sends GET to correct URL path' do
      allow(http_client).to receive(:request).and_return(mock_response(200, tip_json))

      tracker.current_height

      expect(http_client).to have_received(:request) do |uri, _req|
        expect(uri.to_s).to eq('https://arcade.gorillapool.io/chaintracks/v2/tip')
      end
    end
  end

  describe 'URL configuration' do
    it 'defaults to a working instance' do
      tracker = described_class.new
      expect(tracker).to respond_to(:valid_root_for_height?)
      expect(tracker).to respond_to(:current_height)
    end

    it 'accepts a custom URL' do
      testnet_tracker = described_class.new(url: 'https://testnet.arcade.gorillapool.io', http_client: http_client)
      allow(http_client).to receive(:request).and_return(mock_response(200, { 'height' => 1 }.to_json))

      testnet_tracker.current_height

      expect(http_client).to have_received(:request) do |uri, _req|
        expect(uri.host).to eq('testnet.arcade.gorillapool.io')
      end
    end
  end
end

RSpec.describe BSV::Transaction::ChainTrackers do
  describe '.default' do
    it 'returns a Chaintracks instance' do
      expect(described_class.default).to be_a(BSV::Transaction::ChainTrackers::Chaintracks)
    end

    it 'returns a functional tracker by default' do
      tracker = described_class.default
      expect(tracker).to respond_to(:valid_root_for_height?)
    end

    it 'returns a functional tracker for testnet' do
      tracker = described_class.default(testnet: true)
      expect(tracker).to respond_to(:valid_root_for_height?)
    end

    it 'accepts api_key option' do
      tracker = described_class.default(api_key: 'my-key')
      expect(tracker).to respond_to(:valid_root_for_height?)
    end
  end
end

# rubocop:enable RSpec/MultipleDescribes
