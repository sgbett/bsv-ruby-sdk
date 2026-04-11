# frozen_string_literal: true

RSpec.describe 'BSV::MCP::Tools::FetchTx' do
  subject(:tool) { BSV::MCP::Tools::FetchTx }

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

  # Minimal valid coinbase-style transaction hex
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

  let(:txid) { 'abc1234500000000000000000000000000000000000000000000000000000000' }

  describe '.call' do
    context 'with a successful response' do
      before do
        http = mock_http_class.new(200, raw_tx_hex)
        allow(BSV::Network::WhatsOnChain).to receive(:new).and_return(
          BSV::Network::WhatsOnChain.new(http_client: http)
        )
      end

      it 'returns an MCP::Tool::Response' do
        response = tool.call(txid: txid)
        expect(response).to be_a(MCP::Tool::Response)
      end

      it 'is not an error response' do
        response = tool.call(txid: txid)
        expect(response.error?).to be false
      end

      it 'returns the raw hex' do
        result = JSON.parse(tool.call(txid: txid).content.first.text, symbolize_names: true)
        expect(result[:hex]).to be_a(String)
        expect(result[:hex]).not_to be_empty
      end

      it 'returns the txid in display byte order' do
        result = JSON.parse(tool.call(txid: txid).content.first.text, symbolize_names: true)
        expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
      end

      it 'returns version 1' do
        result = JSON.parse(tool.call(txid: txid).content.first.text, symbolize_names: true)
        expect(result[:version]).to eq(1)
      end

      it 'returns inputs array' do
        result = JSON.parse(tool.call(txid: txid).content.first.text, symbolize_names: true)
        expect(result[:inputs]).to be_an(Array)
        expect(result[:inputs].length).to eq(1)
      end

      it 'returns outputs array' do
        result = JSON.parse(tool.call(txid: txid).content.first.text, symbolize_names: true)
        expect(result[:outputs]).to be_an(Array)
        expect(result[:outputs].length).to eq(1)
      end

      it 'includes the network in the result' do
        result = JSON.parse(tool.call(txid: txid).content.first.text, symbolize_names: true)
        expect(result[:network]).to eq('mainnet')
      end

      it 'includes structured_content' do
        response = tool.call(txid: txid)
        expect(response.structured_content[:txid]).to be_a(String)
        expect(response.structured_content[:hex]).to be_a(String)
      end
    end

    context 'when the API returns an error' do
      before do
        http = mock_http_class.new(404, 'Transaction not found')
        allow(BSV::Network::WhatsOnChain).to receive(:new).and_return(
          BSV::Network::WhatsOnChain.new(http_client: http)
        )
      end

      it 'returns an error response' do
        response = tool.call(txid: 'unknowntxid')
        expect(response.error?).to be true
      end

      it 'includes the error message' do
        result = JSON.parse(tool.call(txid: 'unknowntxid').content.first.text, symbolize_names: true)
        expect(result[:error]).to be_a(String)
        expect(result[:error]).not_to be_empty
      end

      it 'includes the HTTP status code' do
        result = JSON.parse(tool.call(txid: 'unknowntxid').content.first.text, symbolize_names: true)
        expect(result[:status_code]).to eq(404)
      end
    end

    context 'when querying testnet' do
      it 'passes testnet to WhatsOnChain' do
        http = mock_http_class.new(200, raw_tx_hex)
        woc = BSV::Network::WhatsOnChain.new(network: :testnet, http_client: http)
        allow(BSV::Network::WhatsOnChain).to receive(:new).with(network: :testnet).and_return(woc)

        result = JSON.parse(tool.call(txid: txid, network: 'testnet').content.first.text, symbolize_names: true)
        expect(result[:network]).to eq('testnet')
      end
    end
  end
end
