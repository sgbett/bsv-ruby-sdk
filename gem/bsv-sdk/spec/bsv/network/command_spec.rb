# frozen_string_literal: true

RSpec.describe BSV::Network::Command do
  before { described_class.reset! }
  after  { described_class.reset!; load 'bsv/network/commands.rb' }

  let(:name)        { :broadcast }
  let(:params)      { { tx: 'Transaction' } }
  let(:returns)     { 'Result::Success' }
  let(:description) { 'Submit a transaction to the network' }

  def define_broadcast
    described_class.define(name, params: params, returns: returns, description: description)
  end

  describe '.define' do
    it 'registers and returns a Command instance' do
      cmd = define_broadcast
      expect(cmd).to be_a(described_class)
    end

    it 'coerces a String name to Symbol' do
      cmd = described_class.define('get_tx', params: {}, returns: nil, description: 'Get tx')
      expect(cmd.name).to eq(:get_tx)
    end

    it 'raises ArgumentError on duplicate name' do
      define_broadcast
      expect { define_broadcast }.to raise_error(ArgumentError, /command :broadcast already defined/)
    end

    it 'freezes the returned command' do
      cmd = define_broadcast
      expect(cmd).to be_frozen
    end
  end

  describe '.find' do
    it 'returns the command when found' do
      define_broadcast
      expect(described_class.find(:broadcast)).to be_a(described_class)
    end

    it 'returns nil for an unknown command' do
      expect(described_class.find(:nonexistent)).to be_nil
    end

    it 'coerces a String name to Symbol for lookup' do
      define_broadcast
      expect(described_class.find('broadcast')).not_to be_nil
    end
  end

  describe '.all' do
    it 'returns an empty hash when no commands are registered' do
      expect(described_class.all).to eq({})
    end

    it 'returns all registered commands keyed by Symbol name' do
      define_broadcast
      described_class.define(:get_tx, params: {}, returns: nil, description: 'Get tx')
      all = described_class.all
      expect(all.keys).to contain_exactly(:broadcast, :get_tx)
    end

    it 'returns a frozen hash' do
      define_broadcast
      expect(described_class.all).to be_frozen
    end

    it 'returns a copy — mutations do not affect the registry' do
      define_broadcast
      copy = described_class.all
      expect { copy[:extra] = :value }.to raise_error(FrozenError)
    end
  end

  describe '.reset!' do
    it 'clears all registered commands' do
      define_broadcast
      described_class.reset!
      expect(described_class.all).to be_empty
    end
  end

  describe 'instance attributes' do
    subject(:cmd) { define_broadcast }

    it 'exposes #name as a Symbol' do
      expect(cmd.name).to eq(:broadcast)
    end

    it 'exposes #params' do
      expect(cmd.params).to eq(params)
    end

    it 'exposes #returns' do
      expect(cmd.returns).to eq(returns)
    end

    it 'exposes #description' do
      expect(cmd.description).to eq(description)
    end
  end
end
