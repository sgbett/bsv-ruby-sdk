# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::MCP::Tools::FetchUtxos' do
  subject(:tool) { BSV::MCP::Tools::FetchUtxos }

  let(:mock_http_class) do
    Class.new do
      def initialize(code, body)
        @code = code
        @body = body
      end

      def request(_uri, _req)
        Struct.new(:code, :body).new(@code.to_s, @body)
      end
    end
  end

  let(:utxo_response_body) do
    [
      { 'tx_hash' => 'aabb1122', 'tx_pos' => 0, 'value' => 100_000, 'height' => 800_000 },
      { 'tx_hash' => 'ccdd3344', 'tx_pos' => 2, 'value' => 50_000, 'height' => 0 }
    ].to_json
  end

  let(:address) { '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa' }

  def stub_woc(code, body, network: :mainnet)
    http = mock_http_class.new(code, body)
    provider = BSV::Network::Providers::WhatsOnChain.default(network: network, http_client: http)
    allow(BSV::Network::Providers::WhatsOnChain).to receive(:default).and_return(provider)
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
        result = JSON.parse(tool.call(address: address).content.first.text, symbolize_names: true)
        expect(result[:utxos]).to be_an(Array)
        expect(result[:utxos].length).to eq(2)
      end

      it 'maps UTXO fields correctly' do
        result = JSON.parse(tool.call(address: address).content.first.text, symbolize_names: true)
        first = result[:utxos].first
        expect(first[:tx_hash]).to eq('aabb1122')
        expect(first[:tx_pos]).to eq(0)
        expect(first[:satoshis]).to eq(100_000)
        expect(first[:height]).to eq(800_000)
      end

      it 'includes the address in the result' do
        result = JSON.parse(tool.call(address: address).content.first.text, symbolize_names: true)
        expect(result[:address]).to eq(address)
      end

      it 'includes the network in the result' do
        result = JSON.parse(tool.call(address: address).content.first.text, symbolize_names: true)
        expect(result[:network]).to eq('mainnet')
      end

      it 'includes structured_content' do
        response = tool.call(address: address)
        expect(response.structured_content[:utxos]).to be_an(Array)
      end
    end

    context 'when querying testnet' do
      it 'passes testnet to the provider' do
        stub_woc(200, '[]', network: :testnet)

        result = JSON.parse(tool.call(address: address, network: 'testnet').content.first.text, symbolize_names: true)
        expect(result[:network]).to eq('testnet')
      end
    end

    context 'when the API returns an error' do
      before { stub_woc(404, 'Address not found') }

      it 'returns an error response' do
        response = tool.call(address: 'invalid')
        expect(response.error?).to be true
      end

      it 'includes the error message' do
        result = JSON.parse(tool.call(address: 'invalid').content.first.text, symbolize_names: true)
        expect(result[:error]).to be_a(String)
        expect(result[:error]).not_to be_empty
      end

      it 'includes the HTTP status code in the error message' do
        result = JSON.parse(tool.call(address: 'invalid').content.first.text, symbolize_names: true)
        expect(result[:error]).to include('404')
      end
    end
  end
end
