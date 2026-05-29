# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Wallet::Substrates::HTTPWalletJSON do
  let(:base_url) { 'http://wallet.example.com' }

  # Injectable HTTP client following the SDK's existing convention (matches
  # HTTPWalletWire, ARC, TAALBinary, Ordinals, WoCREST). The stub responds to
  # `#request(uri, net_http_request)` and returns a properly typed
  # Net::HTTPResponse subclass via {FakeHttpResponse}.
  def stub_http(response)
    http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
    allow(http).to receive(:request).and_return(response)
    http
  end

  def ok_json(body)
    fake_http_response(200, body, content_type: 'application/json')
  end

  def error_json(code, body)
    fake_http_response(code, body, content_type: 'application/json')
  end

  def build_client(http_client:, headers: {})
    described_class.new(base_url: base_url, http_client: http_client, headers: headers)
  end

  # ---------------------------------------------------------------------------
  # Interface inclusion
  # ---------------------------------------------------------------------------

  describe 'interface' do
    it 'includes BSV::Wallet::Interface::BRC100' do
      client = build_client(http_client: stub_http(ok_json('{"network":"mainnet"}')))
      expect(client).to be_a(BSV::Wallet::Interface::BRC100)
    end

    it 'accepts http_client and headers in constructor' do
      c = described_class.new(base_url: base_url, headers: { 'X-Foo' => 'bar' })
      expect(c).to be_a(described_class)
    end
  end

  # ---------------------------------------------------------------------------
  # get_network round-trip
  # ---------------------------------------------------------------------------

  describe '#get_network' do
    it 'POSTs to /v1/wallet/getNetwork and returns snake_case symbol keys' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request) do |uri, _req|
        expect(uri.path).to eq('/v1/wallet/getNetwork')
        ok_json('{"network":"mainnet"}')
      end

      result = build_client(http_client: http).get_network
      expect(result).to eq({ network: 'mainnet' })
    end

    it 'sends an empty JSON object body when no args provided' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request) do |_uri, req|
        expect(req.body).to eq('{}')
        ok_json('{"network":"mainnet"}')
      end

      build_client(http_client: http).get_network
    end
  end

  # ---------------------------------------------------------------------------
  # create_action: camelCase request body
  # ---------------------------------------------------------------------------

  describe '#create_action' do
    it 'sends camelCase keys in the request body' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request) do |uri, req|
        expect(uri.path).to eq('/v1/wallet/createAction')
        body = JSON.parse(req.body)
        expect(body).to include('noSendChange', 'lockTime')
        ok_json('{"txid":"abcd1234"}')
      end

      build_client(http_client: http).create_action(
        description: 'test',
        no_send_change: ['0000000000000000000000000000000000000000000000000000000000000001.0'],
        lock_time: 0
      )
    end

    it 'converts nested arrays of hashes to camelCase' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request) do |_uri, req|
        body = JSON.parse(req.body)
        expect(body['outputs'].first).to have_key('lockingScript')
        ok_json('{"txid":"abcd1234"}')
      end

      build_client(http_client: http).create_action(
        description: 'test',
        outputs: [{ locking_script: 'deadbeef', satoshis: 1000, output_description: 'out' }]
      )
    end

    it 'converts BSV acronym keys correctly (protocol_id → protocolID)' do
      wire = BSV::WireFormat.to_wire({ protocol_id: [2, 'test'], key_id: 'k1', input_beef: [1, 2, 3] })
      expect(wire['protocolID']).to eq([2, 'test'])
      expect(wire['keyID']).to eq('k1')
      expect(wire['inputBEEF']).to eq([1, 2, 3])

      http = stub_http(ok_json('{"txid":"abcd"}'))
      build_client(http_client: http).create_action(description: 'test')
      expect(http).to have_received(:request)
    end
  end

  # ---------------------------------------------------------------------------
  # authenticated?: predicate method maps to isAuthenticated URL (no ?)
  # ---------------------------------------------------------------------------

  describe '#authenticated?' do
    it 'POSTs to /v1/wallet/isAuthenticated (not /v1/wallet/authenticated?)' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request) do |uri, _req|
        expect(uri.path).to eq('/v1/wallet/isAuthenticated')
        ok_json('{"isAuthenticated":true}')
      end

      result = build_client(http_client: http).authenticated?
      expect(result[:is_authenticated]).to be(true)
    end

    it 'does NOT hit /v1/wallet/authenticated?' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request) do |uri, _req|
        expect(uri.path).not_to include('authenticated?')
        ok_json('{"isAuthenticated":false}')
      end

      expect { build_client(http_client: http).authenticated? }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # Error paths
  # ---------------------------------------------------------------------------

  describe 'error handling' do
    it 'raises InsufficientFundsError (code 5) from a 400 response' do
      http = stub_http(error_json(400, '{"code":5,"message":"not enough funds","stack":""}'))

      expect do
        build_client(http_client: http).create_action(description: 'test')
      end.to raise_error(BSV::Wallet::InsufficientFundsError, 'not enough funds')
    end

    it 'raises base Error for an unknown error code, preserving code and message' do
      http = stub_http(error_json(500, '{"code":99,"message":"internal","stack":""}'))

      error = begin
        build_client(http_client: http).get_network
      rescue BSV::Wallet::Error => e
        e
      end
      expect(error).to be_a(BSV::Wallet::Error)
      expect(error.code).to eq(99)
      expect(error.message).to eq('internal')
    end

    it 'raises a wrapped Error (code 1) when response JSON is invalid on success' do
      http = stub_http(ok_json('not-json'))

      expect do
        build_client(http_client: http).get_network
      end.to raise_error(BSV::Wallet::Error) { |e| expect(e.code).to eq(1) }
    end

    it 'raises a wrapped Error (code 1) on network failure' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request).and_raise(SocketError.new('connection refused'))

      expect do
        build_client(http_client: http).get_network
      end.to raise_error(BSV::Wallet::Error) { |e| expect(e.code).to eq(1) }
    end

    it 'uses raw body as message when error JSON has no message field' do
      http = stub_http(fake_http_response(503, 'Service Unavailable'))

      expect do
        build_client(http_client: http).get_network
      end.to raise_error(BSV::Wallet::Error, 'Service Unavailable')
    end
  end

  # ---------------------------------------------------------------------------
  # Custom headers sent on every request
  # ---------------------------------------------------------------------------

  describe 'custom headers' do
    it 'sends a custom Authorization header on every request' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request) do |_uri, req|
        expect(req['Authorization']).to eq('Bearer my-token')
        ok_json('{"network":"mainnet"}')
      end

      build_client(
        http_client: http,
        headers: { 'Authorization' => 'Bearer my-token' }
      ).get_network
    end

    it 'lets Content-Type win over a custom header of the same name' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request) do |_uri, req|
        expect(req['Content-Type']).to eq('application/json')
        ok_json('{"network":"mainnet"}')
      end

      build_client(
        http_client: http,
        headers: { 'Content-Type' => 'text/plain' }
      ).get_network
    end
  end

  # ---------------------------------------------------------------------------
  # 204 No Content
  # ---------------------------------------------------------------------------

  describe '204 No Content response' do
    it 'returns an empty hash for void calls' do
      http = stub_http(fake_http_response(204, ''))

      result = build_client(http_client: http).abort_action(reference: 'ref-123')
      expect(result).to eq({})
    end
  end

  # ---------------------------------------------------------------------------
  # WIRE_METHOD_NAMES verification
  # ---------------------------------------------------------------------------

  describe 'WIRE_METHOD_NAMES' do
    it 'maps all 28 BRC-100 Ruby methods to camelCase wire names' do
      expect(described_class::WIRE_METHOD_NAMES.size).to eq(28)
    end

    it 'maps authenticated? to isAuthenticated' do
      expect(described_class::WIRE_METHOD_NAMES[:authenticated?]).to eq('isAuthenticated')
    end

    it 'maps get_network to getNetwork' do
      expect(described_class::WIRE_METHOD_NAMES[:get_network]).to eq('getNetwork')
    end

    it 'maps create_action to createAction' do
      expect(described_class::WIRE_METHOD_NAMES[:create_action]).to eq('createAction')
    end
  end

  # ---------------------------------------------------------------------------
  # Integration: gated on BSV_WALLET_URL env var
  # ---------------------------------------------------------------------------

  describe 'integration', :integration do
    let(:wallet_url) { ENV.fetch('BSV_WALLET_URL', nil) }

    it 'performs a get_network call against a live wallet' do
      skip 'BSV_WALLET_URL not set' unless wallet_url

      live_client = described_class.new(base_url: wallet_url)
      result = live_client.get_network
      expect(result[:network]).to be('mainnet').or be('testnet')
    end
  end
end
