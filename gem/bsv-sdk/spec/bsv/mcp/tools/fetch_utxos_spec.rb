# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::MCP::Tools::FetchUtxos' do
  subject(:tool) { BSV::MCP::Tools::FetchUtxos }

  let(:mock_http_class) do
    Class.new do
      include FakeHttpResponse

      def initialize(code, body)
        @code = code
        @body = body
      end

      # URIs requested through this client, so specs can assert which
      # network and host a tool really talked to.
      def self.requested
        @requested ||= []
      end

      def request(uri, _req)
        self.class.requested << uri.to_s
        fake_http_response(@code, @body)
      end
    end
  end

  let(:utxo_response_body) do
    {
      'address' => '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa',
      'script' => 'deadbeef',
      'result' => [
        { 'tx_hash' => 'aabb1122', 'tx_pos' => 0, 'value' => 100_000, 'height' => 800_000 },
        { 'tx_hash' => 'ccdd3344', 'tx_pos' => 2, 'value' => 50_000, 'height' => 0 }
      ],
      'error' => ''
    }.to_json
  end

  let(:address) { '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa' }
  let(:testnet_address) { BSV::Primitives::PrivateKey.generate.public_key.address(network: :testnet) }

  # Inject the fake HTTP client but keep the network the tool asked for, so
  # the requested URIs show which network was really used.
  def stub_woc(code, body)
    http = mock_http_class.new(code, body)
    allow(BSV::Network::Providers::WhatsOnChain).to receive(:default).and_wrap_original do |original, **opts|
      original.call(**opts, http_client: http)
    end
  end

  describe '.call' do
    context 'with a successful response' do
      before { stub_woc(200, utxo_response_body) }

      it 'returns an MCP::Tool::Response' do
        response = tool.call(address: address)
        expect(response).to be_a(MCP::Tool::Response)
      end

      it 'is not an error response' do
        response = tool.call(address: address)
        expect(response.error?).to be false
      end

      it 'returns an array of UTXOs' do
        result = JSON.parse(tool.call(address: address).content.first[:text], symbolize_names: true)
        expect(result[:utxos]).to be_an(Array)
        expect(result[:utxos].length).to eq(2)
      end

      it 'maps UTXO fields correctly' do
        result = JSON.parse(tool.call(address: address).content.first[:text], symbolize_names: true)
        first = result[:utxos].first
        expect(first[:tx_hash]).to eq('aabb1122')
        expect(first[:tx_pos]).to eq(0)
        expect(first[:satoshis]).to eq(100_000)
        expect(first[:height]).to eq(800_000)
      end

      it 'includes the address in the result' do
        result = JSON.parse(tool.call(address: address).content.first[:text], symbolize_names: true)
        expect(result[:address]).to eq(address)
      end

      it 'includes the network in the result' do
        result = JSON.parse(tool.call(address: address).content.first[:text], symbolize_names: true)
        expect(result[:network]).to eq('mainnet')
      end

      it 'includes structured_content' do
        response = tool.call(address: address)
        expect(response.structured_content[:utxos]).to be_an(Array)
      end
    end

    context 'when querying testnet' do
      it 'passes testnet to the provider' do
        stub_woc(200, '[]')

        result = JSON.parse(tool.call(address: testnet_address, network: 'testnet').content.first[:text], symbolize_names: true)
        expect(result[:network]).to eq('testnet')
        expect(mock_http_class.requested).not_to be_empty
        expect(mock_http_class.requested).to all(include('/v1/bsv/test/'))
      end
    end

    context 'when the API returns an error' do
      before { stub_woc(404, 'Address not found') }

      it 'returns an error response' do
        response = tool.call(address: address)
        expect(response.error?).to be true
      end

      it 'includes the error message' do
        result = JSON.parse(tool.call(address: address).content.first[:text], symbolize_names: true)
        expect(result[:error]).to be_a(String)
        expect(result[:error]).not_to be_empty
      end

      it 'includes the HTTP status code in the error message' do
        result = JSON.parse(tool.call(address: address).content.first[:text], symbolize_names: true)
        expect(result[:error]).to include('404')
      end
    end
  end

  describe '.call input validation' do
    let(:private_key) { BSV::Primitives::PrivateKey.generate }
    let(:p2sh_address) { BSV::Primitives::Base58.check_encode("\x05".b + ("\x11".b * 20)) }

    before { allow(BSV::Network::Providers::WhatsOnChain).to receive(:default).and_raise('nothing may be requested') }

    [
      ['a testnet address on mainnet', ->(key) { key.public_key.address(network: :testnet) }, nil],
      ['a mainnet address on testnet', ->(key) { key.public_key.address(network: :mainnet) }, 'testnet'],
      ['a WIF', lambda(&:to_wif), nil],
      ['a P2SH address', ->(_key) { BSV::Primitives::Base58.check_encode("\x05".b + ("\x11".b * 20)) }, nil],
      ['a bad checksum', ->(key) { "#{key.public_key.address[0..-2]}#{key.public_key.address[-1] == '2' ? '3' : '2'}" }, nil],
      ['bad characters', ->(key) { key.public_key.address.sub(/.\z/, '0') }, nil],
      ['an empty string', ->(_key) { '' }, nil]
    ].each do |label, build, network|
      it "rejects #{label} without a request or echoing the input" do
        input = build.call(private_key)
        response = tool.call(address: input, **(network ? { network: network } : {}))
        expect(response.error?).to be true
        expect(response.content.first[:text]).not_to include(input) unless input.empty?
        expect(JSON.parse(response.content.first[:text])['error']).to include('not a P2PKH address for')
      end
    end
  end
end
