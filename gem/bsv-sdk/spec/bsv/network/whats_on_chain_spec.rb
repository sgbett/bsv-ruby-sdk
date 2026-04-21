# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::WhatsOnChain do
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

  let(:utxo_response_body) do
    [
      { 'tx_hash' => 'aabb11', 'tx_pos' => 0, 'value' => 50_000, 'height' => 800_000 },
      { 'tx_hash' => 'ccdd22', 'tx_pos' => 1, 'value' => 25_000, 'height' => 0 }
    ].to_json
  end

  # Minimal valid coinbase transaction hex (1 input, 1 output)
  let(:raw_tx_hex) do
    '0100000001' \
      '0000000000000000000000000000000000000000000000000000000000000000' \
      'ffffffff' \
      '04deadbeef' \
      'ffffffff' \
      '01' \
      '0100000000000000' \
      '00' \
      '00000000'
  end

  describe '#fetch_utxos' do
    it 'returns an array of UTXOs' do
      http = mock_http.new(200, utxo_response_body)
      provider = described_class.new(http_client: http)

      utxos = provider.fetch_utxos('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa')

      expect(utxos).to be_an(Array)
      expect(utxos.length).to eq(2)
      expect(utxos.first).to be_a(BSV::Network::UTXO)
    end

    it 'maps WoC fields correctly (value to satoshis)' do
      http = mock_http.new(200, utxo_response_body)
      provider = described_class.new(http_client: http)

      utxos = provider.fetch_utxos('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa')

      first = utxos.first
      expect(first.tx_hash).to eq('aabb11')
      expect(first.tx_pos).to eq(0)
      expect(first.satoshis).to eq(50_000)
      expect(first.height).to eq(800_000)
    end

    it 'sends GET to the correct mainnet URL' do
      http = mock_http.new(200, '[]')
      provider = described_class.new(http_client: http)

      provider.fetch_utxos('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa')

      expect(http.last_uri.to_s).to eq(
        'https://api.whatsonchain.com/v1/bsv/main/address/1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa/unspent'
      )
      expect(http.last_request).to be_a(Net::HTTP::Get)
    end

    it 'uses testnet URL when network is :testnet' do
      http = mock_http.new(200, '[]')
      provider = described_class.new(network: :testnet, http_client: http)

      provider.fetch_utxos('mfWxJ45yp2SFn7UciZyNpvDKrzbi36LaVX')

      expect(http.last_uri.to_s).to include('/v1/bsv/test/')
    end

    it 'returns an empty array when there are no UTXOs' do
      http = mock_http.new(200, '[]')
      provider = described_class.new(http_client: http)

      utxos = provider.fetch_utxos('1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa')

      expect(utxos).to eq([])
    end

    it 'raises ChainProviderError on HTTP error' do
      http = mock_http.new(404, 'Address not found')
      provider = described_class.new(http_client: http)

      expect { provider.fetch_utxos('invalid') }.to raise_error(BSV::Network::ChainProviderError) do |error|
        expect(error.message).to eq('Address not found')
        expect(error.status_code).to eq(404)
      end
    end
  end

  describe '#fetch_transaction' do
    it 'returns a parsed Transaction' do
      http = mock_http.new(200, raw_tx_hex)
      provider = described_class.new(http_client: http)

      tx = provider.fetch_transaction('abc123')

      expect(tx).to be_a(BSV::Transaction::Transaction)
    end

    it 'sends GET to the correct URL' do
      http = mock_http.new(200, raw_tx_hex)
      provider = described_class.new(http_client: http)

      provider.fetch_transaction('abc123')

      expect(http.last_uri.to_s).to eq(
        'https://api.whatsonchain.com/v1/bsv/main/tx/abc123/hex'
      )
    end

    it 'raises ChainProviderError on HTTP error' do
      http = mock_http.new(404, 'Transaction not found')
      provider = described_class.new(http_client: http)

      expect { provider.fetch_transaction('unknown') }.to raise_error(BSV::Network::ChainProviderError) do |error|
        expect(error.message).to eq('Transaction not found')
        expect(error.status_code).to eq(404)
      end
    end
  end

  describe '#current_height' do
    it 'returns the current block height as an integer' do
      chain_info = { 'blocks' => 875_123 }.to_json
      http = mock_http.new(200, chain_info)
      provider = described_class.new(http_client: http)

      height = provider.current_height

      expect(height).to eq(875_123)
    end

    it 'sends GET to the chain info endpoint' do
      chain_info = { 'blocks' => 800_000 }.to_json
      http = mock_http.new(200, chain_info)
      provider = described_class.new(http_client: http)

      provider.current_height

      expect(http.last_uri.to_s).to eq(
        'https://api.whatsonchain.com/v1/bsv/main/chain/info'
      )
    end

    it 'raises ChainProviderError on HTTP error' do
      http = mock_http.new(503, 'Service unavailable')
      provider = described_class.new(http_client: http)

      expect { provider.current_height }.to raise_error(BSV::Network::ChainProviderError)
    end
  end

  describe '#get_block_header' do
    let(:block_header_body) do
      {
        'hash' => '0000000000000000040fb5f4a3f8bc5516b5a7a4b5f4a3f8bc5516b5a7a4b00',
        'height' => 800_000,
        'merkleroot' => 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890'
      }.to_json
    end

    it 'returns the parsed block header hash' do
      http = mock_http.new(200, block_header_body)
      provider = described_class.new(http_client: http)

      header = provider.get_block_header(800_000)

      expect(header).to be_a(Hash)
      expect(header['height']).to eq(800_000)
      expect(header['merkleroot']).to eq('abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890')
    end

    it 'sends GET to the correct block header URL' do
      http = mock_http.new(200, block_header_body)
      provider = described_class.new(http_client: http)

      provider.get_block_header(800_000)

      expect(http.last_uri.to_s).to eq(
        'https://api.whatsonchain.com/v1/bsv/main/block/800000/header'
      )
    end

    it 'raises ChainProviderError on HTTP error' do
      http = mock_http.new(404, 'Block not found')
      provider = described_class.new(http_client: http)

      expect { provider.get_block_header(999_999_999) }.to raise_error(BSV::Network::ChainProviderError)
    end
  end

  describe '#valid_root_for_height?' do
    let(:merkle_root) { 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890' }

    let(:block_header_body) do
      { 'merkleroot' => merkle_root }.to_json
    end

    it 'returns true when the merkle root matches' do
      http = mock_http.new(200, block_header_body)
      provider = described_class.new(http_client: http)

      result = provider.valid_root_for_height?(merkle_root, 800_000)

      expect(result).to be(true)
    end

    it 'returns false when the merkle root does not match' do
      http = mock_http.new(200, block_header_body)
      provider = described_class.new(http_client: http)

      result = provider.valid_root_for_height?('000000', 800_000)

      expect(result).to be(false)
    end

    it 'returns false when the block is not found' do
      http = mock_http.new(404, 'Not found')
      provider = described_class.new(http_client: http)

      result = provider.valid_root_for_height?(merkle_root, 999_999_999)

      expect(result).to be(false)
    end
  end
end
