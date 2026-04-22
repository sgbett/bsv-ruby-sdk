# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'tmpdir'
require 'bsv/wallet/testing/shared_examples_for_wallet_operations'

STORE_FACTORIES.each do |store_label, store_factory|
  RSpec.describe "Pool health and configurable change parameters (#{store_label})" do
    let(:store) { store_factory.call }

    it_behaves_like 'wallet pool health'

    # FileStore-specific: persist settings across instances.
    describe 'FileStore settings persistence' do
      let(:tmpdir) { Dir.mktmpdir('bsv-wallet-settings-test') }

      after { FileUtils.rm_rf(tmpdir) }

      it 'persists settings across instances' do
        file_store = BSV::Wallet::Store::File.new(dir: tmpdir)
        file_store.store_setting('change_params', { 'count' => 20, 'satoshis' => 10_000 })

        reloaded = BSV::Wallet::Store::File.new(dir: tmpdir)
        result = reloaded.find_setting('change_params')
        expect(result).to be_a(Hash)
        expect(result['count']).to eq(20)
        expect(result['satoshis']).to eq(10_000)
      end

      it 'returns nil for an absent setting on a fresh store' do
        file_store = BSV::Wallet::Store::File.new(dir: tmpdir)
        expect(file_store.find_setting('change_params')).to be_nil
      end
    end

    # ChangeGenerator pool-awareness (not store-specific, included here for completeness)
    describe 'BSV::Wallet::ChangeGenerator pool-awareness' do
      let(:private_key) { BSV::Primitives::PrivateKey.generate }
      let(:key_deriver) { BSV::Wallet::KeyDeriver.new(private_key) }
      let(:fee_model) { BSV::Wallet::FeeModel.new(sats_per_kb: 1) }
      let(:generator) do
        BSV::Wallet::ChangeGenerator.new(key_deriver: key_deriver, fee_model: fee_model, max_outputs: 8)
      end

      context 'when pool is below the target count' do
        let(:pool_size)     { 5 }
        let(:change_params) { { count: 20, satoshis: 10_000 } }

        it 'produces up to max_outputs change outputs' do
          outputs = generator.generate(
            excess_satoshis: 10_000,
            pool_size: pool_size,
            change_params: change_params
          )
          expect(outputs.length).to be > 1
          expect(outputs.length).to be <= 8
        end

        it 'all outputs sum to the excess' do
          outputs = generator.generate(
            excess_satoshis: 10_000,
            pool_size: pool_size,
            change_params: change_params
          )
          expect(outputs.sum { |o| o[:satoshis] }).to eq(10_000)
        end
      end

      context 'when pool is at the target count' do
        let(:pool_size)     { 20 }
        let(:change_params) { { count: 20, satoshis: 10_000 } }

        it 'produces 1-2 change outputs' do
          outputs = generator.generate(
            excess_satoshis: 10_000,
            pool_size: pool_size,
            change_params: change_params
          )
          expect(outputs.length).to be <= 2
          expect(outputs.length).to be >= 1
        end
      end

      context 'when no change_params are set' do
        it 'falls back to default behaviour (uses max_outputs)' do
          outputs = generator.generate(excess_satoshis: 10_000)
          expect(outputs.length).to be >= 1
          expect(outputs.length).to be <= generator.max_outputs
          expect(outputs.sum { |o| o[:satoshis] }).to eq(10_000)
        end
      end
    end
  end
end
