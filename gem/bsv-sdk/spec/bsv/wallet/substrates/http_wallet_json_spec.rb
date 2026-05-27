# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'

RSpec.describe BSV::Wallet::Substrates::HTTPWalletJSON do
  let(:base_url) { 'http://wallet.example.com' }
  let(:client)   { described_class.new(base_url: base_url) }

  before { WebMock.enable! }
  after  { WebMock.disable! }

  # ---------------------------------------------------------------------------
  # Interface inclusion
  # ---------------------------------------------------------------------------

  it 'includes BSV::Wallet::Interface::BRC100' do
    expect(client).to be_a(BSV::Wallet::Interface::BRC100)
  end

  it 'accepts http_client and headers in constructor' do
    c = described_class.new(base_url: base_url, headers: { 'X-Foo' => 'bar' })
    expect(c).to be_a(described_class)
  end

  # ---------------------------------------------------------------------------
  # get_network round-trip
  # ---------------------------------------------------------------------------

  describe '#get_network' do
    it 'POSTs to /v1/wallet/getNetwork and returns snake_case symbol keys' do
      stub_request(:post, "#{base_url}/v1/wallet/getNetwork")
        .to_return(status: 200, body: '{"network":"mainnet"}', headers: { 'Content-Type' => 'application/json' })

      result = client.get_network
      expect(result).to eq({ network: 'mainnet' })
    end

    it 'sends an empty JSON object body when no args provided' do
      stub = stub_request(:post, "#{base_url}/v1/wallet/getNetwork")
             .with(body: '{}')
             .to_return(status: 200, body: '{"network":"mainnet"}')

      client.get_network
      expect(stub).to have_been_requested
    end
  end

  # ---------------------------------------------------------------------------
  # create_action: camelCase request body
  # ---------------------------------------------------------------------------

  describe '#create_action' do
    it 'sends camelCase keys in the request body' do
      stub = stub_request(:post, "#{base_url}/v1/wallet/createAction")
             .with(body: hash_including('noSendChange', 'lockTime'))
             .to_return(status: 200, body: '{"txid":"abcd1234"}')

      client.create_action(
        description: 'test',
        no_send_change: ['0000000000000000000000000000000000000000000000000000000000000001.0'],
        lock_time: 0
      )
      expect(stub).to have_been_requested
    end

    it 'converts nested arrays of hashes to camelCase' do
      stub = stub_request(:post, "#{base_url}/v1/wallet/createAction")
             .with do |req|
               body = JSON.parse(req.body)
               body['outputs']&.first&.key?('lockingScript')
             end
               .to_return(status: 200, body: '{"txid":"abcd1234"}')

      client.create_action(
        description: 'test',
        outputs: [{ locking_script: 'deadbeef', satoshis: 1000, output_description: 'out' }]
      )
      expect(stub).to have_been_requested
    end

    it 'converts BSV acronym keys correctly (protocol_id → protocolID)' do
      stub = stub_request(:post, "#{base_url}/v1/wallet/createAction")
             .with do |req|
               body = JSON.parse(req.body)
               body.key?('description')
             end
               .to_return(status: 200, body: '{"txid":"abcd"}')

      # Verify the SNAKE_TO_CAMEL table maps acronym keys
      wire = BSV::WireFormat.to_wire({ protocol_id: [2, 'test'], key_id: 'k1', input_beef: [1, 2, 3] })
      expect(wire['protocolID']).to eq([2, 'test'])
      expect(wire['keyID']).to eq('k1')
      expect(wire['inputBEEF']).to eq([1, 2, 3])

      client.create_action(description: 'test')
      expect(stub).to have_been_requested
    end
  end

  # ---------------------------------------------------------------------------
  # authenticated?: predicate method maps to isAuthenticated URL (no ?)
  # ---------------------------------------------------------------------------

  describe '#authenticated?' do
    it 'POSTs to /v1/wallet/isAuthenticated (not /v1/wallet/authenticated?)' do
      stub = stub_request(:post, "#{base_url}/v1/wallet/isAuthenticated")
             .to_return(status: 200, body: '{"isAuthenticated":true}')

      result = client.authenticated?
      expect(stub).to have_been_requested
      expect(result[:is_authenticated]).to be(true)
    end

    it 'does NOT hit /v1/wallet/authenticated?' do
      stub_request(:post, "#{base_url}/v1/wallet/isAuthenticated")
        .to_return(status: 200, body: '{"isAuthenticated":false}')

      expect { client.authenticated? }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # Error paths
  # ---------------------------------------------------------------------------

  describe 'error handling' do
    it 'raises WERR_INSUFFICIENT_FUNDS (code 5) from a 400 response' do
      stub_request(:post, "#{base_url}/v1/wallet/createAction")
        .to_return(
          status: 400,
          body: '{"code":5,"message":"not enough funds","stack":""}',
          headers: { 'Content-Type' => 'application/json' }
        )

      expect do
        client.create_action(description: 'test')
      end.to raise_error(BSV::Wallet::InsufficientFundsError, 'not enough funds')
    end

    it 'raises base Error for an unknown error code, preserving code and message' do
      stub_request(:post, "#{base_url}/v1/wallet/getNetwork")
        .to_return(status: 500, body: '{"code":99,"message":"internal","stack":""}')

      error = begin
        client.get_network
      rescue BSV::Wallet::Error => e
        e
      end
      expect(error).to be_a(BSV::Wallet::Error)
      expect(error.code).to eq(99)
      expect(error.message).to eq('internal')
    end

    it 'raises WERR_INVALID_OPERATION (code 1) when response JSON is invalid on success' do
      stub_request(:post, "#{base_url}/v1/wallet/getNetwork")
        .to_return(status: 200, body: 'not-json')

      expect do
        client.get_network
      end.to raise_error(BSV::Wallet::Error) { |e| expect(e.code).to eq(1) }
    end

    it 'raises WERR_INVALID_OPERATION (code 1) on network failure' do
      stub_request(:post, "#{base_url}/v1/wallet/getNetwork").to_raise(SocketError.new('connection refused'))

      expect do
        client.get_network
      end.to raise_error(BSV::Wallet::Error) { |e| expect(e.code).to eq(1) }
    end

    it 'uses raw body as message when error JSON has no message field' do
      stub_request(:post, "#{base_url}/v1/wallet/getNetwork")
        .to_return(status: 503, body: 'Service Unavailable')

      expect do
        client.get_network
      end.to raise_error(BSV::Wallet::Error, 'Service Unavailable')
    end
  end

  # ---------------------------------------------------------------------------
  # Custom headers sent on every request
  # ---------------------------------------------------------------------------

  describe 'custom headers' do
    it 'sends a custom Authorization header on every request' do
      client_with_auth = described_class.new(
        base_url: base_url,
        headers: { 'Authorization' => 'Bearer my-token' }
      )

      stub = stub_request(:post, "#{base_url}/v1/wallet/getNetwork")
             .with(headers: { 'Authorization' => 'Bearer my-token' })
             .to_return(status: 200, body: '{"network":"mainnet"}')

      client_with_auth.get_network
      expect(stub).to have_been_requested
    end
  end

  # ---------------------------------------------------------------------------
  # 204 No Content
  # ---------------------------------------------------------------------------

  describe '204 No Content response' do
    it 'returns an empty hash for void calls' do
      stub_request(:post, "#{base_url}/v1/wallet/abortAction")
        .to_return(status: 204, body: '')

      result = client.abort_action(reference: 'ref-123')
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

    before { WebMock.disable! }

    it 'performs a get_network call against a live wallet' do
      skip 'BSV_WALLET_URL not set' unless wallet_url

      live_client = described_class.new(base_url: wallet_url)
      result = live_client.get_network
      expect(result[:network]).to be('mainnet').or be('testnet')
    end
  end
end
