# frozen_string_literal: true

require 'spec_helper'
require 'pp'

RSpec.describe BSV::MCP::Secret do
  subject(:secret) { described_class.new('hunter2') }

  it 'returns the value from reveal' do
    expect(secret.reveal).to eq('hunter2')
  end

  it 'redacts inspect, to_s, interpolation and JSON' do
    outputs = [secret.inspect, secret.to_s, "key=#{secret}", secret.to_json, { key: secret }.to_json, { key: secret }.inspect]
    expect(outputs.join).not_to include('hunter2')
  end

  it 'does not leak through pretty printing' do
    expect(secret.pretty_inspect).not_to include('hunter2')
  end

  describe '.reveal' do
    it 'unwraps a Secret' do
      expect(described_class.reveal(secret)).to eq('hunter2')
    end

    it 'passes other values through' do
      expect(described_class.reveal('plain')).to eq('plain')
      expect(described_class.reveal(nil)).to be_nil
    end
  end
end
