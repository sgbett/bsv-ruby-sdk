# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'securerandom'

RSpec.describe 'BSV::Wallet::ReplenishmentWorker' do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:store)       { BSV::Wallet::MemoryStore.new }
  let(:broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles
  let(:wallet) do
    BSV::Wallet::Client.new(private_key, storage: store, broadcaster: broadcaster)
  end

  before do
    allow(broadcaster).to receive(:broadcast).and_return(
      BSV::Network::BroadcastResponse.new(txid: 'stub', tx_status: 'SEEN_ON_NETWORK')
    )
  end

  # Seeds a spendable output into the default basket with full BRC-29 derivation
  # metadata so auto_fund_and_create can spend it.
  def seed_payment_output(satoshis:)
    deriver      = wallet.key_deriver
    prefix       = SecureRandom.hex(16)
    suffix       = SecureRandom.hex(16)
    identity_key = deriver.identity_key
    key_id       = "#{prefix} #{suffix}"
    protocol_id  = [2, '3241645161d8']

    pub_key        = deriver.derive_public_key(protocol_id, key_id, identity_key, for_self: true)
    locking_script = BSV::Script::Script.p2pkh_lock(pub_key.hash160)

    source_tx = BSV::Transaction::Transaction.new
    source_tx.add_output(
      BSV::Transaction::TransactionOutput.new(
        satoshis: satoshis,
        locking_script: locking_script
      )
    )
    txid     = source_tx.txid_hex
    outpoint = "#{txid}.0"

    store.store_transaction(txid, source_tx.to_hex)
    store.store_output({
                         outpoint: outpoint,
                         satoshis: satoshis,
                         locking_script: locking_script.to_hex,
                         basket: 'default',
                         state: :spendable,
                         spendable: true,
                         derivation_prefix: prefix,
                         derivation_suffix: suffix,
                         sender_identity_key: identity_key,
                         source_tx_hex: source_tx.to_hex
                       })
    outpoint
  end

  # Build a pool and an attached worker without starting the background thread.
  def build_pool_and_worker(name: 'test', target_count: 3, target_satoshis: 1_000, low_water_mark: 1,
                            interval: 60)
    pool = BSV::Wallet::LocalPool.new(
      name: name,
      storage: store,
      wallet_client: wallet,
      target_count: target_count,
      target_satoshis: target_satoshis,
      low_water_mark: low_water_mark
    )
    worker = BSV::Wallet::ReplenishmentWorker.new(
      pool: pool,
      wallet_client: wallet,
      interval: interval
    )
    pool.replenisher = worker
    [pool, worker]
  end

  # -----------------------------------------------------------------------
  # Lifecycle
  # -----------------------------------------------------------------------

  describe 'lifecycle' do
    let(:worker) { build_pool_and_worker.last }

    after { worker.stop }

    it 'start returns self' do
      expect(worker.start).to equal(worker)
    end

    it 'stop signals the worker to terminate' do
      worker.start
      worker.stop
      running = worker.instance_variable_get(:@running)
      expect(running).to be false
    end

    it 'stop is idempotent' do
      worker.start
      worker.stop
      expect { worker.stop }.not_to raise_error
    end

    it 'start is idempotent (calling start twice does not spawn extra threads)' do
      worker.start
      first_thread = worker.instance_variable_get(:@thread)
      worker.start
      second_thread = worker.instance_variable_get(:@thread)
      expect(first_thread).to equal(second_thread)
    end
  end

  # -----------------------------------------------------------------------
  # replenish (invoked directly to avoid thread-timing dependence)
  # -----------------------------------------------------------------------

  describe '#replenish (invoked directly)' do
    it 'does nothing when pool is already at target' do
      _, worker = build_pool_and_worker(target_count: 2)
      seed_payment_output(satoshis: 100_000)

      # Seed pool outputs directly so the pool considers itself full.
      store.store_output(
        outpoint: "#{SecureRandom.hex(32)}.0",
        satoshis: 1_000,
        basket: 'pool:test',
        state: :spendable
      )
      store.store_output(
        outpoint: "#{SecureRandom.hex(32)}.0",
        satoshis: 1_000,
        basket: 'pool:test',
        state: :spendable
      )

      allow(wallet).to receive(:create_action)
      worker.send(:replenish)
      expect(wallet).not_to have_received(:create_action)
    end

    context 'when pool is empty and funds are available' do
      let(:worker) { build_pool_and_worker(target_count: 3, target_satoshis: 1_000).last }

      before { seed_payment_output(satoshis: 100_000) }

      it 'creates pool outputs to fill the deficit' do
        worker.send(:replenish)
        pool_outputs = store.find_spendable_outputs(basket: 'pool:test')
        expect(pool_outputs.length).to be >= 1
      end

      it 'pool outputs are stored with BRC-29 derivation metadata (bug #4 regression)' do
        worker.send(:replenish)
        pool_outputs = store.find_spendable_outputs(basket: 'pool:test')
        expect(pool_outputs).not_to be_empty

        pool_outputs.each do |o|
          expect(o[:derivation_prefix]).not_to be_nil, "Output #{o[:outpoint]} missing :derivation_prefix"
          expect(o[:derivation_suffix]).not_to be_nil, "Output #{o[:outpoint]} missing :derivation_suffix"
          expect(o[:sender_identity_key]).not_to be_nil, "Output #{o[:outpoint]} missing :sender_identity_key"
        end
      end

      it 'calls create_action with auto_fund: true (bug #7 regression)' do
        captured_args = nil
        allow(wallet).to receive(:create_action) do |args|
          captured_args = args
          { txid: 'stub' }
        end

        worker.send(:replenish)
        expect(captured_args).not_to be_nil
        expect(captured_args[:auto_fund]).to be true
      end

      it 'calls create_action with a valid output_description (5-50 chars) per output spec (bug #6 regression)' do
        captured_args = nil
        allow(wallet).to receive(:create_action) do |args|
          captured_args = args
          { txid: 'stub' }
        end

        worker.send(:replenish)
        expect(captured_args).not_to be_nil

        output_specs = captured_args[:outputs] || []
        output_specs.each do |spec|
          desc = spec[:output_description]
          expect(desc).to be_a(String)
          expect(desc.length).to be >= 5,  "output_description '#{desc}' is shorter than 5 chars"
          expect(desc.length).to be <= 50, "output_description '#{desc}' is longer than 50 chars"
        end
      end

      it 'calls create_action with a Hash argument (no ArgumentError in Ruby 3.x) (bug #5 regression)' do
        expect { worker.send(:replenish) }.not_to raise_error
      end

      it 'basket name in each output spec passes validate_basket! (bug #2 regression)' do
        captured_args = nil
        allow(wallet).to receive(:create_action) do |args|
          captured_args = args
          { txid: 'stub' }
        end

        worker.send(:replenish)
        expect(captured_args).not_to be_nil

        output_specs = captured_args[:outputs] || []
        output_specs.each do |spec|
          expect do
            BSV::Wallet::Validators.validate_basket!(spec[:basket])
          end.not_to raise_error, "basket '#{spec[:basket]}' should be valid but raised"
        end
      end
    end

    context 'when the worker thread encounters an error' do
      # replenish itself does NOT rescue — the rescue lives in run_loop.
      # Test that the thread survives errors by checking @running stays true
      # through several fast cycles.

      it 'thread survives a WalletError raised inside replenish' do
        _, worker = build_pool_and_worker(target_count: 2, target_satoshis: 1_000, interval: 0.05)
        allow(wallet).to receive(:create_action).and_raise(
          BSV::Wallet::InsufficientFundsError.new('not enough')
        )
        worker.start
        sleep 0.15 # allow at least two cycles to run
        running = worker.instance_variable_get(:@running)
        thread  = worker.instance_variable_get(:@thread)
        worker.stop
        expect(running).to be true
        expect(thread).to be_a(Thread)
      end

      it 'thread survives a StandardError raised inside replenish' do
        _, worker = build_pool_and_worker(target_count: 2, target_satoshis: 1_000, interval: 0.05)
        allow(wallet).to receive(:create_action).and_raise(StandardError, 'unexpected')
        worker.start
        sleep 0.15
        running = worker.instance_variable_get(:@running)
        thread  = worker.instance_variable_get(:@thread)
        worker.stop
        expect(running).to be true
        expect(thread).to be_a(Thread)
      end
    end
  end

  # -----------------------------------------------------------------------
  # store_tracked_outputs derivation fields (bug #4 regression)
  # -----------------------------------------------------------------------

  describe 'store_tracked_outputs derivation fields (bug #4 regression)' do
    it 'persists derivation_prefix, derivation_suffix, and sender_identity_key from output spec' do
      prefix       = SecureRandom.hex(16)
      suffix       = SecureRandom.hex(16)
      identity_key = wallet.key_deriver.identity_key
      txid         = 'a' * 64
      fake_tx      = BSV::Transaction::Transaction.new

      locking_script = BSV::Script::Script.p2pkh_lock(
        wallet.key_deriver.derive_public_key(
          [2, '3241645161d8'],
          "#{prefix} #{suffix}",
          identity_key,
          for_self: true
        ).hash160
      )

      fake_tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: 1_000,
          locking_script: locking_script
        )
      )

      output_spec = {
        satoshis: 1_000,
        locking_script: locking_script.to_hex,
        basket: 'pool:test',
        output_description: 'utxo pool test',
        derivation_prefix: prefix,
        derivation_suffix: suffix,
        sender_identity_key: identity_key
      }

      fake_tx.outputs.first.instance_variable_set(:@_spec, output_spec)
      wallet.send(:store_tracked_outputs, txid, fake_tx, [output_spec])

      stored_outputs = store.find_outputs({ basket: 'pool:test', include_spent: true, limit: 10, offset: 0 })
      expect(stored_outputs).not_to be_empty

      stored = stored_outputs.first
      expect(stored[:derivation_prefix]).to eq(prefix)
      expect(stored[:derivation_suffix]).to eq(suffix)
      expect(stored[:sender_identity_key]).to eq(identity_key)
    end

    it 'stores nil derivation fields when the spec omits them (no error)' do
      txid = 'b' * 64

      locking_script = BSV::Script::Script.p2pkh_lock(private_key.public_key.hash160)
      fake_tx = BSV::Transaction::Transaction.new
      fake_tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: 500,
          locking_script: locking_script
        )
      )

      output_spec = {
        satoshis: 500,
        locking_script: locking_script.to_hex,
        basket: 'my tokens',
        output_description: 'basket output'
      }

      fake_tx.outputs.first.instance_variable_set(:@_spec, output_spec)

      expect do
        wallet.send(:store_tracked_outputs, txid, fake_tx, [output_spec])
      end.not_to raise_error
    end
  end
end
