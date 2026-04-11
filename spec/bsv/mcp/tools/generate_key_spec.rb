# frozen_string_literal: true

RSpec.describe 'BSV::MCP::Tools::GenerateKey' do
  subject(:tool) { BSV::MCP::Tools::GenerateKey }

  describe '.call' do
    it 'returns an MCP::Tool::Response' do
      response = tool.call
      expect(response).to be_a(MCP::Tool::Response)
    end

    it 'is not an error response' do
      response = tool.call
      expect(response.error?).to be false
    end

    it 'returns a WIF string' do
      response = tool.call
      result = JSON.parse(response.content.first.text, symbolize_names: true)
      expect(result[:wif]).to be_a(String)
      expect(result[:wif]).not_to be_empty
    end

    it 'returns a 66-character compressed public key hex' do
      response = tool.call
      result = JSON.parse(response.content.first.text, symbolize_names: true)
      expect(result[:public_key_hex].length).to eq(66)
      expect(result[:public_key_hex]).to match(/\A[0-9a-f]+\z/)
    end

    it 'returns a mainnet address starting with 1 by default' do
      response = tool.call
      result = JSON.parse(response.content.first.text, symbolize_names: true)
      expect(result[:address]).to start_with('1')
    end

    it 'returns a testnet address starting with m or n when network is testnet' do
      response = tool.call(network: 'testnet')
      result = JSON.parse(response.content.first.text, symbolize_names: true)
      expect(result[:address]).to match(/\A[mn]/)
    end

    it 'returns different keys on successive calls' do
      result_a = JSON.parse(tool.call.content.first.text, symbolize_names: true)
      result_b = JSON.parse(tool.call.content.first.text, symbolize_names: true)
      expect(result_a[:wif]).not_to eq(result_b[:wif])
    end

    it 'returns a WIF that round-trips back to the same public key' do
      result = JSON.parse(tool.call.content.first.text, symbolize_names: true)
      key = BSV::Primitives::PrivateKey.from_wif(result[:wif])
      expect(key.public_key.to_hex).to eq(result[:public_key_hex])
    end

    it 'includes the network in the result' do
      result = JSON.parse(tool.call.content.first.text, symbolize_names: true)
      expect(result[:network]).to eq('mainnet')
    end

    it 'includes structured_content matching the text content' do
      response = tool.call
      text_result = JSON.parse(response.content.first.text, symbolize_names: true)
      expect(response.structured_content[:wif]).to eq(text_result[:wif])
    end
  end
end
