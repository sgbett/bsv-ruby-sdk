# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

# These specs verify that deprecation warnings are emitted correctly.
# The suite-wide BSV_SUPPRESS_DEPRECATIONS is temporarily unset so that
# warnings can be observed; it is restored after each example.
RSpec.describe 'BSV::Wallet deprecation warnings' do
  # Reset once-per-process deprecation flags and env var around each example.
  around do |example|
    original_env = ENV.delete('BSV_SUPPRESS_DEPRECATIONS')

    # Reset all class-level deprecation flags so each spec starts fresh.
    [
      BSV::Wallet::ChainProvider,
      BSV::Wallet::WhatsOnChainProvider,
      BSV::Wallet::NullChainProvider,
      BSV::Wallet::LegacyChainProviderAdapter,
      BSV::Wallet::LegacyBroadcasterAdapter,
      BSV::Wallet::WalletClient
    ].each do |klass|
      klass.instance_variable_set(:@deprecation_warnings, {})
    end

    # ChainProvider module tracks its own instance variable directly.
    BSV::Wallet::ChainProvider.instance_variable_set(:@deprecation_warnings, {})

    example.run
  ensure
    ENV['BSV_SUPPRESS_DEPRECATIONS'] = original_env if original_env
  end

  describe 'ChainProvider module inclusion' do
    it 'emits a deprecation warning when included' do
      expect do
        Class.new { include BSV::Wallet::ChainProvider }
      end.to output(/\[DEPRECATION\].*ChainProvider.*deprecated/i).to_stderr
    end

    it 'emits the warning only once per process' do
      Class.new { include BSV::Wallet::ChainProvider }
      expect do
        Class.new { include BSV::Wallet::ChainProvider }
      end.not_to output.to_stderr
    end
  end

  describe 'NullChainProvider.new' do
    it 'emits a deprecation warning' do
      expect { BSV::Wallet::NullChainProvider.new }
        .to output(/\[DEPRECATION\].*NullChainProvider.*deprecated/i).to_stderr
    end

    it 'emits the warning only once per process' do
      BSV::Wallet::NullChainProvider.new
      expect { BSV::Wallet::NullChainProvider.new }.not_to output.to_stderr
    end
  end

  describe 'WhatsOnChainProvider.new' do
    it 'emits a deprecation warning' do
      expect { BSV::Wallet::WhatsOnChainProvider.new }
        .to output(/\[DEPRECATION\].*WhatsOnChainProvider.*deprecated/i).to_stderr
    end

    it 'emits the warning only once per process' do
      BSV::Wallet::WhatsOnChainProvider.new
      expect { BSV::Wallet::WhatsOnChainProvider.new }.not_to output.to_stderr
    end
  end

  describe 'LegacyChainProviderAdapter.new (chain_provider: param)' do
    let(:stub_provider) { double('chain_provider') } # rubocop:disable RSpec/VerifiedDoubles

    it 'emits a deprecation warning for chain_provider:' do
      expect { BSV::Wallet::LegacyChainProviderAdapter.new(stub_provider) }
        .to output(/\[DEPRECATION\].*chain_provider.*deprecated/i).to_stderr
    end

    it 'emits the warning only once per process' do
      BSV::Wallet::LegacyChainProviderAdapter.new(stub_provider)
      expect { BSV::Wallet::LegacyChainProviderAdapter.new(stub_provider) }.not_to output.to_stderr
    end
  end

  describe 'LegacyBroadcasterAdapter.new (broadcaster: param)' do
    let(:stub_broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles

    it 'emits a deprecation warning for broadcaster:' do
      expect { BSV::Wallet::LegacyBroadcasterAdapter.new(stub_broadcaster) }
        .to output(/\[DEPRECATION\].*broadcaster.*deprecated/i).to_stderr
    end

    it 'emits the warning only once per process' do
      BSV::Wallet::LegacyBroadcasterAdapter.new(stub_broadcaster)
      expect { BSV::Wallet::LegacyBroadcasterAdapter.new(stub_broadcaster) }.not_to output.to_stderr
    end
  end

  describe 'WalletClient#chain_provider accessor' do
    let(:key) { BSV::Primitives::PrivateKey.generate }
    let(:wallet) { BSV::Wallet::WalletClient.new(key, storage: BSV::Wallet::MemoryStore.new) }

    it 'emits a deprecation warning when accessed' do
      expect { wallet.chain_provider }
        .to output(/\[DEPRECATION\].*chain_provider.*deprecated/i).to_stderr
    end

    it 'emits the warning only once per process' do
      wallet.chain_provider
      expect { wallet.chain_provider }.not_to output.to_stderr
    end
  end

  describe 'WalletClient with network: Registry' do
    let(:key) { BSV::Primitives::PrivateKey.generate }

    it 'does NOT emit any deprecation warning when using a Registry' do
      registry = BSV::Network::Registry.new
      expect do
        BSV::Wallet::WalletClient.new(key, storage: BSV::Wallet::MemoryStore.new, network: registry)
      end.not_to output.to_stderr
    end
  end
end
