# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::MCP::Tools::Helpers do
  let(:context_hash) { { bsv_network: 'testnet', arc_url: 'https://arc.example.com' } }

  def wrap(context)
    MCP::ServerContext.new(context, progress: nil, notification_target: nil)
  end

  describe '.context_value' do
    it 'reads from a raw Hash' do
      expect(described_class.context_value(context_hash, :bsv_network)).to eq('testnet')
    end

    it 'reads through an MCP::ServerContext wrapping a Hash' do
      wrapped = wrap(context_hash)
      expect(wrapped).not_to be_a(Hash)
      expect(described_class.context_value(wrapped, :bsv_network)).to eq('testnet')
    end

    it 'returns nil for an MCP::ServerContext wrapping nil' do
      expect(described_class.context_value(wrap(nil), :bsv_network)).to be_nil
    end

    it 'returns nil for a nil context' do
      expect(described_class.context_value(nil, :bsv_network)).to be_nil
    end

    it 'returns nil for a missing key' do
      expect(described_class.context_value(wrap(context_hash), :arc_api_key)).to be_nil
    end

    it 'is not redirected by a _meta entry carrying the same keys' do
      context = context_hash.merge(_meta: { bsv_network: 'mainnet', arc_url: 'https://evil.example.com' })
      wrapped = wrap(context)
      expect(described_class.context_value(wrapped, :bsv_network)).to eq('testnet')
      expect(described_class.context_value(wrapped, :arc_url)).to eq('https://arc.example.com')
    end
  end

  describe '.resolve_network_sym' do
    it 'defaults to mainnet without a context' do
      expect(described_class.resolve_network_sym(nil, nil)).to eq(:mainnet)
    end

    it 'defaults to mainnet for a context wrapping nil' do
      expect(described_class.resolve_network_sym(nil, wrap(nil))).to eq(:mainnet)
    end

    it 'falls back to the server network in a raw Hash' do
      expect(described_class.resolve_network_sym(nil, context_hash)).to eq(:testnet)
    end

    it 'falls back to the server network in a wrapped context' do
      expect(described_class.resolve_network_sym(nil, wrap(context_hash))).to eq(:testnet)
    end

    it 'prefers the per-call network' do
      expect(described_class.resolve_network_sym('mainnet', wrap(context_hash))).to eq(:mainnet)
    end

    it 'accepts a Symbol per-call network' do
      expect(described_class.resolve_network_sym(:testnet, nil)).to eq(:testnet)
    end

    %w[main test Testnet regtest stn].push('').each do |value|
      it "rejects the per-call network #{value.inspect}" do
        expect { described_class.resolve_network_sym(value, wrap(context_hash)) }
          .to raise_error(ArgumentError, /'mainnet' or 'testnet'/)
      end
    end
  end

  describe '.scrub' do
    let(:context) do
      { arc_url: 'https://arc.example.com', arc_api_key: BSV::MCP::Secret.new('s3cret') }
    end

    it 'removes the key and URL from a message' do
      scrubbed = described_class.scrub('bad s3cret at https://arc.example.com/v1/tx', wrap(context))
      expect(scrubbed).to eq('bad [REDACTED] at [REDACTED]/v1/tx')
    end

    it 'leaves a message alone when there is nothing to remove' do
      expect(described_class.scrub('plain', nil)).to eq('plain')
    end
  end
end
