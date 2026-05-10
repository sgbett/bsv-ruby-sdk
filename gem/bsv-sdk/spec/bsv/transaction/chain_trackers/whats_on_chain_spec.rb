# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Transaction::ChainTrackers::WhatsOnChain do
  let(:http_client) { instance_double(Net::HTTP) }
  let(:tracker) { described_class.new(http_client: http_client) }

  let(:merkle_root) { '4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b' }

  let(:header_json) do
    {
      'hash' => '000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f',
      'confirmations' => 800_000,
      'size' => 285,
      'height' => 0,
      'version' => 1,
      'merkleroot' => merkle_root,
      'tx' => [],
      'time' => 1_231_006_505,
      'nonce' => 2_083_236_893,
      'bits' => '1d00ffff',
      'previousblockhash' => '0000000000000000000000000000000000000000000000000000000000000000'
    }.to_json
  end

  def mock_response(code, body)
    fake_http_response(code, body)
  end

  describe '#valid_root_for_height?' do
    it 'returns true when root matches' do
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

    it 'returns false for 404 (block not found)' do
      allow(http_client).to receive(:request).and_return(mock_response(404, 'Not Found'))

      expect(tracker.valid_root_for_height?(merkle_root, 999_999_999)).to be false
    end

    it 'raises ChainProviderError for server errors' do
      allow(http_client).to receive(:request).and_return(mock_response(500, 'Internal Server Error'))

      expect { tracker.valid_root_for_height?(merkle_root, 0) }
        .to raise_error(BSV::Network::ChainProviderError) { |e| expect(e.status_code).to eq(500) }
    end

    it 'sends request to correct URL for mainnet' do
      allow(http_client).to receive(:request).and_return(mock_response(200, header_json))

      tracker.valid_root_for_height?(merkle_root, 100)

      expect(http_client).to have_received(:request) do |uri, _req|
        expect(uri.to_s).to eq('https://api.whatsonchain.com/v1/bsv/main/block/100/header')
      end
    end

    it 'sends API key in Authorization header when provided' do
      keyed_tracker = described_class.new(api_key: 'my-key', http_client: http_client)
      allow(http_client).to receive(:request).and_return(mock_response(200, header_json))

      keyed_tracker.valid_root_for_height?(merkle_root, 0)

      expect(http_client).to have_received(:request) do |_uri, req|
        expect(req['Authorization']).to eq('my-key')
      end
    end
  end

  describe '#current_height' do
    let(:chain_info_json) do
      { 'chain' => 'main', 'blocks' => 800_123, 'bestblockhash' => 'abc' }.to_json
    end

    it 'returns the current block height' do
      allow(http_client).to receive(:request).and_return(mock_response(200, chain_info_json))

      expect(tracker.current_height).to eq(800_123)
    end

    it 'raises ChainProviderError on failure' do
      allow(http_client).to receive(:request).and_return(mock_response(503, 'Unavailable'))

      expect { tracker.current_height }
        .to raise_error(BSV::Network::ChainProviderError) { |e| expect(e.status_code).to eq(503) }
    end
  end

  describe 'network configuration' do
    it 'defaults to mainnet' do
      allow(http_client).to receive(:request).and_return(mock_response(200, header_json))
      tracker.valid_root_for_height?(merkle_root, 0)

      expect(http_client).to have_received(:request) do |uri, _req|
        expect(uri.path).to include('/bsv/main/')
      end
    end

    it 'supports testnet' do
      test_tracker = described_class.new(network: :test, http_client: http_client)
      allow(http_client).to receive(:request).and_return(mock_response(200, header_json))
      test_tracker.valid_root_for_height?(merkle_root, 0)

      expect(http_client).to have_received(:request) do |uri, _req|
        expect(uri.path).to include('/bsv/test/')
      end
    end

    it 'supports stn' do
      stn_tracker = described_class.new(network: :stn, http_client: http_client)
      allow(http_client).to receive(:request).and_return(mock_response(200, header_json))
      stn_tracker.valid_root_for_height?(merkle_root, 0)

      expect(http_client).to have_received(:request) do |uri, _req|
        expect(uri.path).to include('/bsv/stn/')
      end
    end

    it 'raises ArgumentError for unknown network' do
      expect { described_class.new(network: :invalid) }
        .to raise_error(ArgumentError, /unknown network/)
    end
  end
end
