# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::Store::Memory do
  let(:store) { described_class.new }

  it_behaves_like 'a storage adapter'

  describe 'UTXO state tracking' do
    describe '#find_spendable_outputs' do
      it 'returns spendable outputs sorted largest-first by default' do
        [100, 500, 200, 1000, 50].each_with_index do |sats, i|
          store.store_output(outpoint: "tx#{i}:0", satoshis: sats, state: :spendable)
        end

        results = store.find_spendable_outputs
        expect(results.map { |o| o[:satoshis] }).to eq([1000, 500, 200, 100, 50])
      end

      it 'returns outputs in ascending order when sort_order: :asc' do
        [100, 500, 200].each_with_index do |sats, i|
          store.store_output(outpoint: "tx#{i}:0", satoshis: sats, state: :spendable)
        end

        results = store.find_spendable_outputs(sort_order: :asc)
        expect(results.map { |o| o[:satoshis] }).to eq([100, 200, 500])
      end

      it 'excludes outputs in :pending state' do
        store.store_output(outpoint: 'tx0:0', satoshis: 100, state: :spendable)
        store.store_output(outpoint: 'tx1:0', satoshis: 200, state: :pending)

        results = store.find_spendable_outputs
        expect(results.map { |o| o[:outpoint] }).to eq(['tx0:0'])
      end

      it 'excludes outputs in :spent state' do
        store.store_output(outpoint: 'tx0:0', satoshis: 100, state: :spendable)
        store.store_output(outpoint: 'tx1:0', satoshis: 200, state: :spent)

        results = store.find_spendable_outputs
        expect(results.map { |o| o[:outpoint] }).to eq(['tx0:0'])
      end

      it 'filters by basket' do
        store.store_output(outpoint: 'tx0:0', satoshis: 300, basket: 'default', state: :spendable)
        store.store_output(outpoint: 'tx1:0', satoshis: 700, basket: 'other',   state: :spendable)

        results = store.find_spendable_outputs(basket: 'default')
        expect(results.length).to eq(1)
        expect(results.first[:outpoint]).to eq('tx0:0')
      end

      it 'filters by min_satoshis' do
        [100, 200, 300, 500].each_with_index do |sats, i|
          store.store_output(outpoint: "tx#{i}:0", satoshis: sats, basket: 'default', state: :spendable)
        end

        results = store.find_spendable_outputs(basket: 'default', min_satoshis: 200)
        expect(results.map { |o| o[:satoshis] }).to eq([500, 300, 200])
      end

      it 'combines basket and min_satoshis filters' do
        store.store_output(outpoint: 'tx0:0', satoshis: 150, basket: 'default', state: :spendable)
        store.store_output(outpoint: 'tx1:0', satoshis: 500, basket: 'default', state: :spendable)
        store.store_output(outpoint: 'tx2:0', satoshis: 600, basket: 'other',   state: :spendable)

        results = store.find_spendable_outputs(basket: 'default', min_satoshis: 200)
        expect(results.length).to eq(1)
        expect(results.first[:outpoint]).to eq('tx1:0')
      end

      it 'treats a legacy output with spendable: true as :spendable' do
        store.store_output(outpoint: 'legacy:0', satoshis: 999, spendable: true)

        results = store.find_spendable_outputs
        expect(results.map { |o| o[:outpoint] }).to include('legacy:0')
      end

      it 'treats a legacy output with no :state and no :spendable key as :spendable' do
        store.store_output(outpoint: 'bare:0', satoshis: 42)

        results = store.find_spendable_outputs
        expect(results.map { |o| o[:outpoint] }).to include('bare:0')
      end

      it 'treats a legacy output with spendable: false as :spent (excluded)' do
        store.store_output(outpoint: 'spent:0', satoshis: 100, spendable: false)

        results = store.find_spendable_outputs
        expect(results.map { |o| o[:outpoint] }).not_to include('spent:0')
      end
    end

    describe '#update_output_state' do
      it 'transitions an output from :spendable to :pending' do
        store.store_output(outpoint: 'tx0:0', satoshis: 100, state: :spendable)
        store.update_output_state('tx0:0', :pending)

        results = store.find_spendable_outputs
        expect(results).to be_empty
      end

      it 'transitions an output from :pending to :spent' do
        store.store_output(outpoint: 'tx0:0', satoshis: 100, state: :pending)
        store.update_output_state('tx0:0', :spent)

        results = store.find_spendable_outputs
        expect(results).to be_empty
      end

      it 'transitions an output back to :spendable' do
        store.store_output(outpoint: 'tx0:0', satoshis: 100, state: :pending)
        store.update_output_state('tx0:0', :spendable)

        results = store.find_spendable_outputs
        expect(results.length).to eq(1)
      end

      it 'returns the updated output hash' do
        store.store_output(outpoint: 'tx0:0', satoshis: 100, state: :spendable)
        result = store.update_output_state('tx0:0', :pending)
        expect(result[:state]).to eq(:pending)
      end

      it 'raises WalletError for an unknown outpoint' do
        expect do
          store.update_output_state('nonexistent:0', :pending)
        end.to raise_error(BSV::Wallet::WalletError, /nonexistent:0/)
      end
    end
  end

  # --------------------------------------------------------------------------
  # Production warning
  # --------------------------------------------------------------------------
  describe 'production warning' do
    # All specs in this group manage ENV keys manually to avoid cross-test leakage.
    let(:env_keys) { %w[RACK_ENV RAILS_ENV APP_ENV BSV_MEMORY_STORE_OK] }

    around do |example|
      # Save state for every key we might touch.
      saved = env_keys.to_h { |k| [k, ENV.fetch(k, nil)] }
      # Remove all of them so each example starts clean.
      env_keys.each { |k| ENV.delete(k) }
      # Ensure the class flag is reset to default (true) between examples.
      described_class.warn_in_production = true
      example.run
    ensure
      saved.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
      described_class.warn_in_production = true
    end

    it 'emits a warning when RACK_ENV=production' do
      ENV['RACK_ENV'] = 'production'
      expect { described_class.new }.to output(/Store::Memory is intended for testing/).to_stderr
    end

    it 'emits a warning when RAILS_ENV=staging' do
      ENV['RAILS_ENV'] = 'staging'
      expect { described_class.new }.to output(/Store::Memory is intended for testing/).to_stderr
    end

    it 'does not emit a warning when RAILS_ENV=test' do
      ENV['RAILS_ENV'] = 'test'
      expect { described_class.new }.not_to output.to_stderr
    end

    it 'does not emit a warning when no environment variable is set' do
      expect { described_class.new }.not_to output.to_stderr
    end

    it 'suppresses the warning when BSV_MEMORY_STORE_OK=1 is set' do
      ENV['RACK_ENV'] = 'production'
      ENV['BSV_MEMORY_STORE_OK'] = '1'
      expect { described_class.new }.not_to output.to_stderr
    end

    it 'suppresses the warning when Store::Memory.warn_in_production = false' do
      ENV['RACK_ENV'] = 'production'
      described_class.warn_in_production = false
      expect { described_class.new }.not_to output.to_stderr
    end
  end
end
