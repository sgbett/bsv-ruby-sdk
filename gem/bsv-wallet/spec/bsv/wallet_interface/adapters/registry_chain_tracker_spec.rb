# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::RegistryChainTracker do
  subject(:tracker) { described_class.new(registry) }

  let(:registry) { BSV::Network::Registry.new }

  describe '#valid_root_for_height?(root, height)' do
    context 'when the registry returns Result::Success with true' do
      let(:provider) do
        p = double('provider') # rubocop:disable RSpec/VerifiedDoubles
        allow(p).to receive(:class).and_return(Class.new(BSV::Network::Provider) { provides :valid_root })
        allow(p).to receive(:call).with(:valid_root, 'rootabc', 850_000).and_return(
          BSV::Network::Result::Success.new(data: true)
        )
        p
      end

      before { registry.register(provider) }

      it 'returns true' do
        expect(tracker.valid_root_for_height?('rootabc', 850_000)).to be(true)
      end
    end

    context 'when the registry returns Result::Success with false' do
      let(:provider) do
        p = double('provider') # rubocop:disable RSpec/VerifiedDoubles
        allow(p).to receive(:class).and_return(Class.new(BSV::Network::Provider) { provides :valid_root })
        allow(p).to receive(:call).with(:valid_root, 'wrongroot', 850_000).and_return(
          BSV::Network::Result::Success.new(data: false)
        )
        p
      end

      before { registry.register(provider) }

      it 'returns false' do
        expect(tracker.valid_root_for_height?('wrongroot', 850_000)).to be(false)
      end
    end

    context 'when the registry returns Result::Error' do
      let(:provider) do
        p = double('provider') # rubocop:disable RSpec/VerifiedDoubles
        allow(p).to receive(:class).and_return(Class.new(BSV::Network::Provider) { provides :valid_root })
        allow(p).to receive(:call).with(:valid_root, 'root', 1).and_return(
          BSV::Network::Result::Error.new('block not found', retryable: false)
        )
        p
      end

      before { registry.register(provider) }

      it 'returns false (safe default)' do
        expect(tracker.valid_root_for_height?('root', 1)).to be(false)
      end
    end

    context 'when no :valid_root provider is registered' do
      it 'returns false rather than raising' do
        expect(tracker.valid_root_for_height?('root', 1)).to be(false)
      end
    end
  end

  describe '#current_height' do
    context 'when the registry returns Result::Success' do
      let(:provider) do
        p = double('provider') # rubocop:disable RSpec/VerifiedDoubles
        allow(p).to receive(:class).and_return(Class.new(BSV::Network::Provider) { provides :current_height })
        allow(p).to receive(:call).with(:current_height).and_return(
          BSV::Network::Result::Success.new(data: 850_000)
        )
        p
      end

      before { registry.register(provider) }

      it 'returns the height integer' do
        expect(tracker.current_height).to eq(850_000)
      end
    end

    context 'when no :current_height provider is registered' do
      it 'returns nil rather than raising' do
        expect(tracker.current_height).to be_nil
      end
    end
  end
end
