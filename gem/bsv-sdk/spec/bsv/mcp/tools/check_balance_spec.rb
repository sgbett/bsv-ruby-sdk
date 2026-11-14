# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::MCP::Tools::CheckBalance' do
  subject(:tool) { BSV::MCP::Tools::CheckBalance }

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
        { 'tx_hash' => 'ccdd3344', 'tx_pos' => 1, 'value' => 50_000,  'height' => 0 }
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

  describe '.call with an address' do
    before { stub_woc(200, utxo_response_body) }

    it 'returns an MCP::Tool::Response' do
      expect(tool.call(address_or_wif: address)).to be_a(MCP::Tool::Response)
    end

    it 'is not an error response' do
      expect(tool.call(address_or_wif: address).error?).to be false
    end

    it 'returns the correct balance' do
      result = JSON.parse(tool.call(address_or_wif: address).content.first[:text], symbolize_names: true)
      expect(result[:balance_satoshis]).to eq(150_000)
    end

    it 'returns the correct utxo_count' do
      result = JSON.parse(tool.call(address_or_wif: address).content.first[:text], symbolize_names: true)
      expect(result[:utxo_count]).to eq(2)
    end

    it 'returns the address' do
      result = JSON.parse(tool.call(address_or_wif: address).content.first[:text], symbolize_names: true)
      expect(result[:address]).to eq(address)
    end

    it 'returns the network' do
      result = JSON.parse(tool.call(address_or_wif: address).content.first[:text], symbolize_names: true)
      expect(result[:network]).to eq('mainnet')
    end

    it 'returns utxo details' do
      result = JSON.parse(tool.call(address_or_wif: address).content.first[:text], symbolize_names: true)
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
      result = JSON.parse(tool.call(address_or_wif: private_key.to_wif).content.first[:text], symbolize_names: true)
      expect(result[:address]).to eq(derived_address)
    end

    it 'returns the correct balance' do
      result = JSON.parse(tool.call(address_or_wif: private_key.to_wif).content.first[:text], symbolize_names: true)
      expect(result[:balance_satoshis]).to eq(150_000)
    end
  end

  describe '.call with empty UTXOs' do
    before { stub_woc(200, '[]') }

    it 'returns zero balance' do
      result = JSON.parse(tool.call(address_or_wif: address).content.first[:text], symbolize_names: true)
      expect(result[:balance_satoshis]).to eq(0)
      expect(result[:utxo_count]).to eq(0)
    end
  end

  describe '.call with testnet' do
    before { stub_woc(200, utxo_response_body) }

    it 'reports testnet in the result' do
      result = JSON.parse(tool.call(address_or_wif: testnet_address, network: 'testnet').content.first[:text], symbolize_names: true)
      expect(result[:network]).to eq('testnet')
      expect(mock_http_class.requested).not_to be_empty
      expect(mock_http_class.requested).to all(include('/v1/bsv/test/'))
    end
  end

  describe '.call when the API returns an error' do
    before { stub_woc(404, 'Not found') }

    it 'returns an error response' do
      expect(tool.call(address_or_wif: address).error?).to be true
    end

    it 'includes the error message' do
      result = JSON.parse(tool.call(address_or_wif: address).content.first[:text], symbolize_names: true)
      expect(result[:error]).not_to be_nil
    end
  end

  describe '.call input validation' do
    let(:key) { BSV::Primitives::PrivateKey.generate }

    before { allow(BSV::Network::Providers::WhatsOnChain).to receive(:default).and_raise('nothing may be requested') }

    {
      'a testnet address on mainnet' => ->(k) { [k.public_key.address(network: :testnet), nil] },
      'a mainnet address on testnet' => ->(k) { [k.public_key.address(network: :mainnet), 'testnet'] },
      'a testnet WIF on mainnet' => ->(k) { [k.to_wif(network: :testnet), nil] },
      'a mainnet WIF on testnet' => ->(k) { [k.to_wif(network: :mainnet), 'testnet'] },
      'a P2SH address' => ->(_k) { [BSV::Primitives::Base58.check_encode("\x05".b + ("\x11".b * 20)), nil] },
      'a WIF with one character replaced by 0' => ->(k) { [k.to_wif.sub(/.(.{10})\z/, '0\\1'), nil] },
      'a WIF with a bad checksum' => ->(k) { [k.to_wif[0..-2] + (k.to_wif[-1] == 'a' ? 'b' : 'a'), nil] },
      'a payload of the wrong length' => ->(_k) { [BSV::Primitives::Base58.check_encode("\x00".b + ("\x11".b * 19)), nil] }
    }.each do |label, build|
      it "rejects #{label} without a request or echoing the input" do
        input, network = build.call(key)
        response = tool.call(address_or_wif: input, **(network ? { network: network } : {}))
        text = response.content.first[:text]
        expect(response.error?).to be true
        expect(text).not_to include(input)
        expect(JSON.parse(text)['error']).to include('not a P2PKH address or WIF private key for')
      end
    end
  end

  describe '.call with a WIF for the call network' do
    before { stub_woc(200, utxo_response_body) }

    it 'accepts a compressed testnet WIF and queries the derived testnet address' do
      key = BSV::Primitives::PrivateKey.generate
      result = JSON.parse(tool.call(address_or_wif: key.to_wif(network: :testnet), network: 'testnet').content.first[:text])
      expect(result['address']).to eq(key.public_key.address(network: :testnet))
    end
  end
end
