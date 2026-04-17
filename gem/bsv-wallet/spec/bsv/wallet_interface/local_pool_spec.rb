# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'securerandom'

RSpec.describe 'BSV::Wallet::LocalPool' do
  let(:store) { BSV::Wallet::MemoryStore.new }

  # Build a pool with sensible defaults. Replenisher is nil unless set explicitly.
  def build_pool(name: 'test', target_count: 5, target_satoshis: 10_000, low_water_mark: 2)
    BSV::Wallet::LocalPool.new(
      name: name,
      storage: store,
      wallet_client: nil,
      target_count: target_count,
      target_satoshis: target_satoshis,
      low_water_mark: low_water_mark
    )
  end

  # Seeds a spendable output directly into the store for the pool basket.
  def seed_pool_output(outpoint:, satoshis: 10_000, basket: 'pool:test')
    store.store_output(
      outpoint: outpoint,
      satoshis: satoshis,
      basket: basket,
      state: :spendable,
      derivation_prefix: SecureRandom.hex(16),
      derivation_suffix: SecureRandom.hex(16),
      sender_identity_key: "02#{'ab' * 32}"
    )
  end

  # -----------------------------------------------------------------------
  # Attributes and factory basics
  # -----------------------------------------------------------------------

  describe 'attributes' do
    it 'derives the basket name as pool:<name>' do
      pool = build_pool(name: 'doom')
      expect(pool.basket).to eq('pool:doom')
    end

    it 'exposes the name' do
      pool = build_pool(name: 'payments')
      expect(pool.name).to eq('payments')
    end

    it 'exposes the storage adapter (bug #8 regression)' do
      pool = build_pool
      expect(pool.storage).to eq(store)
    end

    it 'exposes target_count' do
      pool = build_pool(target_count: 10)
      expect(pool.target_count).to eq(10)
    end

    it 'exposes target_satoshis' do
      pool = build_pool(target_satoshis: 5_000)
      expect(pool.target_satoshis).to eq(5_000)
    end
  end

  # -----------------------------------------------------------------------
  # acquire
  # -----------------------------------------------------------------------

  describe '#acquire' do
    let(:pool) { build_pool }

    before do
      seed_pool_output(outpoint: "#{'aa' * 32}.0")
    end

    it 'returns the outpoint string of the acquired output' do
      result = pool.acquire
      expect(result).to be_a(String)
      expect(result).to match(/\A[0-9a-f]{64}\.\d+\z/)
    end

    it 'acquired output is no longer in find_spendable_outputs' do
      outpoint = pool.acquire
      spendable = store.find_spendable_outputs(basket: 'pool:test')
      expect(spendable.map { |o| o[:outpoint] }).not_to include(outpoint)
    end

    it 'multiple sequential acquires return distinct outpoints' do
      seed_pool_output(outpoint: "#{'bb' * 32}.0")
      first  = pool.acquire
      second = pool.acquire
      expect(first).not_to eq(second)
    end

    it 'raises PoolDepletedError when the pool is empty' do
      store.update_output_state("#{'aa' * 32}.0", :spent)
      expect { pool.acquire }.to raise_error(BSV::Wallet::PoolDepletedError)
    end

    it 'raises PoolDepletedError when all outputs are already pending' do
      outpoint = "#{'aa' * 32}.0"
      store.update_output_state(outpoint, :pending, pending_reference: 'held-externally')
      expect { pool.acquire }.to raise_error(BSV::Wallet::PoolDepletedError)
    end

    # Bug #1 regression: pool-acquired locks must use no_send: true so they
    # are exempt from release_stale_pending! sweeps.
    it 'acquires with no_send: true so the lock survives release_stale_pending! (bug #1)' do
      outpoint = pool.acquire

      # Zero-timeout forces any non-exempt lock to be released immediately.
      released = store.release_stale_pending!(timeout: 0)
      expect(released).to eq(0)

      # The output must still be locked (not spendable).
      spendable = store.find_spendable_outputs(basket: 'pool:test')
      expect(spendable.map { |o| o[:outpoint] }).not_to include(outpoint)
    end

    it 'the acquired output carries no_send: true in storage' do
      outpoint = pool.acquire
      raw = store.find_outputs({ outpoint: outpoint, include_spent: true, limit: 1, offset: 0 })
      expect(raw.first[:no_send]).to be true
    end
  end

  # -----------------------------------------------------------------------
  # Bug #3 regression: signal at <= low_water_mark
  # -----------------------------------------------------------------------

  describe '#acquire signals replenisher at exactly the low-water mark (bug #3)' do
    let(:replenisher) { double('replenisher', signal: nil, stop: nil) } # rubocop:disable RSpec/VerifiedDoubles

    # Pool of 2 with low_water_mark of 2: after first acquire, 1 output remains
    # which is <= 2, so the replenisher must be signalled.
    it 'signals when remaining count equals low_water_mark' do
      pool = build_pool(target_count: 3, low_water_mark: 2)
      pool.replenisher = replenisher

      seed_pool_output(outpoint: "#{'cc' * 32}.0")
      seed_pool_output(outpoint: "#{'dd' * 32}.0")

      # After the first acquire there is 1 output left, which is <= low_water_mark (2).
      pool.acquire
      expect(replenisher).to have_received(:signal).at_least(:once)
    end

    # Pool of 1 with low_water_mark of 1: after acquire, 0 remain which is still <= 1.
    it 'signals when pool drops to zero at low_water_mark of 1 (pool-of-1 edge case)' do
      pool = build_pool(target_count: 1, low_water_mark: 1)
      pool.replenisher = replenisher

      seed_pool_output(outpoint: "#{'ee' * 32}.0")

      pool.acquire
      expect(replenisher).to have_received(:signal).at_least(:once)
    end

    it 'does not signal when remaining count is above low_water_mark' do
      pool = build_pool(target_count: 10, low_water_mark: 2)
      pool.replenisher = replenisher

      # Seed 5 outputs; after one acquire 4 remain, which is > 2.
      5.times { |i| seed_pool_output(outpoint: "#{"f#{i}" * 32}.0") }

      pool.acquire
      expect(replenisher).not_to have_received(:signal)
    end
  end

  # -----------------------------------------------------------------------
  # release
  # -----------------------------------------------------------------------

  describe '#release' do
    let(:pool) { build_pool }

    before { seed_pool_output(outpoint: "#{'aa' * 32}.0") }

    it 'returns the output to spendable state' do
      outpoint = pool.acquire
      pool.release(outpoint)
      spendable = store.find_spendable_outputs(basket: 'pool:test')
      expect(spendable.map { |o| o[:outpoint] }).to include(outpoint)
    end

    it 'a released output can be re-acquired' do
      outpoint = pool.acquire
      pool.release(outpoint)
      re_acquired = pool.acquire
      expect(re_acquired).to eq(outpoint)
    end
  end

  # -----------------------------------------------------------------------
  # status
  # -----------------------------------------------------------------------

  describe '#status' do
    it 'returns :healthy state when available count is above low_water_mark' do
      pool = build_pool(target_count: 5, low_water_mark: 2)
      3.times { |i| seed_pool_output(outpoint: "#{"a#{i}" * 32}.0") }
      result = pool.status
      expect(result[:state]).to eq(:healthy)
    end

    it 'returns :depleted state when pool is empty and no replenisher is running' do
      pool = build_pool(target_count: 5, low_water_mark: 2)
      # No outputs seeded — pool is empty.
      result = pool.status
      expect(result[:state]).to eq(:depleted)
    end

    it 'includes correct available count' do
      pool = build_pool
      seed_pool_output(outpoint: "#{'aa' * 32}.0")
      seed_pool_output(outpoint: "#{'bb' * 32}.0")
      expect(pool.status[:available]).to eq(2)
    end

    it 'includes target count' do
      pool = build_pool(target_count: 7)
      expect(pool.status[:target]).to eq(7)
    end

    it 'includes satoshis_committed as the sum of spendable satoshis' do
      pool = build_pool
      seed_pool_output(outpoint: "#{'aa' * 32}.0", satoshis: 10_000)
      seed_pool_output(outpoint: "#{'bb' * 32}.0", satoshis: 20_000)
      expect(pool.status[:satoshis_committed]).to eq(30_000)
    end

    it 'returns :replenishing after acquire triggers replenisher signal' do
      replenisher = double('replenisher', signal: nil, stop: nil) # rubocop:disable RSpec/VerifiedDoubles
      pool = build_pool(target_count: 2, low_water_mark: 2)
      pool.replenisher = replenisher

      seed_pool_output(outpoint: "#{'aa' * 32}.0")
      seed_pool_output(outpoint: "#{'bb' * 32}.0")

      # After acquire the pool drops to 1 which is <= 2, triggering replenishment.
      pool.acquire
      expect(pool.status[:state]).to eq(:replenishing)
    end
  end

  # -----------------------------------------------------------------------
  # Basket isolation
  # -----------------------------------------------------------------------

  describe 'basket isolation' do
    it 'pool outputs are not returned by find_spendable_outputs for the default basket' do
      seed_pool_output(outpoint: "#{'aa' * 32}.0", basket: 'pool:test')
      default_outputs = store.find_spendable_outputs(basket: 'default')
      expect(default_outputs.map { |o| o[:outpoint] }).not_to include("#{'aa' * 32}.0")
    end
  end

  # -----------------------------------------------------------------------
  # shutdown
  # -----------------------------------------------------------------------

  describe '#shutdown' do
    let(:pool) { build_pool }

    it 'sets status to :shutdown' do
      pool.shutdown
      expect(pool.status[:state]).to eq(:shutdown)
    end

    it 'is idempotent (calling shutdown twice does not raise)' do
      pool.shutdown
      expect { pool.shutdown }.not_to raise_error
    end

    it 'raises PoolDepletedError on acquire after shutdown' do
      pool.shutdown
      expect { pool.acquire }.to raise_error(BSV::Wallet::PoolDepletedError)
    end

    it 'stops the replenisher if one is set' do
      replenisher = double('replenisher', stop: nil) # rubocop:disable RSpec/VerifiedDoubles
      pool.replenisher = replenisher
      pool.shutdown
      expect(replenisher).to have_received(:stop)
    end
  end

  # -----------------------------------------------------------------------
  # Concurrent acquire (barrier pattern)
  # -----------------------------------------------------------------------

  describe 'concurrent acquire' do
    it '2 threads competing for 1 output: exactly 1 succeeds, the other gets PoolDepletedError' do
      pool = build_pool
      seed_pool_output(outpoint: "#{'aa' * 32}.0")

      results  = Array.new(2)
      barrier  = Queue.new
      acquired = []

      threads = 2.times.map do |i|
        Thread.new do
          barrier.pop # wait until both threads are ready

          begin
            results[i] = pool.acquire
            acquired << results[i]
          rescue BSV::Wallet::PoolDepletedError
            results[i] = :depleted
          end
        end
      end

      2.times { barrier.push(:go) }
      threads.each(&:join)

      depleted_count = results.count(:depleted)
      success_count  = results.count { |r| r != :depleted }

      expect(success_count).to eq(1), "Expected exactly 1 acquire to succeed; got #{results.inspect}"
      expect(depleted_count).to eq(1)
    end

    it '5 threads competing for 5 outputs: all 5 get distinct outpoints' do
      pool = build_pool(target_count: 5)
      5.times { |i| seed_pool_output(outpoint: "#{SecureRandom.hex(32)}.#{i}") }

      results = Array.new(5)
      barrier = Queue.new

      threads = 5.times.map do |i|
        Thread.new do
          barrier.pop
          results[i] = pool.acquire
        rescue BSV::Wallet::PoolDepletedError
          results[i] = :depleted
        end
      end

      5.times { barrier.push(:go) }
      threads.each(&:join)

      expect(results).not_to include(:depleted)
      expect(results.uniq.length).to eq(5), "Expected all 5 distinct outpoints; got #{results.inspect}"
    end
  end

  # -----------------------------------------------------------------------
  # WalletClient#utxo_pool factory integration
  # -----------------------------------------------------------------------

  describe 'WalletClient#utxo_pool factory' do
    let(:private_key) { BSV::Primitives::PrivateKey.generate }
    let(:storage)     { BSV::Wallet::MemoryStore.new }
    let(:broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles
    let(:wallet) do
      BSV::Wallet::WalletClient.new(private_key, storage: storage, broadcaster: broadcaster)
    end
    let(:pool) { wallet.utxo_pool(name: 'test') }

    after { pool.shutdown }

    before do
      allow(broadcaster).to receive(:broadcast).and_return(
        BSV::Network::BroadcastResponse.new(txid: 'stub', tx_status: 'SEEN_ON_NETWORK')
      )
    end

    it 'returns a LocalPool instance' do
      expect(pool).to be_a(BSV::Wallet::LocalPool)
    end

    it 'pool basket is pool:<name>' do
      named_pool = wallet.utxo_pool(name: 'payments')
      named_pool.shutdown
      expect(named_pool.basket).to eq('pool:payments')
    end

    it 'pool has a replenisher attached (not nil)' do
      replenisher = pool.instance_variable_get(:@replenisher)
      expect(replenisher).not_to be_nil
    end

    it 'pool.storage returns the wallet storage adapter (bug #8 regression)' do
      expect(pool.storage).to eq(storage)
    end

    it 'shutdown marks the replenisher as stopped' do
      replenisher = pool.instance_variable_get(:@replenisher)
      pool.shutdown
      running = replenisher.instance_variable_get(:@running)
      expect(running).to be false
    end
  end
end
