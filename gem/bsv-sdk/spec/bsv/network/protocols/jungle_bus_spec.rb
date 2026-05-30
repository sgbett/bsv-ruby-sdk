# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::Protocols::JungleBus do
  subject(:protocol) { described_class.new(base_url: 'https://junglebus.gorillapool.io', http_client: http) }

  let(:http) { FakeHttp.new(200, '{}') }

  let(:fake_http_class) do
    Class.new do
      attr_reader :last_uri, :last_request

      def initialize(code, body)
        @code = code.to_i
        @body = body
      end

      def request(uri, req)
        @last_uri     = uri
        @last_request = req
        FakeHttpResponse.fake_http_response(@code, @body)
      end
    end
  end

  def fake(code, body)
    fake_http_class.new(code, body)
  end

  before { stub_const('FakeHttp', fake_http_class) }

  # ---------------------------------------------------------------------------
  # Declared commands
  # ---------------------------------------------------------------------------

  describe '.commands' do
    it 'declares all expected commands' do
      expected = %i[get_tx get_address_meta get_address_txs get_block_header get_block_headers current_height]
      expected.each do |cmd|
        expect(described_class.commands).to include(cmd)
      end
    end

    it 'has 6 commands' do
      expect(described_class.commands.size).to eq(6)
    end
  end

  # ---------------------------------------------------------------------------
  # get_tx — full transaction with metadata
  # ---------------------------------------------------------------------------

  describe '#call(:get_tx)' do
    let(:genesis_txid) { '4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b' }
    let(:tx_json) do
      {
        'id' => genesis_txid,
        'transaction' => 'AQAAAAE...base64...',
        'block_hash' => '000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f',
        'block_height' => 0,
        'block_time' => 1_231_006_505,
        'block_index' => 0,
        'addresses' => [],
        'outputs' => ['4104678afdb0...ac'],
        'output_types' => ['pubkey'],
        'merkle_proof' => nil
      }.to_json
    end

    it 'returns parsed transaction JSON' do
      http_client = fake(200, tx_json)
      proto = described_class.new(base_url: 'https://junglebus.gorillapool.io', http_client: http_client)

      result = proto.call(:get_tx, genesis_txid)

      expect(result).to be_http_success
      expect(result.data['id']).to eq(genesis_txid)
      expect(result.data['block_height']).to eq(0)
      expect(result.data['transaction']).to be_a(String)
    end

    it 'sends GET to /v1/transaction/get/{txid}' do
      http_client = fake(200, tx_json)
      proto = described_class.new(base_url: 'https://junglebus.gorillapool.io', http_client: http_client)

      proto.call(:get_tx, genesis_txid)

      expect(http_client.last_uri.path).to end_with("/v1/transaction/get/#{genesis_txid}")
    end

    it 'returns not_found on 404' do
      http_client = fake(404, 'not found')
      proto = described_class.new(base_url: 'https://junglebus.gorillapool.io', http_client: http_client)

      result = proto.call(:get_tx, 'unknown')

      expect(result).to be_http_not_found
    end
  end

  # ---------------------------------------------------------------------------
  # get_address_meta — transaction metadata for an address
  # ---------------------------------------------------------------------------

  describe '#call(:get_address_meta)' do
    let(:address) { '1AzDmXHX891VQovic5A7iqrW3AnikSf6tm' }
    let(:meta_json) do
      [{ 'transaction_id' => 'abc123', 'block_height' => 948_120,
         'block_hash' => 'def456', 'block_index' => 12_992 }].to_json
    end

    it 'returns parsed address metadata' do
      http_client = fake(200, meta_json)
      proto = described_class.new(base_url: 'https://junglebus.gorillapool.io', http_client: http_client)

      result = proto.call(:get_address_meta, address)

      expect(result).to be_http_success
      expect(result.data).to be_an(Array)
      expect(result.data.first['transaction_id']).to eq('abc123')
    end

    it 'sends GET to /v1/address/get/{address}' do
      http_client = fake(200, meta_json)
      proto = described_class.new(base_url: 'https://junglebus.gorillapool.io', http_client: http_client)

      proto.call(:get_address_meta, address)

      expect(http_client.last_uri.path).to end_with("/v1/address/get/#{address}")
    end
  end

  # ---------------------------------------------------------------------------
  # get_address_txs — full transaction documents for an address
  # ---------------------------------------------------------------------------

  describe '#call(:get_address_txs)' do
    let(:address) { '1AzDmXHX891VQovic5A7iqrW3AnikSf6tm' }
    let(:txs_json) do
      [{ 'id' => 'abc123', 'transaction' => 'AQAAAA...', 'block_height' => 948_120 }].to_json
    end

    it 'returns parsed transaction documents' do
      http_client = fake(200, txs_json)
      proto = described_class.new(base_url: 'https://junglebus.gorillapool.io', http_client: http_client)

      result = proto.call(:get_address_txs, address)

      expect(result).to be_http_success
      expect(result.data).to be_an(Array)
      expect(result.data.first['id']).to eq('abc123')
    end

    it 'sends GET to /v1/address/transactions/{address}' do
      http_client = fake(200, txs_json)
      proto = described_class.new(base_url: 'https://junglebus.gorillapool.io', http_client: http_client)

      proto.call(:get_address_txs, address)

      expect(http_client.last_uri.path).to end_with("/v1/address/transactions/#{address}")
    end
  end

  # ---------------------------------------------------------------------------
  # get_block_header — single block header by height
  # ---------------------------------------------------------------------------

  describe '#call(:get_block_header)' do
    let(:header_json) do
      {
        'hash' => '000000000000000001d956714215d96ffc00e0afda4cd0a96c96f8d802b1662b',
        'coin' => 1,
        'height' => 556_767,
        'time' => 1_542_305_817,
        'nonce' => 1_301_274_612,
        'version' => 536_870_912,
        'merkleroot' => 'da2b9eb7e8a3619734a17b55c47bdd6fd855b0afa9c7e14e3a164a279e51bba9',
        'bits' => '18021fdb',
        'synced' => 68_705
      }.to_json
    end

    it 'returns parsed block header' do
      http_client = fake(200, header_json)
      proto = described_class.new(base_url: 'https://junglebus.gorillapool.io', http_client: http_client)

      result = proto.call(:get_block_header, 556_767)

      expect(result).to be_http_success
      expect(result.data['height']).to eq(556_767)
      expect(result.data['hash']).to start_with('0000000000')
    end

    it 'sends GET to /v1/block_header/get/{height}' do
      http_client = fake(200, header_json)
      proto = described_class.new(base_url: 'https://junglebus.gorillapool.io', http_client: http_client)

      proto.call(:get_block_header, 556_767)

      expect(http_client.last_uri.path).to end_with('/v1/block_header/get/556767')
    end

    it 'returns not_found on 404' do
      http_client = fake(404, 'not found')
      proto = described_class.new(base_url: 'https://junglebus.gorillapool.io', http_client: http_client)

      result = proto.call(:get_block_header, 99_999_999)

      expect(result).to be_http_not_found
    end
  end

  # ---------------------------------------------------------------------------
  # get_block_headers — block headers from a height
  # ---------------------------------------------------------------------------

  describe '#call(:get_block_headers)' do
    let(:headers_json) do
      [
        { 'hash' => 'abc', 'height' => 948_120, 'time' => 1_778_184_660 },
        { 'hash' => 'def', 'height' => 948_121, 'time' => 1_778_185_691 }
      ].to_json
    end

    it 'returns an array of block headers' do
      http_client = fake(200, headers_json)
      proto = described_class.new(base_url: 'https://junglebus.gorillapool.io', http_client: http_client)

      result = proto.call(:get_block_headers, 948_120)

      expect(result).to be_http_success
      expect(result.data).to be_an(Array)
      expect(result.data.length).to eq(2)
      expect(result.data[0]['height']).to eq(948_120)
    end

    it 'sends GET to /v1/block_header/list/{height}' do
      http_client = fake(200, headers_json)
      proto = described_class.new(base_url: 'https://junglebus.gorillapool.io', http_client: http_client)

      proto.call(:get_block_headers, 948_120)

      expect(http_client.last_uri.path).to end_with('/v1/block_header/list/948120')
    end
  end

  # ---------------------------------------------------------------------------
  # current_height — chain tip height
  # ---------------------------------------------------------------------------

  describe '#call(:current_height)' do
    let(:tip_json) do
      {
        'hash' => '000000000000000001d956714215d96ffc00e0afda4cd0a96c96f8d802b1662b',
        'height' => 951_235,
        'merkleroot' => 'da2b9eb7e8a3619734a17b55c47bdd6fd855b0afa9c7e14e3a164a279e51bba9',
        'time' => 1_778_200_000
      }.to_json
    end

    it 'returns the tip height as an Integer' do
      http_client = fake(200, tip_json)
      proto = described_class.new(base_url: 'https://junglebus.gorillapool.io', http_client: http_client)

      result = proto.call(:current_height)

      expect(result).to be_http_success
      expect(result.data).to be_an(Integer)
      expect(result.data).to eq(951_235)
    end

    it 'sends GET to /v1/block_header/tip' do
      http_client = fake(200, tip_json)
      proto = described_class.new(base_url: 'https://junglebus.gorillapool.io', http_client: http_client)

      proto.call(:current_height)

      expect(http_client.last_uri.path).to end_with('/v1/block_header/tip')
    end
  end
end
