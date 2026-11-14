# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::MCP::Server do
  let(:config) { BSV::MCP::Config.new }
  let(:secret_key) { 'arc-secret-key-1234' }
  let(:arc_url) { 'https://arc.example.com' }
  let(:configured) do
    BSV::MCP::Config.new(network: 'testnet', arc_url: arc_url, arc_api_key: secret_key)
  end

  describe '.build' do
    subject(:server) { described_class.build(config) }

    it 'returns an MCP::Server instance' do
      expect(server).to be_a(MCP::Server)
    end

    it 'sets the server name to bsv-sdk' do
      expect(server.name).to eq('bsv-sdk')
    end

    it 'sets the version from BSV::VERSION' do
      expect(server.version).to eq(BSV::VERSION)
    end

    it 'includes the network in the instructions' do
      expect(server.instructions).to include(config.network)
    end

    it 'registers all six tools' do
      tool_names = server.tools.keys
      expect(tool_names).to include('generate_key', 'decode_tx', 'fetch_utxos', 'fetch_tx',
                                    'check_balance', 'broadcast_p2pkh')
    end

    it 'uses Config.new when no config is given' do
      built = described_class.build
      expect(built).to be_a(MCP::Server)
    end
  end

  describe '.server_context' do
    subject(:context) { described_class.server_context(configured) }

    it 'carries the network, ARC URL and key' do
      expect(context).to include(bsv_network: 'testnet', arc_url: arc_url)
      expect(BSV::MCP::Secret.reveal(context[:arc_api_key])).to eq(secret_key)
    end

    it 'is frozen' do
      expect(context).to be_frozen
    end

    it 'omits the key when none is configured' do
      expect(described_class.server_context(config)[:arc_api_key]).to be_nil
    end

    it 'is passed to the MCP server' do
      passed = described_class.build(configured).server_context
      expect(passed).to include(bsv_network: 'testnet', arc_url: arc_url)
      expect(BSV::MCP::Secret.reveal(passed[:arc_api_key])).to eq(secret_key)
    end
  end

  describe 'key hygiene' do
    let(:server) { described_class.build(configured) }

    it 'keeps the key out of Config#inspect' do
      expect(configured.inspect).not_to include(secret_key)
    end

    it 'keeps the key out of the server context inspect and JSON' do
      context = described_class.server_context(configured)
      expect(context.inspect + context.to_json).not_to include(secret_key)
    end

    it 'keeps the key out of the MCP::Server inspect' do
      expect(server.inspect).not_to include(secret_key)
    end

    it 'keeps the key and URL out of the instructions' do
      expect(server.instructions).not_to include(secret_key)
      expect(server.instructions).not_to include(arc_url)
    end
  end
end
