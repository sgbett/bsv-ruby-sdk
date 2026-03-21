# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'BSV::X402' do
  it 'exposes the VERSION constant matching semver' do
    expect(BSV::X402::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it 'makes BSV::Primitives available transitively via bsv-sdk' do
    expect(defined?(BSV::Primitives)).to eq('constant')
  end

  it 'makes BSV::Transaction available transitively via bsv-sdk' do
    expect(defined?(BSV::Transaction)).to eq('constant')
  end

  describe '.configure' do
    after { BSV::X402.reset_configuration! }

    it 'yields the configuration object' do
      yielded = nil
      BSV::X402.configure { |c| yielded = c }
      expect(yielded).to be_a(BSV::X402::Configuration)
    end

    it 'persists values set in the block' do
      BSV::X402.configure { |c| c.amount_sats = 500 }
      expect(BSV::X402.configuration.amount_sats).to eq(500)
    end
  end

  describe '.configuration' do
    after { BSV::X402.reset_configuration! }

    it 'returns a Configuration instance' do
      expect(BSV::X402.configuration).to be_a(BSV::X402::Configuration)
    end

    it 'returns the same object on repeated calls' do
      expect(BSV::X402.configuration).to equal(BSV::X402.configuration)
    end
  end

  describe '.reset_configuration!' do
    it 'restores defaults' do
      BSV::X402.configure { |c| c.amount_sats = 9999 }
      BSV::X402.reset_configuration!
      expect(BSV::X402.configuration.amount_sats).to eq(100)
    end
  end
end
