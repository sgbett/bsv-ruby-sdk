# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::MCP::Server do
  let(:config) { BSV::MCP::Config.new }

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
end
