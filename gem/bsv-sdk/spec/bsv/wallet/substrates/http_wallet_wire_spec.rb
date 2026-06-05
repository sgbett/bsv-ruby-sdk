# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Wallet::Substrates::HTTPWalletWire do
  # Build a well-formed success result frame for get_network → :mainnet.
  # Frame layout: [0x00 success_byte][0x00 mainnet_code]
  let(:mainnet_frame) do
    payload = BSV::Wallet::Serializer::GetNetwork::Result.serialize({ network: :mainnet })
    BSV::Wallet::Wire::Frame.write_result(payload: payload)
  end

  let(:base_url) { 'http://wallet.example' }

  # Stub HTTP client matching the injectable client convention (responds to #request(uri, req)).
  def stub_http(response)
    client = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
    allow(client).to receive(:request).and_return(response)
    client
  end

  def ok_response(body)
    fake_http_response(200, body)
  end

  def error_response(code, body = '')
    fake_http_response(code, body)
  end

  # -------------------------------------------------------------------------
  # Round-trip: get_network → :mainnet
  # -------------------------------------------------------------------------

  describe '#transmit_to_wallet (get_network round-trip)' do
    it 'decodes :mainnet from the stubbed frame' do
      wire   = described_class.new(base_url: base_url, http_client: stub_http(ok_response(mainnet_frame)))
      client = BSV::Wallet::WalletWireTransceiver.new(wire)

      expect(client.get_network[:network]).to eq(:mainnet)
    end

    it 'sends Content-Type: application/octet-stream' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request) do |_uri, req|
        expect(req['Content-Type']).to eq('application/octet-stream')
        ok_response(mainnet_frame)
      end

      BSV::Wallet::WalletWireTransceiver.new(
        described_class.new(base_url: base_url, http_client: http)
      ).get_network
    end

    it 'passes a binary body to the HTTP request' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request) do |_uri, req|
        expect(req.body.encoding).to eq(Encoding::ASCII_8BIT)
        ok_response(mainnet_frame)
      end

      BSV::Wallet::WalletWireTransceiver.new(
        described_class.new(base_url: base_url, http_client: http)
      ).get_network
    end

    it 'POSTs to the correct URI path' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request) do |uri, _req|
        expect(uri.path).to eq('/wallet')
        ok_response(mainnet_frame)
      end

      BSV::Wallet::WalletWireTransceiver.new(
        described_class.new(base_url: base_url, http_client: http)
      ).get_network
    end
  end

  # -------------------------------------------------------------------------
  # Round-trip: error frame → exception rehydration
  # -------------------------------------------------------------------------

  describe '#transmit_to_wallet (error frame round-trip)' do
    it 'rehydrates WERR_INSUFFICIENT_FUNDS and raises InsufficientFundsError' do
      error_frame = BSV::Wallet::Wire::Frame.write_error(
        error: BSV::Wallet::InsufficientFundsError.new('not enough coins')
      )
      wire   = described_class.new(base_url: base_url, http_client: stub_http(ok_response(error_frame)))
      client = BSV::Wallet::WalletWireTransceiver.new(wire)

      expect { client.get_network }
        .to raise_error(BSV::Wallet::InsufficientFundsError, 'not enough coins')
    end
  end

  # -------------------------------------------------------------------------
  # HTTP non-2xx → WERR_INVALID_OPERATION
  # -------------------------------------------------------------------------

  describe '#transmit_to_wallet (non-2xx responses)' do
    it 'raises WERR_INVALID_OPERATION with status code on HTTP 500' do
      wire = described_class.new(base_url: base_url, http_client: stub_http(error_response(500, 'oops')))

      expect { wire.transmit_to_wallet("\x1b\x00".b) }
        .to raise_error(BSV::Wallet::Error) do |err|
          expect(err.message).to include('500')
        end
    end

    it 'raises WERR_INVALID_OPERATION on HTTP 404' do
      wire = described_class.new(base_url: base_url, http_client: stub_http(error_response(404, 'not found')))

      expect { wire.transmit_to_wallet("\x1b\x00".b) }
        .to raise_error(BSV::Wallet::Error) do |err|
          expect(err.message).to include('404')
        end
    end
  end

  # -------------------------------------------------------------------------
  # Network failure → WERR_INVALID_OPERATION
  # -------------------------------------------------------------------------

  describe '#transmit_to_wallet (network failure)' do
    it 'wraps SocketError as WERR_INVALID_OPERATION' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request).and_raise(SocketError.new('connection refused'))
      wire = described_class.new(base_url: base_url, http_client: http)

      expect { wire.transmit_to_wallet("\x1b\x00".b) }
        .to raise_error(BSV::Wallet::Error) do |err|
          expect(err.message).to include('connection refused')
        end
    end

    it 'wraps Errno::ECONNREFUSED as WERR_INVALID_OPERATION' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request).and_raise(Errno::ECONNREFUSED)
      wire = described_class.new(base_url: base_url, http_client: http)

      expect { wire.transmit_to_wallet("\x1b\x00".b) }
        .to raise_error(BSV::Wallet::Error) do |err|
          expect(err.message).to include('connection')
        end
    end
  end

  # -------------------------------------------------------------------------
  # Header merging
  # -------------------------------------------------------------------------

  describe 'header merging' do
    it 'sends custom Authorization header on every request' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request) do |_uri, req|
        expect(req['Authorization']).to eq('Bearer token123')
        ok_response(mainnet_frame)
      end

      BSV::Wallet::WalletWireTransceiver.new(
        described_class.new(base_url: base_url, http_client: http, headers: { 'Authorization' => 'Bearer token123' })
      ).get_network
    end

    it 'does not allow custom headers to override Content-Type' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request) do |_uri, req|
        expect(req['Content-Type']).to eq('application/octet-stream')
        ok_response(mainnet_frame)
      end

      BSV::Wallet::WalletWireTransceiver.new(
        described_class.new(base_url: base_url, http_client: http, headers: { 'Content-Type' => 'text/plain' })
      ).get_network
    end
  end

  # -------------------------------------------------------------------------
  # URL normalisation (trailing slash variants)
  # -------------------------------------------------------------------------

  describe 'base URL normalisation' do
    it 'resolves /wallet path without trailing slash on base_url' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request) do |uri, _req|
        expect(uri.to_s).to eq('http://wallet.example/wallet')
        ok_response(mainnet_frame)
      end

      BSV::Wallet::WalletWireTransceiver.new(
        described_class.new(base_url: 'http://wallet.example', http_client: http)
      ).get_network
    end

    it 'resolves /wallet path with trailing slash on base_url' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request) do |uri, _req|
        expect(uri.to_s).to eq('http://wallet.example/wallet')
        ok_response(mainnet_frame)
      end

      BSV::Wallet::WalletWireTransceiver.new(
        described_class.new(base_url: 'http://wallet.example/', http_client: http)
      ).get_network
    end
  end

  # -------------------------------------------------------------------------
  # HTTPS: URI scheme carried through to injectable client
  # -------------------------------------------------------------------------

  describe 'HTTPS URI' do
    it 'builds an https:// URI for the injectable client' do
      http = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(http).to receive(:request) do |uri, _req|
        expect(uri.scheme).to eq('https')
        ok_response(mainnet_frame)
      end

      BSV::Wallet::WalletWireTransceiver.new(
        described_class.new(base_url: 'https://secure.wallet.example', http_client: http)
      ).get_network
    end
  end

  # -------------------------------------------------------------------------
  # .client convenience factory
  # -------------------------------------------------------------------------

  describe '.client' do
    it 'returns a WalletWireTransceiver' do
      c = described_class.client(base_url: base_url)
      expect(c).to be_a(BSV::Wallet::WalletWireTransceiver)
    end

    it 'returns a client that can make BRC-100 calls via the injected http_client' do
      c = described_class.client(base_url: base_url, http_client: stub_http(ok_response(mainnet_frame)))
      expect(c.get_network[:network]).to eq(:mainnet)
    end
  end

  # -------------------------------------------------------------------------
  # Empty response body on success
  # -------------------------------------------------------------------------

  describe 'empty response body' do
    it 'returns empty binary string on 200 with nil body' do
      wire   = described_class.new(base_url: base_url, http_client: stub_http(ok_response(nil)))
      result = wire.transmit_to_wallet("\x1b\x00".b)

      expect(result).to eq(''.b)
      expect(result.encoding).to eq(Encoding::ASCII_8BIT)
    end
  end

  # -------------------------------------------------------------------------
  # Integration suite (requires BSV_WALLET_URL)
  # -------------------------------------------------------------------------

  describe 'live wallet integration', :integration do
    let(:wallet_url) { ENV.fetch('BSV_WALLET_URL', nil) }

    it 'get_network returns a valid network symbol from a real wallet' do
      skip 'BSV_WALLET_URL not set' unless wallet_url

      live_client = described_class.client(base_url: wallet_url)
      result  = live_client.get_network
      network = result[:network]
      expect(network).to be(:mainnet).or be(:testnet)
    end
  end
end
