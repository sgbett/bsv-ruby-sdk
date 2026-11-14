# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::MCP::Tools::FetchTx' do
  subject(:tool) { BSV::MCP::Tools::FetchTx }

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
      before { stub_woc(200, raw_tx_hex) }

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
      before { stub_woc(404, 'Transaction not found') }

      it 'returns an error response' do
        response = tool.call(txid: 'unknowntxid')
        expect(response.error?).to be true
      end

      it 'includes the error message' do
        result = JSON.parse(tool.call(txid: 'unknowntxid').content.first.text, symbolize_names: true)
        expect(result[:error]).to be_a(String)
        expect(result[:error]).not_to be_empty
      end

      it 'includes the HTTP status code in the error message' do
        result = JSON.parse(tool.call(txid: 'unknowntxid').content.first.text, symbolize_names: true)
        expect(result[:error]).to include('404')
      end
    end

    context 'when querying testnet' do
      it 'passes testnet to the provider' do
        stub_woc(200, raw_tx_hex)

        result = JSON.parse(tool.call(txid: txid, network: 'testnet').content.first.text, symbolize_names: true)
        expect(result[:network]).to eq('testnet')
        expect(mock_http_class.requested).to all(include('/v1/bsv/test/'))
      end
    end
  end
end
