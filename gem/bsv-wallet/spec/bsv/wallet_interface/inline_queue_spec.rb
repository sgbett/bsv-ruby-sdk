# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::InlineQueue do
  let(:storage)     { BSV::Wallet::MemoryStore.new }
  let(:broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles

  # --------------------------------------------------------------------------
  # Shared seeding helpers
  # --------------------------------------------------------------------------

  # Seeds a spendable output and returns its outpoint string.
  def seed_output(store, outpoint:, satoshis: 1_000)
    store.store_output(
      outpoint: outpoint,
      satoshis: satoshis,
      state: :spendable,
      basket: 'default'
    )
    outpoint
  end

  # Seeds a pending output (locked as input) and returns its outpoint string.
  def seed_pending_output(store, outpoint:, satoshis: 1_000, fund_ref: 'ref-001')
    store.store_output(
      outpoint: outpoint,
      satoshis: satoshis,
      state: :pending,
      basket: 'default',
      pending_reference: fund_ref
    )
    outpoint
  end

  # Seeds a pending change output and returns its outpoint string.
  def seed_change_output(store, outpoint:, satoshis: 500)
    store.store_output(
      outpoint: outpoint,
      satoshis: satoshis,
      state: :pending,
      basket: 'default'
    )
    outpoint
  end

  # Seeds an action in 'signed' state and returns the txid.
  def seed_action(store, txid:, status: 'signed')
    store.store_action(txid: txid, description: 'test action', status: status)
    txid
  end

  # Builds a minimal broadcast payload.
  def build_payload(txid:, input_outpoints:, change_outpoints:, fund_ref: 'ref-001', accept_delayed_broadcast: false)
    tx = BSV::Transaction::Transaction.new
    beef_binary = tx.to_beef
    {
      tx: tx,
      txid: txid,
      beef_binary: beef_binary,
      input_outpoints: input_outpoints,
      change_outpoints: change_outpoints,
      fund_ref: fund_ref,
      accept_delayed_broadcast: accept_delayed_broadcast
    }
  end

  # --------------------------------------------------------------------------
  # 1. With broadcaster — broadcast succeeds
  # --------------------------------------------------------------------------
  describe 'with broadcaster, broadcast succeeds' do
    let(:queue)  { described_class.new(storage: storage, broadcaster: broadcaster) }
    let(:payload) do
      build_payload(
        txid: txid,
        input_outpoints: ['abc:0'],
        change_outpoints: ['xyz:0'],
        fund_ref: 'ref-001'
      )
    end
    let(:result) { queue.enqueue(payload) }
    let(:txid)   { 'a' * 64 }
    let(:input1) { seed_pending_output(storage, outpoint: 'abc:0', fund_ref: 'ref-001') }
    let(:change1) { seed_change_output(storage, outpoint: 'xyz:0') }

    before do
      input1
      change1
      seed_action(storage, txid: txid)
      allow(broadcaster).to receive(:broadcast).and_return(
        BSV::Network::BroadcastResponse.new(txid: txid, tx_status: 'SEEN_ON_NETWORK')
      )
    end

    it 'returns broadcast_status: "success"' do
      expect(result[:broadcast_status]).to eq('success')
    end

    it 'returns the txid' do
      expect(result[:txid]).to eq(txid)
    end

    it 'promotes input outputs to :spent' do
      result
      all = storage.find_outputs({ include_spent: true, limit: 100, offset: 0 })
      input = all.find { |o| o[:outpoint] == 'abc:0' }
      expect(input[:state]).to eq(:spent)
    end

    it 'promotes change outputs to :spendable' do
      result
      spendable = storage.find_spendable_outputs
      outpoints = spendable.map { |o| o[:outpoint] }
      expect(outpoints).to include('xyz:0')
    end

    it 'updates action status to "completed"' do
      result
      actions = storage.find_actions({ limit: 10, offset: 0 })
      action = actions.find { |a| a[:txid] == txid }
      expect(action[:status]).to eq('completed')
    end
  end

  # --------------------------------------------------------------------------
  # 2. With broadcaster — broadcast fails
  # --------------------------------------------------------------------------
  describe 'with broadcaster, broadcast fails' do
    let(:queue)  { described_class.new(storage: storage, broadcaster: broadcaster) }
    let(:payload) do
      build_payload(
        txid: txid,
        input_outpoints: ['inp:0'],
        change_outpoints: ['chg:0'],
        fund_ref: 'ref-fail'
      )
    end
    let(:result) { queue.enqueue(payload) }
    let(:txid)   { 'b' * 64 }
    let(:input1) { seed_pending_output(storage, outpoint: 'inp:0', fund_ref: 'ref-fail') }
    let(:change1) { seed_change_output(storage, outpoint: 'chg:0') }

    before do
      input1
      change1
      seed_action(storage, txid: txid)
      allow(broadcaster).to receive(:broadcast).and_raise(
        BSV::Network::BroadcastError.new('network error', arc_status: 'REJECTED')
      )
    end

    it 'returns a broadcast_error string' do
      expect(result[:broadcast_error]).to be_a(String)
    end

    it 'returns broadcast_status: "invalidTx" for REJECTED' do
      expect(result[:broadcast_status]).to eq('invalidTx')
    end

    it 'rolls back input outputs to :spendable' do
      result
      spendable = storage.find_spendable_outputs
      outpoints = spendable.map { |o| o[:outpoint] }
      expect(outpoints).to include('inp:0')
    end

    it 'deletes change outputs' do
      result
      all = storage.find_outputs({ include_spent: true, limit: 100, offset: 0 })
      outpoints = all.map { |o| o[:outpoint] }
      expect(outpoints).not_to include('chg:0')
    end

    it 'updates action status to "failed"' do
      result
      actions = storage.find_actions({ limit: 10, offset: 0 })
      action = actions.find { |a| a[:txid] == txid }
      expect(action[:status]).to eq('failed')
    end
  end

  # --------------------------------------------------------------------------
  # 3. Without broadcaster — promotes immediately
  # --------------------------------------------------------------------------
  describe 'without broadcaster' do
    let(:queue) { described_class.new(storage: storage) }
    let(:payload) do
      build_payload(
        txid: txid,
        input_outpoints: ['in2:0'],
        change_outpoints: ['ch2:0'],
        fund_ref: 'ref-nb'
      )
    end
    let(:result) { queue.enqueue(payload) }
    let(:txid)   { 'c' * 64 }
    let(:input1) { seed_pending_output(storage, outpoint: 'in2:0', fund_ref: 'ref-nb') }
    let(:change1) { seed_change_output(storage, outpoint: 'ch2:0') }

    before do
      input1
      change1
      seed_action(storage, txid: txid)
    end

    it 'returns the txid' do
      expect(result[:txid]).to eq(txid)
    end

    it 'returns tx bytes' do
      expect(result[:tx]).to be_an(Array)
    end

    it 'does not return broadcast_status' do
      expect(result).not_to have_key(:broadcast_status)
    end

    it 'promotes input outputs to :spent' do
      result
      all = storage.find_outputs({ include_spent: true, limit: 100, offset: 0 })
      input = all.find { |o| o[:outpoint] == 'in2:0' }
      expect(input[:state]).to eq(:spent)
    end

    it 'promotes change outputs to :spendable' do
      result
      spendable = storage.find_spendable_outputs
      outpoints = spendable.map { |o| o[:outpoint] }
      expect(outpoints).to include('ch2:0')
    end

    it 'sets action status to "completed"' do
      result
      actions = storage.find_actions({ limit: 10, offset: 0 })
      action = actions.find { |a| a[:txid] == txid }
      expect(action[:status]).to eq('completed')
    end
  end

  # --------------------------------------------------------------------------
  # 4. Without broadcaster + accept_delayed_broadcast
  # --------------------------------------------------------------------------
  describe 'without broadcaster, accept_delayed_broadcast: true' do
    let(:queue) { described_class.new(storage: storage) }
    let(:payload) do
      build_payload(
        txid: txid,
        input_outpoints: ['in3:0'],
        change_outpoints: ['ch3:0'],
        fund_ref: 'ref-delayed',
        accept_delayed_broadcast: true
      )
    end
    let(:result) { queue.enqueue(payload) }
    let(:txid)   { 'd' * 64 }

    before do
      seed_pending_output(storage, outpoint: 'in3:0', fund_ref: 'ref-delayed')
      seed_change_output(storage, outpoint: 'ch3:0')
      seed_action(storage, txid: txid)
    end

    it 'sets action status to "unproven"' do
      result
      actions = storage.find_actions({ limit: 10, offset: 0 })
      action = actions.find { |a| a[:txid] == txid }
      expect(action[:status]).to eq('unproven')
    end
  end

  # --------------------------------------------------------------------------
  # 5. Finalize path (nil outpoints) — broadcast succeeds
  # --------------------------------------------------------------------------
  describe 'finalize path (nil outpoints), broadcast succeeds' do
    let(:queue) { described_class.new(storage: storage, broadcaster: broadcaster) }
    let(:payload) do
      {
        tx: BSV::Transaction::Transaction.new,
        txid: txid,
        beef_binary: BSV::Transaction::Transaction.new.to_beef,
        input_outpoints: nil,
        change_outpoints: nil,
        fund_ref: nil,
        accept_delayed_broadcast: false
      }
    end
    let(:result) { queue.enqueue(payload) }
    let(:txid)   { 'e' * 64 }

    before do
      seed_action(storage, txid: txid)
      allow(broadcaster).to receive(:broadcast).and_return(
        BSV::Network::BroadcastResponse.new(txid: txid, tx_status: 'SEEN_ON_NETWORK')
      )
    end

    it 'returns broadcast_status: "success"' do
      expect(result[:broadcast_status]).to eq('success')
    end

    it 'updates action status to "completed"' do
      result
      actions = storage.find_actions({ limit: 10, offset: 0 })
      action = actions.find { |a| a[:txid] == txid }
      expect(action[:status]).to eq('completed')
    end

    it 'does not add any extra outputs' do
      result
      all = storage.find_outputs({ include_spent: true, limit: 100, offset: 0 })
      expect(all).to be_empty
    end
  end

  # --------------------------------------------------------------------------
  # 6. Finalize path (nil outpoints) — broadcast fails
  # --------------------------------------------------------------------------
  describe 'finalize path (nil outpoints), broadcast fails' do
    let(:queue) { described_class.new(storage: storage, broadcaster: broadcaster) }
    let(:payload) do
      {
        tx: BSV::Transaction::Transaction.new,
        txid: txid,
        beef_binary: BSV::Transaction::Transaction.new.to_beef,
        input_outpoints: nil,
        change_outpoints: nil,
        fund_ref: nil,
        accept_delayed_broadcast: false
      }
    end
    let(:result) { queue.enqueue(payload) }
    let(:txid)   { 'f' * 64 }

    before do
      seed_action(storage, txid: txid)
      allow(broadcaster).to receive(:broadcast).and_raise(
        BSV::Network::BroadcastError.new('double spend', arc_status: 'DOUBLE_SPEND_ATTEMPTED')
      )
    end

    it 'returns broadcast_status: "doubleSpend"' do
      expect(result[:broadcast_status]).to eq('doubleSpend')
    end

    it 'updates action status to "failed"' do
      result
      actions = storage.find_actions({ limit: 10, offset: 0 })
      action = actions.find { |a| a[:txid] == txid }
      expect(action[:status]).to eq('failed')
    end

    it 'does not add or remove any outputs' do
      result
      all = storage.find_outputs({ include_spent: true, limit: 100, offset: 0 })
      expect(all).to be_empty
    end
  end

  # --------------------------------------------------------------------------
  # 7. #async?
  # --------------------------------------------------------------------------
  describe '#async?' do
    it 'returns false' do
      queue = described_class.new(storage: storage)
      expect(queue.async?).to be(false)
    end
  end

  # --------------------------------------------------------------------------
  # 8. #status — delegates to storage
  # --------------------------------------------------------------------------
  describe '#status' do
    let(:queue) { described_class.new(storage: storage) }
    let(:txid)  { '0' * 64 }

    it 'returns the action status from storage' do
      storage.store_action(txid: txid, description: 'test', status: 'completed')
      expect(queue.status(txid)).to eq('completed')
    end

    it 'returns nil when the action is not found' do
      expect(queue.status('nonexistent')).to be_nil
    end
  end
end
