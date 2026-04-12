# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet-postgres'

RSpec.describe 'BSV::Wallet::SolidQueueAdapter', :postgres do
  let(:db)          { POSTGRES_TEST_DB }
  let(:storage)     { BSV::Wallet::PostgresStore.new(db) }
  let(:broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles
  let(:adapter) do
    BSV::Wallet::SolidQueueAdapter.new(
      db: db,
      storage: storage,
      broadcaster: broadcaster,
      poll_interval: 0.1,
      stale_threshold: 1
    )
  end

  # Minimal valid txids
  let(:txid_a) { 'a' * 64 }
  let(:txid_b) { 'b' * 64 }

  # Minimal BEEF binary — an empty transaction serialised as BEEF
  let(:beef_binary) { BSV::Transaction::Transaction.new.to_beef }
  let(:beef_hex)    { beef_binary.unpack1('H*') }

  before do
    POSTGRES_WALLET_TABLES.each { |t| db[t].truncate(cascade: true) }
  end

  after do
    adapter.drain rescue nil # rubocop:disable Style/RescueModifier
  end

  # ---------------------------------------------------------------------------
  # Seeding helpers (mirror InlineQueue spec patterns)
  # ---------------------------------------------------------------------------

  def seed_pending_input(outpoint:, fund_ref: 'ref-001')
    storage.store_output(
      outpoint: outpoint,
      satoshis: 1000,
      state: :pending,
      basket: 'default',
      pending_reference: fund_ref
    )
  end

  def seed_pending_change(outpoint:)
    storage.store_output(
      outpoint: outpoint,
      satoshis: 500,
      state: :pending,
      basket: 'default'
    )
  end

  def seed_action(txid:, status: 'signed')
    storage.store_action(txid: txid, description: 'test action', status: status)
  end

  def enqueue_auto_fund(txid:, input_outpoints:, change_outpoints:, fund_ref: 'ref-001')
    adapter.enqueue(
      txid: txid,
      beef_binary: beef_binary,
      input_outpoints: input_outpoints,
      change_outpoints: change_outpoints,
      fund_ref: fund_ref
    )
  end

  def enqueue_finalize(txid:)
    adapter.enqueue(
      txid: txid,
      beef_binary: beef_binary,
      input_outpoints: nil,
      change_outpoints: nil,
      fund_ref: nil
    )
  end

  def job_row(txid)
    db[:wallet_broadcast_jobs].where(txid: txid).first
  end

  def output_state(outpoint)
    storage.find_outputs({ outpoint: outpoint, include_spent: true, limit: 1, offset: 0 }).first&.dig(:state)
  end

  def action_status(txid)
    storage.find_actions({ txid: txid, limit: 1, offset: 0 }).first&.dig(:status)
  end

  # ---------------------------------------------------------------------------
  # 1. Constructor guards
  # ---------------------------------------------------------------------------
  describe 'constructor validation' do
    it 'raises ArgumentError when storage is MemoryStore' do
      expect do
        BSV::Wallet::SolidQueueAdapter.new(
          db: db,
          storage: BSV::Wallet::MemoryStore.new,
          broadcaster: broadcaster
        )
      end.to raise_error(ArgumentError, /MemoryStore/)
    end

    it 'raises ArgumentError when broadcaster is nil' do
      expect do
        BSV::Wallet::SolidQueueAdapter.new(db: db, storage: storage, broadcaster: nil)
      end.to raise_error(ArgumentError, /broadcaster/)
    end

    it 'accepts PostgresStore with a broadcaster without raising' do
      expect do
        BSV::Wallet::SolidQueueAdapter.new(db: db, storage: storage, broadcaster: broadcaster)
      end.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Interface compliance
  # ---------------------------------------------------------------------------
  describe '#async?' do
    it 'returns true' do
      expect(adapter.async?).to be(true)
    end
  end

  describe 'BroadcastQueue inclusion' do
    it 'includes BroadcastQueue' do
      expect(described_class).to be_nil # no-op; verify via ancestors
      expect(BSV::Wallet::SolidQueueAdapter.ancestors).to include(BSV::Wallet::BroadcastQueue)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Enqueue — auto-fund path
  # ---------------------------------------------------------------------------
  describe '#enqueue (auto-fund path)' do
    it 'inserts a row into wallet_broadcast_jobs with status unsent' do
      enqueue_auto_fund(txid: txid_a, input_outpoints: ['abc:0'], change_outpoints: ['xyz:0'])
      row = job_row(txid_a)
      expect(row).not_to be_nil
      expect(row[:status]).to eq('unsent')
    end

    it 'stores beef_hex as hex encoding of beef_binary' do
      enqueue_auto_fund(txid: txid_a, input_outpoints: ['abc:0'], change_outpoints: ['xyz:0'])
      expect(job_row(txid_a)[:beef_hex]).to eq(beef_hex)
    end

    it 'stores input_outpoints as a postgres text array' do
      enqueue_auto_fund(txid: txid_a, input_outpoints: %w[abc:0 def:1], change_outpoints: [])
      stored = job_row(txid_a)[:input_outpoints].to_a
      expect(stored).to eq(%w[abc:0 def:1])
    end

    it 'stores change_outpoints as a postgres text array' do
      enqueue_auto_fund(txid: txid_a, input_outpoints: ['abc:0'], change_outpoints: %w[xyz:0 xyz:1])
      stored = job_row(txid_a)[:change_outpoints].to_a
      expect(stored).to eq(%w[xyz:0 xyz:1])
    end

    it 'stores fund_ref' do
      enqueue_auto_fund(txid: txid_a, input_outpoints: ['abc:0'], change_outpoints: [], fund_ref: 'ref-xyz')
      expect(job_row(txid_a)[:fund_ref]).to eq('ref-xyz')
    end

    it 'returns { txid:, broadcast_status: "sending" }' do
      result = enqueue_auto_fund(txid: txid_a, input_outpoints: [], change_outpoints: [])
      expect(result).to eq(txid: txid_a, broadcast_status: 'sending')
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Enqueue — finalize path (nil outpoints)
  # ---------------------------------------------------------------------------
  describe '#enqueue (finalize path)' do
    it 'stores nil input_outpoints and change_outpoints' do
      enqueue_finalize(txid: txid_a)
      row = job_row(txid_a)
      expect(row[:input_outpoints]).to be_nil
      expect(row[:change_outpoints]).to be_nil
    end

    it 'stores nil fund_ref' do
      enqueue_finalize(txid: txid_a)
      expect(job_row(txid_a)[:fund_ref]).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Enqueue — duplicate txid (idempotent crash recovery)
  # ---------------------------------------------------------------------------
  describe '#enqueue (duplicate txid)' do
    it 'does not raise on duplicate txid and returns existing status' do
      enqueue_auto_fund(txid: txid_a, input_outpoints: [], change_outpoints: [])
      result = nil
      expect { result = enqueue_auto_fund(txid: txid_a, input_outpoints: [], change_outpoints: []) }.not_to raise_error
      expect(result[:txid]).to eq(txid_a)
      expect(result[:broadcast_status]).to be_a(String)
    end

    it 'inserts exactly one row on duplicate enqueue' do
      enqueue_auto_fund(txid: txid_a, input_outpoints: [], change_outpoints: [])
      enqueue_auto_fund(txid: txid_a, input_outpoints: [], change_outpoints: [])
      expect(db[:wallet_broadcast_jobs].where(txid: txid_a).count).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Status
  # ---------------------------------------------------------------------------
  describe '#status' do
    it 'returns the job status for a known txid' do
      enqueue_auto_fund(txid: txid_a, input_outpoints: [], change_outpoints: [])
      expect(adapter.status(txid_a)).to eq('unsent')
    end

    it 'returns nil for an unknown txid' do
      expect(adapter.status('0' * 64)).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Worker — success path (auto-fund)
  # ---------------------------------------------------------------------------
  describe 'worker success path (auto-fund)' do
    let(:mock_tx) { double('tx') } # rubocop:disable RSpec/VerifiedDoubles

    before do
      seed_pending_input(outpoint: 'inp:0', fund_ref: 'ref-001')
      seed_pending_change(outpoint: 'chg:0')
      seed_action(txid: txid_a)
      enqueue_auto_fund(
        txid: txid_a,
        input_outpoints: ['inp:0'],
        change_outpoints: ['chg:0'],
        fund_ref: 'ref-001'
      )
      allow(broadcaster).to receive(:broadcast).and_return(double('result')) # rubocop:disable RSpec/VerifiedDoubles
      allow(BSV::Transaction::Transaction).to receive(:from_beef_hex).and_return(mock_tx)
      adapter.start
      sleep(0.5)
      adapter.drain
    end

    it 'marks the job as completed' do
      expect(job_row(txid_a)[:status]).to eq('completed')
    end

    it 'promotes input outputs to spent' do
      expect(output_state('inp:0').to_s).to eq('spent')
    end

    it 'promotes change outputs to spendable' do
      expect(output_state('chg:0').to_s).to eq('spendable')
    end

    it 'updates action status to completed' do
      expect(action_status(txid_a)).to eq('completed')
    end
  end

  # ---------------------------------------------------------------------------
  # 8. Worker — failure path (auto-fund)
  # ---------------------------------------------------------------------------
  describe 'worker failure path (auto-fund)' do
    let(:mock_tx) { double('tx') } # rubocop:disable RSpec/VerifiedDoubles

    before do
      seed_pending_input(outpoint: 'inp:0', fund_ref: 'ref-001')
      seed_pending_change(outpoint: 'chg:0')
      seed_action(txid: txid_a)
      enqueue_auto_fund(
        txid: txid_a,
        input_outpoints: ['inp:0'],
        change_outpoints: ['chg:0'],
        fund_ref: 'ref-001'
      )
      allow(broadcaster).to receive(:broadcast).and_raise(StandardError, 'network down')
      allow(BSV::Transaction::Transaction).to receive(:from_beef_hex).and_return(mock_tx)
      adapter.start
      sleep(0.5)
      adapter.drain
    end

    it 'marks the job as failed' do
      expect(job_row(txid_a)[:status]).to eq('failed')
    end

    it 'populates last_error on the job' do
      expect(job_row(txid_a)[:last_error]).to eq('network down')
    end

    it 'rolls back input outputs to spendable' do
      expect(output_state('inp:0').to_s).to eq('spendable')
    end

    it 'deletes change outputs' do
      all = storage.find_outputs({ include_spent: true, limit: 100, offset: 0 })
      expect(all.map { |o| o[:outpoint] }).not_to include('chg:0')
    end

    it 'updates action status to failed' do
      expect(action_status(txid_a)).to eq('failed')
    end

    it 'increments attempts' do
      expect(job_row(txid_a)[:attempts]).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # 9. Worker — finalize path success
  # ---------------------------------------------------------------------------
  describe 'worker finalize path, broadcast succeeds' do
    let(:mock_tx) { double('tx') } # rubocop:disable RSpec/VerifiedDoubles

    before do
      seed_action(txid: txid_a)
      enqueue_finalize(txid: txid_a)
      allow(broadcaster).to receive(:broadcast).and_return(double('result')) # rubocop:disable RSpec/VerifiedDoubles
      allow(BSV::Transaction::Transaction).to receive(:from_beef_hex).and_return(mock_tx)
      adapter.start
      sleep(0.5)
      adapter.drain
    end

    it 'updates action status to completed' do
      expect(action_status(txid_a)).to eq('completed')
    end

    it 'marks job as completed' do
      expect(job_row(txid_a)[:status]).to eq('completed')
    end

    it 'does not create or remove any outputs' do
      all = storage.find_outputs({ include_spent: true, limit: 100, offset: 0 })
      expect(all).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # 10. Worker — finalize path failure
  # ---------------------------------------------------------------------------
  describe 'worker finalize path, broadcast fails' do
    let(:mock_tx) { double('tx') } # rubocop:disable RSpec/VerifiedDoubles

    before do
      seed_action(txid: txid_a)
      enqueue_finalize(txid: txid_a)
      allow(broadcaster).to receive(:broadcast).and_raise(StandardError, 'timeout')
      allow(BSV::Transaction::Transaction).to receive(:from_beef_hex).and_return(mock_tx)
      adapter.start
      sleep(0.5)
      adapter.drain
    end

    it 'updates action status to failed' do
      expect(action_status(txid_a)).to eq('failed')
    end

    it 'marks job as failed with last_error' do
      row = job_row(txid_a)
      expect(row[:status]).to eq('failed')
      expect(row[:last_error]).to eq('timeout')
    end

    it 'does not create or remove any outputs' do
      all = storage.find_outputs({ include_spent: true, limit: 100, offset: 0 })
      expect(all).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # 11. Recovery — stale sending job
  # ---------------------------------------------------------------------------
  describe 'recovery of stale sending jobs' do
    let(:mock_tx) { double('tx') } # rubocop:disable RSpec/VerifiedDoubles

    it 'retries a stale sending job (locked_at well past threshold)' do
      db[:wallet_broadcast_jobs].insert(
        txid: txid_a,
        beef_hex: beef_hex,
        input_outpoints: nil,
        change_outpoints: nil,
        fund_ref: nil,
        status: 'sending',
        locked_at: Sequel.lit('NOW() - interval \'600 second\''),
        attempts: 1,
        created_at: Sequel.lit('NOW()'),
        updated_at: Sequel.lit('NOW()')
      )
      seed_action(txid: txid_a)
      allow(broadcaster).to receive(:broadcast).and_return(double('result')) # rubocop:disable RSpec/VerifiedDoubles
      allow(BSV::Transaction::Transaction).to receive(:from_beef_hex).and_return(mock_tx)

      adapter.start
      sleep(0.5)
      adapter.drain

      expect(job_row(txid_a)[:status]).to eq('completed')
    end

    it 'does not retry a recently-locked sending job' do
      # Insert a job locked just now (within the 60s stale_threshold we will use)
      db[:wallet_broadcast_jobs].insert(
        txid: txid_a,
        beef_hex: beef_hex,
        input_outpoints: nil,
        change_outpoints: nil,
        fund_ref: nil,
        status: 'sending',
        locked_at: Sequel.lit('NOW()'),
        attempts: 1,
        created_at: Sequel.lit('NOW()'),
        updated_at: Sequel.lit('NOW()')
      )
      allow(BSV::Transaction::Transaction).to receive(:from_beef_hex).and_return(mock_tx)
      allow(broadcaster).to receive(:broadcast).and_return(double('result')) # rubocop:disable RSpec/VerifiedDoubles

      # Use a 60s threshold — a job locked NOW() is not yet stale
      adapter2 = BSV::Wallet::SolidQueueAdapter.new(
        db: db,
        storage: storage,
        broadcaster: broadcaster,
        poll_interval: 0.1,
        stale_threshold: 60
      )
      adapter2.start
      sleep(0.4)
      adapter2.drain

      # Job should remain 'sending' — it was not stale enough to be retried
      expect(job_row(txid_a)[:status]).to eq('sending')
    end
  end

  # ---------------------------------------------------------------------------
  # 12. Drain / shutdown
  # ---------------------------------------------------------------------------
  describe '#drain' do
    it 'blocks until the worker thread finishes' do
      allow(broadcaster).to receive(:broadcast)
      adapter.start
      thread = adapter.instance_variable_get(:@worker_thread)
      adapter.drain
      expect(thread.alive?).to be(false)
    end

    it 'worker thread is not alive after drain' do
      adapter.start
      adapter.drain
      thread = adapter.instance_variable_get(:@worker_thread)
      expect(thread&.alive?).not_to be(true)
    end
  end

  # ---------------------------------------------------------------------------
  # 13. Thread safety
  # ---------------------------------------------------------------------------
  describe 'thread safety' do
    it 'handles concurrent enqueue from multiple threads with unique txids' do
      txids = (1..5).map { |i| i.to_s.rjust(64, '0') }
      threads = txids.map do |id|
        Thread.new do
          adapter.enqueue(
            txid: id,
            beef_binary: beef_binary,
            input_outpoints: [],
            change_outpoints: [],
            fund_ref: 'ref'
          )
        end
      end
      threads.each(&:join)
      expect(db[:wallet_broadcast_jobs].count).to eq(5)
    end

    it 'handles concurrent enqueue with the same txid without raising' do
      errors = []
      threads = Array.new(5) do
        Thread.new do
          adapter.enqueue(
            txid: txid_a,
            beef_binary: beef_binary,
            input_outpoints: [],
            change_outpoints: [],
            fund_ref: 'ref'
          )
        rescue StandardError => e
          errors << e
        end
      end
      threads.each(&:join)
      expect(errors).to be_empty
      expect(db[:wallet_broadcast_jobs].where(txid: txid_a).count).to eq(1)
    end

    it 'start is idempotent — calling twice does not spawn two threads' do
      allow(broadcaster).to receive(:broadcast)
      adapter.start
      thread_before = adapter.instance_variable_get(:@worker_thread)
      adapter.start
      thread_after = adapter.instance_variable_get(:@worker_thread)
      expect(thread_after).to equal(thread_before)
      adapter.drain
    end
  end
end
