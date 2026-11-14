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
      include FakeHttpResponse

      def initialize(code, body)
        @code = code
        @body = body
      end

      def request(_uri, req)
        body = @body.respond_to?(:call) ? @body.call(req) : @body
        fake_http_response(@code, body)
      end
    end
  end

  # The txid of the transaction a broadcast request carries (the tool
  # submits Extended Format hex).
  def submitted_txid(req)
    BSV::Transaction::Tx.from_ef_hex(JSON.parse(req.body)['rawTx']).txid_hex
  end

  # The broadcast services answer {txid, status: 202, txStatus}.
  def broadcast_reply(tx_status, **overrides)
    lambda do |req|
      { 'txid' => submitted_txid(req), 'status' => 202, 'txStatus' => tx_status }.merge(overrides.transform_keys(&:to_s)).to_json
    end
  end

  def stub_woc(code, body, network: :mainnet)
    http = mock_http_class.new(code, body)
    provider = BSV::Network::Providers::WhatsOnChain.default(network: network, http_client: http)
    allow(BSV::Network::Providers::WhatsOnChain).to receive(:default).and_return(provider)
  end

  def stub_broadcaster(code, body)
    http = mock_http_class.new(code, body)
    provider = BSV::Network::Providers::GorillaPool.default(http_client: http)
    allow(BSV::Network::Providers::GorillaPool).to receive(:default).and_return(provider)
  end

  def call_tool(**opts)
    response = tool.call(wif: wif, to_address: recipient_address, satoshis: 10_000, **opts)
    [response, JSON.parse(response.content.first.text, symbolize_names: true)]
  end

  describe '.call with sufficient funds' do
    before do
      stub_woc(200, utxo_response_body)
      stub_broadcaster(200, broadcast_reply('RECEIVED'))
    end

    it 'is a successful MCP::Tool::Response' do
      response, = call_tool
      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be false
    end

    it 'returns the txid computed from the signed transaction' do
      _, result = call_tool
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
      expect(BSV::Transaction::Tx.from_hex(result[:hex]).txid_hex).to eq(result[:txid])
    end

    it 'returns the service txStatus, not the HTTP code' do
      _, result = call_tool
      expect(result[:tx_status]).to eq('RECEIVED')
    end

    it 'does not return the retired status or state fields' do
      _, result = call_tool
      expect(result.keys).to contain_exactly(:txid, :tx_status, :hex)
    end

    it 'includes structured_content with txid and tx_status' do
      response, result = call_tool
      expect(response.structured_content).to include(txid: result[:txid], tx_status: 'RECEIVED')
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
      expect(result[:error]).to include('No UTXOs')
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

    # Regression guard for #801: previously only ArgumentError was rescued,
    # so a nil WIF raised NoMethodError out of the tool handler and crashed
    # the MCP server response cycle.
    it 'returns a structured error for nil WIF (not just ArgumentError)' do
      response = tool.call(wif: nil, to_address: recipient_address, satoshis: 10_000)
      expect(response.error?).to be true
    end
  end

  describe '.call when the service rejects the broadcast with an HTTP error' do
    before do
      stub_woc(200, utxo_response_body)
      rejection_body = { 'title' => 'transaction rejected', 'detail' => 'transaction rejected', 'txStatus' => 'REJECTED' }.to_json
      stub_broadcaster(422, rejection_body)
    end

    it 'returns an error response carrying the computed txid' do
      response, result = call_tool
      expect(response.error?).to be true
      expect(result[:error]).to include('Broadcast failed')
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  describe '.call when a 2xx reply carries a rejected txStatus' do
    before { stub_woc(200, utxo_response_body) }

    %w[REJECTED DOUBLE_SPEND_ATTEMPTED INVALID MALFORMED MINED_IN_STALE_BLOCK ORPHANED].each do |status|
      it "reports #{status} as an error with the computed txid" do
        stub_broadcaster(200, broadcast_reply(status))
        response, result = call_tool
        expect(response.error?).to be true
        expect(result[:error]).to include(status)
        expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
      end
    end

    it 'reports a lower-case rejection too' do
      stub_broadcaster(200, broadcast_reply('double_spend_attempted'))
      response, = call_tool
      expect(response.error?).to be true
    end
  end

  describe '.call when the reply names a different txid' do
    before do
      stub_woc(200, utxo_response_body)
      stub_broadcaster(200, broadcast_reply('RECEIVED', txid: 'ab' * 32))
    end

    it 'returns an error carrying the computed txid' do
      response, result = call_tool
      expect(response.error?).to be true
      expect(result[:error]).to include('different txid')
      expect(result[:txid]).not_to eq('ab' * 32)
    end
  end

  describe '.call when the reply carries no txid' do
    before do
      stub_woc(200, utxo_response_body)
      stub_broadcaster(200, { 'status' => 202, 'txStatus' => 'RECEIVED' }.to_json)
    end

    it 'still returns the computed txid' do
      response, result = call_tool
      expect(response.error?).to be false
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  describe '.call with testnet' do
    before do
      stub_woc(200, utxo_response_body, network: :testnet)
      stub_broadcaster(200, broadcast_reply('RECEIVED'))
    end

    let(:testnet_key) { BSV::Primitives::PrivateKey.generate }
    let(:testnet_wif) { testnet_key.to_wif(network: :testnet) }
    let(:testnet_recipient) { testnet_key.public_key.address(network: :testnet) }

    it 'uses testnet for WhatsOnChain and Arcade' do
      response = tool.call(wif: testnet_wif, to_address: testnet_recipient, satoshis: 10_000, network: 'testnet')
      result = JSON.parse(response.content.first.text, symbolize_names: true)
      expect(result[:tx_status]).to eq('RECEIVED')
    end
  end
end
