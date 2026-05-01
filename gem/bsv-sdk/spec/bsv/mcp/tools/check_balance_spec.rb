# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::MCP::Tools::CheckBalance' do
  subject(:tool) { BSV::MCP::Tools::CheckBalance }

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
      { 'tx_hash' => 'ccdd3344', 'tx_pos' => 1, 'value' => 50_000,  'height' => 0 }
    ].to_json
  end

  let(:address) { '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa' }

  def stub_woc(code, body, network: :mainnet)
    http = mock_http_class.new(code, body)
    provider = BSV::Network::Providers::WhatsOnChain.default(network: network, http_client: http)
    allow(BSV::Network::Providers::WhatsOnChain).to receive(:default).and_return(provider)
  end

  describe '.call with an address' do
    before { stub_woc(200, utxo_response_body) }

    it 'returns an MCP::Tool::Response' do
      expect(tool.call(address_or_wif: address)).to be_a(MCP::Tool::Response)
    end

    it 'is not an error response' do
      expect(tool.call(address_or_wif: address).error?).to be false
    end

    it 'returns the correct balance' do
      result = JSON.parse(tool.call(address_or_wif: address).content.first.text, symbolize_names: true)
      expect(result[:balance_satoshis]).to eq(150_000)
    end

    it 'returns the correct utxo_count' do
      result = JSON.parse(tool.call(address_or_wif: address).content.first.text, symbolize_names: true)
      expect(result[:utxo_count]).to eq(2)
    end

    it 'returns the address' do
      result = JSON.parse(tool.call(address_or_wif: address).content.first.text, symbolize_names: true)
      expect(result[:address]).to eq(address)
    end

    it 'returns the network' do
      result = JSON.parse(tool.call(address_or_wif: address).content.first.text, symbolize_names: true)
      expect(result[:network]).to eq('mainnet')
    end

    it 'returns utxo details' do
      result = JSON.parse(tool.call(address_or_wif: address).content.first.text, symbolize_names: true)
      first = result[:utxos].first
      expect(first[:tx_hash]).to eq('aabb1122')
      expect(first[:satoshis]).to eq(100_000)
    end

    it 'includes structured_content' do
      response = tool.call(address_or_wif: address)
      expect(response.structured_content[:balance_satoshis]).to eq(150_000)
    end
  end

  describe '.call with a WIF key' do
    let(:private_key) { BSV::Primitives::PrivateKey.generate }
    let(:derived_address) { private_key.public_key.address(network: :mainnet) }

    before { stub_woc(200, utxo_response_body) }

    it 'derives the address from the WIF and returns it' do
      result = JSON.parse(tool.call(address_or_wif: private_key.to_wif).content.first.text, symbolize_names: true)
      expect(result[:address]).to eq(derived_address)
    end

    it 'returns the correct balance' do
      result = JSON.parse(tool.call(address_or_wif: private_key.to_wif).content.first.text, symbolize_names: true)
      expect(result[:balance_satoshis]).to eq(150_000)
    end
  end

  describe '.call with empty UTXOs' do
    before { stub_woc(200, '[]') }

    it 'returns zero balance' do
      result = JSON.parse(tool.call(address_or_wif: address).content.first.text, symbolize_names: true)
      expect(result[:balance_satoshis]).to eq(0)
      expect(result[:utxo_count]).to eq(0)
    end
  end

  describe '.call with testnet' do
    before { stub_woc(200, utxo_response_body, network: :testnet) }

    it 'reports testnet in the result' do
      result = JSON.parse(tool.call(address_or_wif: address, network: 'testnet').content.first.text, symbolize_names: true)
      expect(result[:network]).to eq('testnet')
    end
  end

  describe '.call when the API returns an error' do
    before { stub_woc(404, 'Not found') }

    it 'returns an error response' do
      expect(tool.call(address_or_wif: address).error?).to be true
    end

    it 'includes the error message' do
      result = JSON.parse(tool.call(address_or_wif: address).content.first.text, symbolize_names: true)
      expect(result[:error]).not_to be_nil
    end
  end
end
