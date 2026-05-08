# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::MCP::Tools::BroadcastP2pkh' do
  subject(:tool) { BSV::MCP::Tools::BroadcastP2pkh }

  # A deterministic private key for reproducible tests (hex of 1..32)
  let(:private_key) do
    BSV::Primitives::PrivateKey.from_hex('0101010101010101010101010101010101010101010101010101010101010101')
  end
  let(:sender_address) { private_key.public_key.address(network: :mainnet) }
  let(:wif) { private_key.to_wif }

  let(:recipient_address) { '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa' }

  # A funded UTXO worth 100_000 satoshis
  let(:utxo_response_body) do
    {
      'address' => '1test',
      'script' => 'deadbeef',
      'result' => [
        {
          'tx_hash' => 'a' * 64,
          'tx_pos' => 0,
          'value' => 100_000,
          'height' => 800_000
        }
      ],
      'error' => ''
    }.to_json
  end

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

  let(:arc_success_body) do
    {
      'txid' => 'deadbeef' * 8,
      'txStatus' => 'SEEN_ON_NETWORK',
      'title' => 'Added to mempool'
    }.to_json
  end

  def stub_woc(code, body, network: :mainnet)
    http = mock_http_class.new(code, body)
    provider = BSV::Network::Providers::WhatsOnChain.default(network: network, http_client: http)
    allow(BSV::Network::Providers::WhatsOnChain).to receive(:default).and_return(provider)
  end

  def stub_arc_success
    http = mock_http_class.new(200, arc_success_body)
    provider = BSV::Network::Providers::GorillaPool.default(http_client: http)
    arc_protocol = provider.protocol_for(:broadcast)
    allow(BSV::Network::Providers::GorillaPool).to receive(:default).and_return(provider)
    arc_protocol
  end

  def stub_arc_failure(code, body)
    http = mock_http_class.new(code, body)
    provider = BSV::Network::Providers::GorillaPool.default(http_client: http)
    allow(BSV::Network::Providers::GorillaPool).to receive(:default).and_return(provider)
  end

  describe '.call with sufficient funds' do
    before do
      stub_woc(200, utxo_response_body)
      stub_arc_success
    end

    it 'returns an MCP::Tool::Response' do
      response = tool.call(wif: wif, to_address: recipient_address, satoshis: 10_000)
      expect(response).to be_a(MCP::Tool::Response)
    end

    it 'is not an error response' do
      response = tool.call(wif: wif, to_address: recipient_address, satoshis: 10_000)
      expect(response.error?).to be false
    end

    it 'returns the txid from ARC' do
      result = JSON.parse(
        tool.call(wif: wif, to_address: recipient_address, satoshis: 10_000).content.first.text,
        symbolize_names: true
      )
      expect(result[:txid]).to eq('deadbeef' * 8)
    end

    it 'returns the tx_status from ARC' do
      result = JSON.parse(
        tool.call(wif: wif, to_address: recipient_address, satoshis: 10_000).content.first.text,
        symbolize_names: true
      )
      expect(result[:tx_status]).to eq('SEEN_ON_NETWORK')
    end

    it 'returns a hex string' do
      result = JSON.parse(
        tool.call(wif: wif, to_address: recipient_address, satoshis: 10_000).content.first.text,
        symbolize_names: true
      )
      expect(result[:hex]).to match(/\A[0-9a-f]+\z/)
    end

    it 'includes structured_content' do
      response = tool.call(wif: wif, to_address: recipient_address, satoshis: 10_000)
      expect(response.structured_content[:txid]).to eq('deadbeef' * 8)
    end
  end

  describe '.call with insufficient funds' do
    before { stub_woc(200, utxo_response_body) }

    it 'returns an error response when requesting more than available' do
      response = tool.call(wif: wif, to_address: recipient_address, satoshis: 200_000)
      expect(response.error?).to be true
    end

    it 'includes an error message mentioning insufficient funds' do
      result = JSON.parse(
        tool.call(wif: wif, to_address: recipient_address, satoshis: 200_000).content.first.text,
        symbolize_names: true
      )
      expect(result[:error]).to include('Insufficient funds')
    end
  end

  describe '.call with empty UTXO set' do
    before { stub_woc(200, '[]') }

    it 'returns an error response' do
      response = tool.call(wif: wif, to_address: recipient_address, satoshis: 10_000)
      expect(response.error?).to be true
    end

    it 'mentions no UTXOs found' do
      result = JSON.parse(
        tool.call(wif: wif, to_address: recipient_address, satoshis: 10_000).content.first.text,
        symbolize_names: true
      )
      expect(result[:error]).to match(/no utxos/i)
    end
  end

  describe '.call with an invalid WIF key' do
    it 'returns an error response' do
      response = tool.call(wif: 'not-a-valid-wif', to_address: recipient_address, satoshis: 10_000)
      expect(response.error?).to be true
    end

    it 'includes an error message' do
      result = JSON.parse(
        tool.call(wif: 'not-a-valid-wif', to_address: recipient_address, satoshis: 10_000).content.first.text,
        symbolize_names: true
      )
      expect(result[:error]).to be_a(String)
      expect(result[:error]).not_to be_empty
    end
  end

  describe '.call when ARC rejects the broadcast' do
    before do
      stub_woc(200, utxo_response_body)
      rejection_body = { 'title' => 'transaction rejected', 'detail' => 'transaction rejected', 'txStatus' => 'REJECTED' }.to_json
      stub_arc_failure(422, rejection_body)
    end

    it 'returns an error response' do
      response = tool.call(wif: wif, to_address: recipient_address, satoshis: 10_000)
      expect(response.error?).to be true
    end

    it 'includes the broadcast failure message' do
      result = JSON.parse(
        tool.call(wif: wif, to_address: recipient_address, satoshis: 10_000).content.first.text,
        symbolize_names: true
      )
      expect(result[:error]).to include('Broadcast failed')
    end
  end

  describe '.call with testnet' do
    before do
      stub_woc(200, utxo_response_body, network: :testnet)
      stub_arc_success
    end

    let(:testnet_key) { BSV::Primitives::PrivateKey.generate }
    let(:testnet_wif) { testnet_key.to_wif(network: :testnet) }
    let(:testnet_recipient) { testnet_key.public_key.address(network: :testnet) }

    it 'uses testnet for WhatsOnChain and ARC' do
      result = JSON.parse(
        tool.call(wif: testnet_wif, to_address: testnet_recipient, satoshis: 10_000, network: 'testnet').content.first.text,
        symbolize_names: true
      )
      expect(result[:txid]).to eq('deadbeef' * 8)
    end
  end
end
