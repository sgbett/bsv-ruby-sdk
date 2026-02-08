# frozen_string_literal: true

RSpec.describe BSV::Network::ARC do
  # Mock HTTP client that stores the last request and returns a configurable response
  let(:mock_http) do
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

  # Minimal transaction double with #to_binary
  let(:tx) do
    instance_double(BSV::Transaction::Transaction, to_binary: "\x01\x00\x00\x00".b)
  end

  let(:success_body) do
    {
      'txid' => 'abc123',
      'txStatus' => 'SEEN_ON_NETWORK',
      'title' => 'Added to mempool',
      'extraInfo' => '',
      'blockHash' => '',
      'blockHeight' => 0,
      'timestamp' => '2025-01-01T00:00:00Z',
      'competingTxs' => nil
    }.to_json
  end

  describe '#broadcast' do
    it 'returns a BroadcastResponse on success' do
      http = mock_http.new(200, success_body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      response = arc.broadcast(tx)

      expect(response).to be_a(BSV::Network::BroadcastResponse)
      expect(response.txid).to eq('abc123')
      expect(response.tx_status).to eq('SEEN_ON_NETWORK')
      expect(response.message).to eq('Added to mempool')
      expect(response.success?).to be true
    end

    it 'sends binary transaction body with correct content type' do
      http = mock_http.new(200, success_body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      arc.broadcast(tx)

      expect(http.last_request['Content-Type']).to eq('application/octet-stream')
      expect(http.last_request.body).to eq("\x01\x00\x00\x00".b)
    end

    it 'posts to /v1/tx' do
      http = mock_http.new(200, success_body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      arc.broadcast(tx)

      expect(http.last_uri.to_s).to eq('https://arc.example.com/v1/tx')
    end

    it 'raises BroadcastError on HTTP 400' do
      body = { 'title' => 'Bad request', 'detail' => 'malformed tx', 'txid' => nil }.to_json
      http = mock_http.new(400, body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      expect { arc.broadcast(tx) }.to raise_error(BSV::Network::BroadcastError) do |error|
        expect(error.message).to eq('malformed tx')
        expect(error.status_code).to eq(400)
      end
    end

    it 'raises BroadcastError on HTTP 465 (fee too low)' do
      body = { 'title' => 'Fee too low', 'detail' => 'fee is below minimum', 'txid' => 'abc123' }.to_json
      http = mock_http.new(465, body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      expect { arc.broadcast(tx) }.to raise_error(BSV::Network::BroadcastError) do |error|
        expect(error.message).to eq('fee is below minimum')
        expect(error.status_code).to eq(465)
        expect(error.txid).to eq('abc123')
      end
    end

    it 'raises BroadcastError when txStatus is REJECTED' do
      body = { 'txid' => 'abc123', 'txStatus' => 'REJECTED', 'title' => 'Transaction rejected' }.to_json
      http = mock_http.new(200, body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      expect { arc.broadcast(tx) }.to raise_error(BSV::Network::BroadcastError) do |error|
        expect(error.message).to eq('Transaction rejected')
        expect(error.txid).to eq('abc123')
        expect(error.status_code).to eq(200)
      end
    end

    it 'raises BroadcastError when txStatus is DOUBLE_SPEND_ATTEMPTED' do
      body = {
        'txid' => 'abc123',
        'txStatus' => 'DOUBLE_SPEND_ATTEMPTED',
        'title' => 'Double spend',
        'competingTxs' => ['def456']
      }.to_json
      http = mock_http.new(200, body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      expect { arc.broadcast(tx) }.to raise_error(BSV::Network::BroadcastError, 'Double spend')
    end

    it 'handles non-JSON response body gracefully' do
      http = mock_http.new(500, 'Internal Server Error')
      arc = described_class.new('https://arc.example.com', http_client: http)

      expect { arc.broadcast(tx) }.to raise_error(BSV::Network::BroadcastError) do |error|
        expect(error.message).to eq('Internal Server Error')
        expect(error.status_code).to eq(500)
      end
    end
  end

  describe '#status' do
    it 'returns a BroadcastResponse for a known txid' do
      body = { 'txid' => 'abc123', 'txStatus' => 'MINED', 'blockHeight' => 800_000 }.to_json
      http = mock_http.new(200, body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      response = arc.status('abc123')

      expect(response).to be_a(BSV::Network::BroadcastResponse)
      expect(response.txid).to eq('abc123')
      expect(response.mined?).to be true
      expect(response.block_height).to eq(800_000)
    end

    it 'sends GET to /v1/tx/{txid}' do
      body = { 'txid' => 'abc123', 'txStatus' => 'SEEN_ON_NETWORK' }.to_json
      http = mock_http.new(200, body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      arc.status('abc123')

      expect(http.last_uri.to_s).to eq('https://arc.example.com/v1/tx/abc123')
      expect(http.last_request).to be_a(Net::HTTP::Get)
    end

    it 'raises BroadcastError on failure' do
      body = { 'title' => 'Not found', 'detail' => 'transaction not found' }.to_json
      http = mock_http.new(404, body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      expect { arc.status('unknown') }.to raise_error(BSV::Network::BroadcastError) do |error|
        expect(error.status_code).to eq(404)
      end
    end
  end

  describe 'authentication' do
    it 'sets Authorization header when api_key is provided' do
      http = mock_http.new(200, success_body)
      arc = described_class.new('https://arc.example.com', api_key: 'my-key', http_client: http)

      arc.broadcast(tx)

      expect(http.last_request['Authorization']).to eq('Bearer my-key')
    end

    it 'omits Authorization header when api_key is nil' do
      http = mock_http.new(200, success_body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      arc.broadcast(tx)

      expect(http.last_request['Authorization']).to be_nil
    end
  end

  describe 'URL normalisation' do
    it 'strips trailing slash from base URL' do
      http = mock_http.new(200, success_body)
      arc = described_class.new('https://arc.example.com/', http_client: http)

      arc.broadcast(tx)

      expect(http.last_uri.to_s).to eq('https://arc.example.com/v1/tx')
    end
  end
end
