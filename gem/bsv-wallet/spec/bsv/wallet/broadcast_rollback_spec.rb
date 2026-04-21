# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'securerandom'

# Integration specs for broadcast_and_promote and promote_no_send flows.
#
# These specs exercise the combined behaviour introduced by Tasks 1-3 of HLR #379:
#   - Task 1: change outputs stored as :pending immediately (TOCTOU fix)
#   - Task 2: broadcast and promotion error handling are isolated
#   - Task 3: per-tx rollback for send_with batch broadcasts
#
# All specs use a real MemoryStore and a mock broadcaster so state transitions
# can be inspected directly without hitting the network.

STORE_FACTORIES.each do |store_label, store_factory|
RSpec.describe "broadcast_and_promote and promote_no_send integration (#{store_label})" do
  # --------------------------------------------------------------------------
  # Shared helpers
  # --------------------------------------------------------------------------

  # Stores a real BRC-29-derivable UTXO in storage so auto-fund can select it.
  def seed_payment_output(wallet, satoshis:)
    deriver = wallet.key_deriver
    prefix = SecureRandom.hex(8)
    suffix = SecureRandom.hex(8)
    sender_pub = deriver.identity_key

    derived_pub = deriver.derive_public_key(
      [2, '3241645161d8'],
      "#{prefix} #{suffix}",
      sender_pub,
      for_self: true
    )
    locking_script = BSV::Script::Script.p2pkh_lock(derived_pub.hash160)

    source_tx = BSV::Transaction::Transaction.new
    source_tx.add_output(
      BSV::Transaction::TransactionOutput.new(
        satoshis: satoshis,
        locking_script: locking_script
      )
    )
    txid = source_tx.txid_hex
    outpoint = "#{txid}.0"

    wallet.storage.store_transaction(txid, source_tx.to_hex)
    wallet.storage.store_output({
                                  outpoint: outpoint,
                                  satoshis: satoshis,
                                  locking_script: locking_script.to_hex,
                                  basket: 'default',
                                  state: :spendable,
                                  spendable: true,
                                  derivation_prefix: prefix,
                                  derivation_suffix: suffix,
                                  sender_identity_key: sender_pub,
                                  source_tx_hex: source_tx.to_hex
                                })

    { outpoint: outpoint, satoshis: satoshis }
  end

  # Returns a P2PKH locking script hex for an arbitrary recipient.
  def recipient_lock_hex
    BSV::Script::Script.p2pkh_lock(BSV::Primitives::PrivateKey.generate.public_key.hash160).to_hex
  end

  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:storage)     { store_factory.call }

  # A successful broadcast response (no competing_txs).
  let(:broadcast_ok) do
    BSV::Network::BroadcastResponse.new(txid: 'aabbcc', tx_status: 'SEEN_ON_NETWORK')
  end

  # --------------------------------------------------------------------------
  # 1. broadcast_and_promote — broadcast succeeds
  # --------------------------------------------------------------------------
  describe 'broadcast succeeds → state promoted to final' do
    let(:broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles
    let(:wallet) do
      BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster)
    end
    let(:result) do
      allow(broadcaster).to receive(:broadcast).and_return(broadcast_ok)

      wallet.create_action({
                             description: 'broadcast success integration',
                             outputs: [{
                               locking_script: recipient_lock_hex,
                               satoshis: 1_000,
                               output_description: 'payment to recipient'
                             }]
                           })
    end

    before { seed_payment_output(wallet, satoshis: 10_000) }

    it 'returns a 64-char hex txid' do
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'returns broadcast_status: "success"' do
      expect(result[:broadcast_status]).to eq('success')
    end

    it 'marks the input UTXO as :spent' do
      txid = result[:txid]
      all = storage.find_outputs({ include_spent: true, limit: 1000, offset: 0 })
      tx = BSV::Transaction::Transaction.from_hex(storage.find_transaction(txid))
      # Each input outpoint in the transaction must be :spent in storage
      tx.inputs.each do |inp|
        source_txid = inp.prev_tx_id.reverse.unpack1('H*')
        vout = inp.prev_tx_out_index
        outpoint = "#{source_txid}.#{vout}"
        stored = all.find { |o| o[:outpoint] == outpoint }
        next unless stored # input may be external; only check wallet-tracked inputs

        expect(stored[:state]).to eq(:spent)
      end
    end

    it 'marks change outputs as :spendable' do
      result
      spendable = storage.find_spendable_outputs(basket: 'default')
      # Change outputs (those with derivation metadata) must be :spendable
      change = spendable.select { |o| o[:derivation_prefix] }
      expect(change).not_to be_empty
      change.each { |o| expect(o[:state]).to eq(:spendable) }
    end

    # Post-HLR #455: 'unproven' until a merkle proof lands via internalize_action
    it 'stores the action with status "unproven"' do
      txid = result[:txid]
      actions = storage.find_actions({ limit: 100, offset: 0 })
      action = actions.find { |a| a[:txid] == txid }
      expect(action[:status]).to eq('unproven')
    end
  end

  # --------------------------------------------------------------------------
  # 2. broadcast_and_promote — broadcast fails → full rollback
  # --------------------------------------------------------------------------
  describe 'broadcast fails → full rollback' do
    let(:broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles
    let(:wallet) do
      BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster)
    end
    let(:seeded_outpoint) { seed_payment_output(wallet, satoshis: 10_000)[:outpoint] }
    let(:result) do
      seeded_outpoint # ensure the UTXO is seeded before creating the action
      allow(broadcaster).to receive(:broadcast).and_raise(
        BSV::Network::BroadcastError.new('network unavailable', arc_status: nil)
      )

      wallet.create_action({
                             description: 'broadcast failure rollback test',
                             outputs: [{
                               locking_script: recipient_lock_hex,
                               satoshis: 1_000,
                               output_description: 'payment attempted'
                             }]
                           })
    end

    it 'returns a result hash (does not raise)' do
      expect { result }.not_to raise_error
    end

    it 'returns broadcast_error in the result' do
      expect(result[:broadcast_error]).to be_a(String)
    end

    it 'returns broadcast_status "serviceError"' do
      expect(result[:broadcast_status]).to eq('serviceError')
    end

    it 'releases input UTXOs back to :spendable' do
      result
      spendable = storage.find_spendable_outputs
      spendable_outpoints = spendable.map { |o| o[:outpoint] }
      expect(spendable_outpoints).to include(seeded_outpoint)
    end

    it 'removes change outputs from storage' do
      result
      all = storage.find_outputs({ include_spent: true, limit: 1000, offset: 0 })
      # After rollback, only the original seeded UTXO should remain
      expect(all.size).to eq(1)
      expect(all.first[:outpoint]).to eq(seeded_outpoint)
    end

    it 'sets the action status to "failed"' do
      txid = result[:txid]
      all_actions = storage.find_actions({ limit: 100, offset: 0 })
      action = all_actions.find { |a| a[:txid] == txid }
      expect(action[:status]).to eq('failed')
    end
  end

  # --------------------------------------------------------------------------
  # 3. Promotion failure after successful broadcast → no rollback
  #
  # This validates the Task 2 invariant: only broadcast failure triggers rollback.
  # If the broadcast succeeds but a subsequent promotion step raises (e.g. storage
  # write failure), the error propagates and on-chain outputs are NOT deleted.
  # --------------------------------------------------------------------------
  describe 'promotion failure after successful broadcast → no rollback of on-chain outputs' do
    let(:broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles
    let(:wallet) do
      BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster)
    end

    before { seed_payment_output(wallet, satoshis: 10_000) }

    it 'propagates the promotion error without deleting change outputs' do
      allow(broadcaster).to receive(:broadcast).and_return(broadcast_ok)

      # Inject a failure in update_output_state — fires during promotion of inputs
      # (first call after broadcast success). The broadcast has already succeeded
      # so the transaction is on-chain; storage must not be rolled back.
      call_count = 0
      allow(storage).to receive(:update_output_state).and_wrap_original do |original, *args|
        call_count += 1
        raise 'simulated storage failure' if call_count == 1

        original.call(*args)
      end

      expect do
        wallet.create_action({
                               description: 'promotion failure no rollback test',
                               outputs: [{
                                 locking_script: recipient_lock_hex,
                                 satoshis: 1_000,
                                 output_description: 'broadcast-then-promotion-failure'
                               }]
                             })
      end.to raise_error(RuntimeError, 'simulated storage failure')

      # Change outputs must still exist in storage — NOT deleted — because the
      # transaction was already confirmed on-chain before the failure.
      all = storage.find_outputs({ include_spent: true, limit: 1000, offset: 0 })
      # At least 2 outputs: original input UTXO + change output(s)
      expect(all.size).to be >= 2
    end
  end

  # --------------------------------------------------------------------------
  # 4. send_with broadcast succeeds → per-tx state promoted, pending cleaned up
  # --------------------------------------------------------------------------
  describe 'send_with broadcast succeeds → per-tx state promoted' do
    let(:broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles
    let(:wallet) do
      BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster)
    end
    let(:first_no_send) do
      wallet.create_action({
                             description: 'first no send transaction one',
                             outputs: [{
                               locking_script: recipient_lock_hex,
                               satoshis: 500,
                               output_description: 'first no_send output'
                             }],
                             options: { no_send: true }
                           })
    end
    let(:second_no_send) do
      wallet.create_action({
                             description: 'second no send transaction two',
                             outputs: [{
                               locking_script: recipient_lock_hex,
                               satoshis: 500,
                               output_description: 'second no_send output'
                             }],
                             options: { no_send: true }
                           })
    end

    before do
      seed_payment_output(wallet, satoshis: 10_000)
      seed_payment_output(wallet, satoshis: 8_000)
    end

    it 'promotes both transactions to unproven after send_with succeeds' do
      txid1 = first_no_send[:txid]
      txid2 = second_no_send[:txid]

      allow(broadcaster).to receive(:broadcast).and_return(broadcast_ok)

      result = wallet.create_action({
                                      description: 'send with batch broadcast test',
                                      options: { send_with: [txid1, txid2] }
                                    })

      send_with_results = result[:send_with_results]
      expect(send_with_results).to be_an(Array)
      expect(send_with_results.size).to eq(2)
      send_with_results.each do |r|
        expect(r[:status]).to eq('unproven')
      end
    end

    it 'promotes input UTXOs to :spent for both transactions' do
      txid1 = first_no_send[:txid]
      txid2 = second_no_send[:txid]

      allow(broadcaster).to receive(:broadcast).and_return(broadcast_ok)

      wallet.create_action({
                             description: 'send with input state test',
                             options: { send_with: [txid1, txid2] }
                           })

      # No original seeded UTXOs should remain spendable
      spendable = storage.find_spendable_outputs
      # Only change outputs (with derivation metadata) should be spendable
      non_change_spendable = spendable.reject { |o| o[:derivation_prefix] }
      expect(non_change_spendable).to be_empty
    end

    it 'promotes change outputs to :spendable for both transactions' do
      txid1 = first_no_send[:txid]
      txid2 = second_no_send[:txid]

      allow(broadcaster).to receive(:broadcast).and_return(broadcast_ok)

      wallet.create_action({
                             description: 'send with change state test',
                             options: { send_with: [txid1, txid2] }
                           })

      spendable = storage.find_spendable_outputs
      change = spendable.select { |o| o[:derivation_prefix] }
      expect(change).not_to be_empty
    end

    it 'sets action status to "unproven" for both transactions' do
      txid1 = first_no_send[:txid]
      txid2 = second_no_send[:txid]

      allow(broadcaster).to receive(:broadcast).and_return(broadcast_ok)

      wallet.create_action({
                             description: 'send with action status test',
                             options: { send_with: [txid1, txid2] }
                           })

      all_actions = storage.find_actions({ limit: 100, offset: 0 })
      [txid1, txid2].each do |txid|
        action = all_actions.find { |a| a[:txid] == txid }
        expect(action[:status]).to eq('unproven')
      end
    end
  end

  # --------------------------------------------------------------------------
  # 5. send_with broadcast fails → per-tx rollback, other txs unaffected
  # --------------------------------------------------------------------------
  describe 'send_with broadcast fails → per-tx rollback' do
    let(:broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles
    let(:wallet) do
      BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster)
    end
    let(:first_no_send) do
      wallet.create_action({
                             description: 'first no send tx for fail test',
                             outputs: [{
                               locking_script: recipient_lock_hex,
                               satoshis: 500,
                               output_description: 'first no_send output'
                             }],
                             options: { no_send: true }
                           })
    end
    let(:second_no_send) do
      wallet.create_action({
                             description: 'second no send tx for fail test',
                             outputs: [{
                               locking_script: recipient_lock_hex,
                               satoshis: 500,
                               output_description: 'second no_send output'
                             }],
                             options: { no_send: true }
                           })
    end

    before do
      seed_payment_output(wallet, satoshis: 10_000)
      seed_payment_output(wallet, satoshis: 8_000)
    end

    it 'rolls back the failed tx and succeeds for the other' do
      txid1 = first_no_send[:txid]
      txid2 = second_no_send[:txid]

      # First broadcast fails, second succeeds
      call_count = 0
      allow(broadcaster).to receive(:broadcast) do
        call_count += 1
        raise BSV::Network::BroadcastError.new('rejected', arc_status: nil) if call_count == 1

        broadcast_ok
      end

      result = wallet.create_action({
                                      description: 'send with partial failure test',
                                      options: { send_with: [txid1, txid2] }
                                    })

      send_with_results = result[:send_with_results]
      statuses = send_with_results.to_h { |r| [r[:txid], r[:status]] }
      expect(statuses[txid1]).to eq('failed')
      expect(statuses[txid2]).to eq('unproven')
    end

    it 'sets action status to "failed" for the rolled-back tx' do
      txid1 = first_no_send[:txid]
      txid2 = second_no_send[:txid]

      call_count = 0
      allow(broadcaster).to receive(:broadcast) do
        call_count += 1
        raise BSV::Network::BroadcastError.new('rejected', arc_status: nil) if call_count == 1

        broadcast_ok
      end

      wallet.create_action({
                             description: 'send with partial fail action status',
                             options: { send_with: [txid1, txid2] }
                           })

      all_actions = storage.find_actions({ limit: 100, offset: 0 })
      action_first = all_actions.find { |a| a[:txid] == txid1 }
      action_second = all_actions.find { |a| a[:txid] == txid2 }
      expect(action_first[:status]).to eq('failed')
      expect(action_second[:status]).to eq('unproven')
    end

    it 'releases input UTXOs back to :spendable for the failed tx only' do
      txid1 = first_no_send[:txid]
      txid2 = second_no_send[:txid]

      # Track the outpoints each no_send tx consumed
      no_send_tx_first = BSV::Transaction::Transaction.from_hex(storage.find_transaction(txid1))
      no_send_tx_second = BSV::Transaction::Transaction.from_hex(storage.find_transaction(txid2))

      first_input_ops = no_send_tx_first.inputs.map { |i| "#{i.prev_tx_id.reverse.unpack1('H*')}.#{i.prev_tx_out_index}" }
      second_input_ops = no_send_tx_second.inputs.map { |i| "#{i.prev_tx_id.reverse.unpack1('H*')}.#{i.prev_tx_out_index}" }

      call_count = 0
      allow(broadcaster).to receive(:broadcast) do
        call_count += 1
        raise BSV::Network::BroadcastError.new('rejected', arc_status: nil) if call_count == 1

        broadcast_ok
      end

      wallet.create_action({
                             description: 'send with per tx rollback state test',
                             options: { send_with: [txid1, txid2] }
                           })

      spendable = storage.find_spendable_outputs
      spendable_ops = spendable.map { |o| o[:outpoint] }

      # Inputs of the failed tx are back to :spendable
      first_input_ops.each { |op| expect(spendable_ops).to include(op) }

      # Inputs of the successful tx are :spent (not spendable)
      second_input_ops.each { |op| expect(spendable_ops).not_to include(op) }
    end
  end

  # --------------------------------------------------------------------------
  # 6. Concurrent auto-fund exclusion — pending change outputs are not selectable
  #
  # Validates the Task 1 fix: change outputs stored as :pending immediately
  # cannot be selected by a concurrent auto-fund call.
  # --------------------------------------------------------------------------
  describe 'concurrent auto-fund exclusion of pending change outputs' do
    let(:broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles
    let(:wallet) do
      BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster)
    end

    before { seed_payment_output(wallet, satoshis: 10_000) }

    it 'raises InsufficientFundsError when the only spendable UTXO is locked as :pending' do
      # Create a no_send transaction — the original UTXO becomes :pending and
      # change is stored directly as :pending (Task 1 fix). Nothing is :spendable.
      allow(broadcaster).to receive(:broadcast).and_return(broadcast_ok)

      wallet.create_action({
                             description: 'no send locks all utxos test',
                             outputs: [{
                               locking_script: recipient_lock_hex,
                               satoshis: 1_000,
                               output_description: 'no_send locks everything'
                             }],
                             options: { no_send: true }
                           })

      # Attempting to auto-fund at this point must fail — the pending change
      # output is not selectable by design.
      expect do
        wallet.create_action({
                               description: 'concurrent auto fund attempt test',
                               auto_fund: true,
                               outputs: [{
                                 locking_script: recipient_lock_hex,
                                 satoshis: 100,
                                 output_description: 'attempt to spend pending change'
                               }]
                             })
      end.to raise_error(BSV::Wallet::InsufficientFundsError)
    end
  end
end
end # STORE_FACTORIES.each
