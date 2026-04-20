# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'tmpdir'

RSpec.describe 'Pool health and configurable change parameters' do
  let(:store) { BSV::Wallet::Store::Memory.new }

  # --- balance ---

  describe 'Client#balance' do
    let(:private_key) { BSV::Primitives::PrivateKey.generate }
    let(:client)      { BSV::Wallet::Client.new(private_key, storage: store) }

    context 'with 3 spendable outputs in the default basket' do
      before do
        store.store_output({ outpoint: 'aa.0', satoshis: 1000, basket: 'default', state: :spendable })
        store.store_output({ outpoint: 'bb.0', satoshis: 2000, basket: 'default', state: :spendable })
        store.store_output({ outpoint: 'cc.0', satoshis: 3000, basket: 'default', state: :spendable })
      end

      it 'returns the sum of all spendable satoshis in that basket' do
        expect(client.balance(basket: 'default')).to eq(6000)
      end
    end

    context 'with outputs in different baskets' do
      before do
        store.store_output({ outpoint: 'aa.0', satoshis: 1000, basket: 'payments', state: :spendable })
        store.store_output({ outpoint: 'bb.0', satoshis: 2000, basket: 'tokens', state: :spendable })
      end

      it 'sums all baskets when basket: nil' do
        expect(client.balance(basket: nil)).to eq(3000)
      end

      it 'filters to the named basket when basket: is given' do
        expect(client.balance(basket: 'payments')).to eq(1000)
      end

      it 'returns 0 for an empty basket' do
        expect(client.balance(basket: 'nonexistent')).to eq(0)
      end
    end

    context 'when one output is pending' do
      before do
        store.store_output({ outpoint: 'aa.0', satoshis: 1000, basket: 'default', state: :spendable })
        store.store_output({ outpoint: 'bb.0', satoshis: 2000, basket: 'default', state: :pending })
      end

      it 'excludes the pending output from the balance' do
        expect(client.balance(basket: 'default')).to eq(1000)
      end
    end

    context 'when an output is spent' do
      before do
        store.store_output({ outpoint: 'aa.0', satoshis: 5000, basket: 'default', state: :spent })
      end

      it 'returns zero' do
        expect(client.balance(basket: 'default')).to eq(0)
      end
    end

    it 'returns 0 when there are no outputs' do
      expect(client.balance).to eq(0)
    end
  end

  # --- spendable_balance ---

  describe 'Client#spendable_balance' do
    let(:private_key) { BSV::Primitives::PrivateKey.generate }
    let(:client)      { BSV::Wallet::Client.new(private_key, storage: store) }

    # Output with full BRC-29 derivation metadata (auto-spendable).
    let(:derivation_output) do
      { outpoint: 'aa.0', satoshis: 3000, state: :spendable,
        derivation_prefix: 'abc', derivation_suffix: 'def', sender_identity_key: '02abc' }
    end

    # Basket-only output without derivation data (not auto-spendable).
    let(:basket_output) do
      { outpoint: 'bb.0', satoshis: 2000, basket: 'tokens', state: :spendable }
    end

    it 'returns 0 when there are no outputs' do
      expect(client.spendable_balance).to eq(0)
    end

    it 'returns 0 when only basket-only outputs exist' do
      store.store_output(basket_output)
      expect(client.spendable_balance).to eq(0)
    end

    it 'includes only outputs with full BRC-29 derivation metadata' do
      store.store_output(derivation_output)
      store.store_output(basket_output)
      expect(client.spendable_balance).to eq(3000)
    end

    it 'is less than balance when basket-only outputs are present' do
      store.store_output(derivation_output)
      store.store_output(basket_output)
      expect(client.balance).to eq(5000)
      expect(client.spendable_balance).to eq(3000)
    end

    it 'filters to a named basket when basket: is given' do
      store.store_output(derivation_output.merge(basket: 'payments'))
      store.store_output(derivation_output.merge(outpoint: 'cc.0', basket: 'other', satoshis: 1000))
      expect(client.spendable_balance(basket: 'payments')).to eq(3000)
    end

    it 'excludes pending outputs' do
      store.store_output(derivation_output.merge(state: :pending))
      expect(client.spendable_balance).to eq(0)
    end

    it 'excludes spent outputs' do
      store.store_output(derivation_output.merge(state: :spent))
      expect(client.spendable_balance).to eq(0)
    end
  end

  # --- store_setting / find_setting ---

  describe 'MemoryStore settings' do
    it 'stores and retrieves a setting by key' do
      params = { count: 20, satoshis: 10_000 }
      store.store_setting('change_params', params)
      expect(store.find_setting('change_params')).to eq(params)
    end

    it 'returns nil for a key that has never been set' do
      expect(store.find_setting('nonexistent')).to be_nil
    end

    it 'overwrites an existing setting on second store' do
      store.store_setting('change_params', { count: 10, satoshis: 5000 })
      store.store_setting('change_params', { count: 20, satoshis: 8000 })
      expect(store.find_setting('change_params')).to eq({ count: 20, satoshis: 8000 })
    end
  end

  # --- FileStore persistence ---

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

  # --- set_wallet_change_params ---

  describe 'Client#set_wallet_change_params' do
    let(:private_key) { BSV::Primitives::PrivateKey.generate }
    let(:client)      { BSV::Wallet::Client.new(private_key, storage: store) }

    it 'persists change params to storage' do
      client.set_wallet_change_params(count: 20, satoshis: 10_000)
      params = store.find_setting('change_params')
      expect(params[:count]).to eq(20)
      expect(params[:satoshis]).to eq(10_000)
    end

    it 'raises InvalidParameterError when count is not a positive integer' do
      expect do
        client.set_wallet_change_params(count: 0, satoshis: 1000)
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError when satoshis is not a positive integer' do
      expect do
        client.set_wallet_change_params(count: 10, satoshis: -1)
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  # --- Pool-aware ChangeGenerator ---

  describe 'BSV::Wallet::ChangeGenerator pool-awareness' do
    let(:private_key) { BSV::Primitives::PrivateKey.generate }
    let(:key_deriver) { BSV::Wallet::KeyDeriver.new(private_key) }
    # Use 1 sat/kB so dust_floor = max(2, 1*2) = 2 — keeps arithmetic simple.
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

    context 'when pool is above the target count' do
      let(:pool_size)     { 25 }
      let(:change_params) { { count: 20, satoshis: 10_000 } }

      it 'produces 1-2 change outputs' do
        outputs = generator.generate(
          excess_satoshis: 10_000,
          pool_size: pool_size,
          change_params: change_params
        )
        expect(outputs.length).to be <= 2
      end
    end

    context 'when pool is far below target but max_outputs cap applies' do
      it 'never exceeds max_outputs' do
        outputs = generator.generate(
          excess_satoshis: 100_000,
          pool_size: 1,
          change_params: { count: 1000, satoshis: 10_000 }
        )
        expect(outputs.length).to be <= generator.max_outputs
      end
    end

    context 'when no change_params are set' do
      it 'falls back to default behaviour (uses max_outputs)' do
        # With no pool_size or change_params the generator behaves as before —
        # it will produce up to max_outputs outputs when the excess allows it.
        outputs = generator.generate(excess_satoshis: 10_000)
        expect(outputs.length).to be >= 1
        expect(outputs.length).to be <= generator.max_outputs
        expect(outputs.sum { |o| o[:satoshis] }).to eq(10_000)
      end
    end

    context 'when pool_size is provided but change_params is nil' do
      it 'falls back to default behaviour' do
        outputs = generator.generate(excess_satoshis: 10_000, pool_size: 5)
        expect(outputs.length).to be >= 1
        expect(outputs.length).to be <= generator.max_outputs
      end
    end
  end
end
