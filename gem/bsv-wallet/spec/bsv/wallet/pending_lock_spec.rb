# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'securerandom'
require 'time'

STORE_FACTORIES.each do |store_label, store_factory|
RSpec.describe "Pending UTXO locking and double-spend prevention (#{store_label})" do
  let(:store) { store_factory.call }

  # Seeds a spendable output into the store.
  def seed_output(outpoint: 'tx0:0', satoshis: 1000, basket: 'default')
    store.store_output(
      outpoint: outpoint,
      satoshis: satoshis,
      basket: basket,
      state: :spendable
    )
  end

  # -----------------------------------------------------------------------
  # 1. Pending metadata
  # -----------------------------------------------------------------------
  describe 'marking an output as pending with a reference' do
    it 'sets :pending_since as an ISO 8601 UTC timestamp' do
      seed_output
      before = Time.now.utc
      store.update_output_state('tx0:0', :pending, pending_reference: 'action-123')
      after = Time.now.utc

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      raw = outputs.first[:pending_since]

      expect(raw).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)

      # iso8601 truncates to whole seconds, so allow a 1-second tolerance on
      # the lower bound to avoid spurious failures at sub-second boundaries.
      pending_since = Time.parse(raw)
      expect(pending_since).to be >= (before - 1)
      expect(pending_since).to be <= after
    end

    it 'stores the caller-supplied :pending_reference' do
      seed_output
      store.update_output_state('tx0:0', :pending, pending_reference: 'action-123')

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      expect(outputs.first[:pending_reference]).to eq('action-123')
    end
  end

  # -----------------------------------------------------------------------
  # 2. Pending outputs are excluded from find_spendable_outputs
  # -----------------------------------------------------------------------
  describe '#find_spendable_outputs' do
    it 'excludes outputs in :pending state' do
      seed_output(outpoint: 'tx0:0', satoshis: 500)
      seed_output(outpoint: 'tx1:0', satoshis: 300)
      store.update_output_state('tx0:0', :pending, pending_reference: 'ref-xyz')

      results = store.find_spendable_outputs
      expect(results.map { |o| o[:outpoint] }).to eq(['tx1:0'])
    end
  end

  # -----------------------------------------------------------------------
  # 3. Stale lock recovery
  # -----------------------------------------------------------------------
  describe '#release_stale_pending!' do
    it 'releases a lock that is older than the timeout' do
      seed_output
      store.update_output_state('tx0:0', :pending, pending_reference: 'stale-ref')

      # Backdating the timestamp to simulate a 6-minute-old lock.
      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      outputs.first[:pending_since] = (Time.now.utc - 360).iso8601

      released = store.release_stale_pending!(timeout: 300)
      expect(released).to eq(1)

      spendable = store.find_spendable_outputs
      expect(spendable.map { |o| o[:outpoint] }).to include('tx0:0')
    end

    it 'clears :pending_since and :pending_reference after release' do
      seed_output
      store.update_output_state('tx0:0', :pending, pending_reference: 'stale-ref')

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      outputs.first[:pending_since] = (Time.now.utc - 360).iso8601

      store.release_stale_pending!(timeout: 300)

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      expect(outputs.first).not_to have_key(:pending_since)
      expect(outputs.first).not_to have_key(:pending_reference)
    end

    # -----------------------------------------------------------------------
    # 4. Non-stale locks are preserved
    # -----------------------------------------------------------------------
    it 'preserves a lock that is within the timeout window' do
      seed_output
      store.update_output_state('tx0:0', :pending, pending_reference: 'fresh-ref')

      # The lock was set just now — 60 seconds old is well within 300 s.
      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      outputs.first[:pending_since] = (Time.now.utc - 60).iso8601

      released = store.release_stale_pending!(timeout: 300)
      expect(released).to eq(0)

      spendable = store.find_spendable_outputs
      expect(spendable).to be_empty
    end
  end

  # -----------------------------------------------------------------------
  # 5. Abort releases UTXOs in the auto-fund flow
  # -----------------------------------------------------------------------
  describe 'abort_action releases pending UTXOs' do
    let(:private_key) { BSV::Primitives::PrivateKey.generate }
    let(:storage)     { store_factory.call }
    # Post-HLR #455: broadcaster required; create_action raises without one.
    let(:broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles
    let(:wallet) do
      BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster)
    end

    before do
      allow(broadcaster).to receive(:broadcast).and_return(
        BSV::Network::BroadcastResponse.new(txid: 'stub', tx_status: 'SEEN_ON_NETWORK')
      )
    end

    def seed_wallet_utxo(satoshis:)
      prefix = SecureRandom.hex(16)
      suffix = SecureRandom.hex(16)
      key_id = "#{prefix} #{suffix}"
      identity_key = wallet.key_deriver.identity_key

      pub_key = wallet.key_deriver.derive_public_key(
        BSV::Wallet::ChangeGenerator::BRC29_PROTOCOL_ID,
        key_id,
        identity_key,
        for_self: true
      )
      locking_script = BSV::Script::Script.p2pkh_lock(pub_key.hash160)

      source_tx = BSV::Transaction::Transaction.new
      source_tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: satoshis,
          locking_script: locking_script
        )
      )
      txid = source_tx.txid_hex
      storage.store_transaction(txid, source_tx.to_hex)

      outpoint = "#{txid}.0"
      storage.store_output({
                             outpoint: outpoint,
                             satoshis: satoshis,
                             locking_script: locking_script.to_hex,
                             basket: 'default',
                             tags: [],
                             derivation_prefix: prefix,
                             derivation_suffix: suffix,
                             sender_identity_key: identity_key,
                             state: :spendable,
                             source_tx_hex: source_tx.to_hex
                           })
      outpoint
    end

    it 'marks UTXOs pending during auto-fund and releases them if the build fails' do
      outpoint = seed_wallet_utxo(satoshis: 5000)

      # Corrupt the storage so signing cannot complete, triggering the rescue.
      allow(storage).to receive(:store_transaction).and_raise(RuntimeError, 'simulated failure')

      recipient_key  = BSV::Primitives::PrivateKey.generate
      recipient_lock = BSV::Script::Script.p2pkh_lock(recipient_key.public_key.hash160).to_hex

      expect do
        wallet.create_action({
                               description: 'will fail',
                               auto_fund: true,
                               outputs: [{ locking_script: recipient_lock, satoshis: 500, output_description: 'Payment to recipient' }]
                             })
      end.to raise_error(RuntimeError, 'simulated failure')

      # The UTXO must have been returned to :spendable.
      spendable = storage.find_spendable_outputs
      expect(spendable.map { |o| o[:outpoint] }).to include(outpoint)
    end
  end

  # -----------------------------------------------------------------------
  # 6. Thread safety — only one thread should succeed in marking pending
  # -----------------------------------------------------------------------
  describe 'thread safety' do
    it 'allows only one thread to lock a single UTXO as pending' do
      seed_output(outpoint: 'shared:0', satoshis: 1000)

      results = Array.new(2)
      barrier = Queue.new

      threads = 2.times.map do |i|
        Thread.new do
          barrier.pop # wait until both threads are ready

          begin
            spendable = store.find_spendable_outputs
            if spendable.any? { |o| o[:outpoint] == 'shared:0' }
              store.update_output_state('shared:0', :pending, pending_reference: "thread-#{i}")
              results[i] = :locked
            else
              results[i] = :missed
            end
          rescue BSV::Wallet::WalletError
            results[i] = :error
          end
        end
      end

      # Release both threads simultaneously.
      2.times { barrier.push(:go) }
      threads.each(&:join)

      # With mutex protection, exactly one thread should have locked the UTXO
      # and the UTXO should now be in :pending state (not double-spent).
      locked_count = results.count(:locked)
      expect(locked_count).to eq(1), "Expected exactly 1 thread to lock the UTXO; got #{locked_count} (results: #{results.inspect})"

      spendable_after = store.find_spendable_outputs
      expect(spendable_after.map { |o| o[:outpoint] }).not_to include('shared:0')
    end
  end

  # -----------------------------------------------------------------------
  # 7. Full lifecycle: spendable → pending → spent
  # -----------------------------------------------------------------------
  describe 'full state lifecycle' do
    it 'transitions correctly through spendable → pending → spent' do
      seed_output

      # Step 1: spendable
      expect(store.find_spendable_outputs.map { |o| o[:outpoint] }).to include('tx0:0')

      # Step 2: pending (with metadata)
      store.update_output_state('tx0:0', :pending, pending_reference: 'lifecycle-ref')
      spendable_after_lock = store.find_spendable_outputs
      expect(spendable_after_lock.map { |o| o[:outpoint] }).not_to include('tx0:0')

      pending_output = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 }).first
      expect(pending_output[:state]).to eq(:pending)
      expect(pending_output[:pending_reference]).to eq('lifecycle-ref')
      expect(pending_output[:pending_since]).not_to be_nil

      # Step 3: spent (metadata cleared)
      store.update_output_state('tx0:0', :spent)
      spent_output = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 }).first
      expect(spent_output[:state]).to eq(:spent)
      expect(spent_output).not_to have_key(:pending_since)
      expect(spent_output).not_to have_key(:pending_reference)
    end
  end

  # -----------------------------------------------------------------------
  # 8. Metadata is cleared when transitioning from pending to spent
  # -----------------------------------------------------------------------
  describe 'clearing metadata on transition to spent' do
    it 'removes :pending_since and :pending_reference when marking spent' do
      seed_output
      store.update_output_state('tx0:0', :pending, pending_reference: 'to-be-spent')

      store.update_output_state('tx0:0', :spent)

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      output = outputs.first
      expect(output[:state]).to eq(:spent)
      expect(output).not_to have_key(:pending_since)
      expect(output).not_to have_key(:pending_reference)
    end
  end

  # -----------------------------------------------------------------------
  # 9. no_send locks are exempt from stale recovery
  # -----------------------------------------------------------------------
  describe 'no_send lock exemption' do
    it 'does not release a stale no_send lock during release_stale_pending!' do
      seed_output
      store.update_output_state('tx0:0', :pending, pending_reference: 'no-send-ref', no_send: true)

      # Backdate the lock to well beyond the timeout.
      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      outputs.first[:pending_since] = (Time.now.utc - 600).iso8601

      released = store.release_stale_pending!(timeout: 300)
      expect(released).to eq(0)

      spendable = store.find_spendable_outputs
      expect(spendable).to be_empty
    end

    it 'stores the :no_send flag on the output when marking pending with no_send: true' do
      seed_output
      store.update_output_state('tx0:0', :pending, pending_reference: 'ns-ref', no_send: true)

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      expect(outputs.first[:no_send]).to be true
    end

    it 'clears the :no_send flag when transitioning away from pending' do
      seed_output
      store.update_output_state('tx0:0', :pending, pending_reference: 'ns-ref', no_send: true)
      store.update_output_state('tx0:0', :spendable)

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      expect(outputs.first).not_to have_key(:no_send)
    end

    it 'does not set :no_send on an ordinary pending lock' do
      seed_output
      store.update_output_state('tx0:0', :pending, pending_reference: 'ordinary-ref')

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      expect(outputs.first).not_to have_key(:no_send)
    end
  end
end
end # STORE_FACTORIES.each
