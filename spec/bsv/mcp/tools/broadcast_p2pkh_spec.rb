# frozen_string_literal: true

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
    [
      {
        'tx_hash' => 'a' * 64,
        'tx_pos' => 0,
        'value' => 100_000,
        'height' => 800_000
      }
    ].to_json
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

  let(:arc_success_response) do
    BSV::Network::BroadcastResponse.new(
      txid: 'deadbeef' * 8,
      tx_status: 'SEEN_ON_NETWORK'
    )
  end

  def stub_woc(code, body, network: :mainnet)
    http = mock_http_class.new(code, body)
    allow(BSV::Network::WhatsOnChain).to receive(:new).with(network: network).and_return(
      BSV::Network::WhatsOnChain.new(network: network, http_client: http)
    )
  end

  def stub_arc_success
    arc = instance_double(BSV::Network::ARC, broadcast: arc_success_response)
    allow(BSV::Network::ARC).to receive(:default).and_return(arc)
    arc
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

    it 'broadcasts with Extended Format (inputs have source data set)' do
      arc = instance_double(BSV::Network::ARC)
      allow(arc).to receive(:broadcast) do |tx|
        tx.inputs.each do |inp|
          expect(inp.source_satoshis).not_to be_nil
          expect(inp.source_locking_script).not_to be_nil
        end
        arc_success_response
      end
      allow(BSV::Network::ARC).to receive(:default).and_return(arc)

      tool.call(wif: wif, to_address: recipient_address, satoshis: 10_000)
    end

    it 'includes the payment output with the requested satoshis' do
      arc = instance_double(BSV::Network::ARC)
      allow(arc).to receive(:broadcast) do |tx|
        payment_output = tx.outputs.find { |o| !o.change }
        expect(payment_output.satoshis).to eq(10_000)
        arc_success_response
      end
      allow(BSV::Network::ARC).to receive(:default).and_return(arc)

      tool.call(wif: wif, to_address: recipient_address, satoshis: 10_000)
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
    before { stub_woc(200, utxo_response_body) }

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
      arc = instance_double(BSV::Network::ARC)
      allow(arc).to receive(:broadcast).and_raise(
        BSV::Network::BroadcastError.new('transaction rejected', status_code: 422)
      )
      allow(BSV::Network::ARC).to receive(:default).and_return(arc)
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
      arc = instance_double(BSV::Network::ARC, broadcast: arc_success_response)
      allow(BSV::Network::ARC).to receive(:default).with(testnet: true).and_return(arc)

      tool.call(wif: testnet_wif, to_address: testnet_recipient, satoshis: 10_000, network: 'testnet')

      expect(BSV::Network::ARC).to have_received(:default).with(testnet: true)
    end
  end
end
