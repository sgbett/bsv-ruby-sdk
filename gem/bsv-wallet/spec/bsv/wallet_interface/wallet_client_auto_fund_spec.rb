# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'securerandom'

RSpec.describe 'WalletClient auto-fund mode' do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:storage)     { BSV::Wallet::MemoryStore.new }
  let(:wallet)      { BSV::Wallet::WalletClient.new(private_key, storage: storage) }
  let(:description) { 'auto fund test action' }

  # A P2PKH locking script to an arbitrary external recipient.
  let(:recipient_key)      { BSV::Primitives::PrivateKey.generate }
  let(:recipient_lock_hex) { BSV::Script::Script.p2pkh_lock(recipient_key.public_key.hash160).to_hex }

  # Helper: creates a real spendable UTXO in storage, using the wallet's key
  # deriver to produce a genuine P2PKH locking script. Stores the source
  # transaction so wire_source_from_storage can resolve it.
  def seed_utxo(satoshis:, basket: 'default')
    prefix  = SecureRandom.hex(16)
    suffix  = SecureRandom.hex(16)
    key_id  = "#{prefix} #{suffix}"
    identity_key = wallet.key_deriver.identity_key

    pub_key = wallet.key_deriver.derive_public_key(
      BSV::Wallet::ChangeGenerator::BRC29_PROTOCOL_ID,
      key_id,
      identity_key,
      for_self: true
    )
    locking_script = BSV::Script::Script.p2pkh_lock(pub_key.hash160)

    # Build a fake source transaction that carries this output.
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
                           basket: basket,
                           tags: [],
                           derivation_prefix: prefix,
                           derivation_suffix: suffix,
                           sender_identity_key: identity_key,
                           state: :spendable,
                           source_tx_hex: source_tx.to_hex
                         })

    { outpoint: outpoint, satoshis: satoshis, prefix: prefix, suffix: suffix }
  end

  # -------------------------------------------------------------------------
  # End-to-end: single UTXO, single output
  # -------------------------------------------------------------------------
  describe 'end-to-end: single UTXO covering a single output' do
    before { seed_utxo(satoshis: 10_000) }

    let(:result) do
      wallet.create_action({
                             description: description,
                             auto_fund: true,
                             outputs: [{
                               locking_script: recipient_lock_hex,
                               satoshis: 1_000,
                               output_description: 'recipient payment'
                             }]
                           })
    end

    it 'returns a 64-character hex txid' do
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'returns :tx as a byte array' do
      expect(result[:tx]).to be_a(Array)
      expect(result[:tx]).to all(be_a(Integer))
    end

    it 'does not return :signable_transaction' do
      expect(result).not_to have_key(:signable_transaction)
    end

    it 'marks the input UTXO as :spent' do
      result
      spendable = storage.find_spendable_outputs(basket: 'default')
      # The original 10 000-sat UTXO should be gone; only change may remain.
      expect(spendable.none? { |o| o[:satoshis] == 10_000 }).to be true
    end

    it 'stores the signed transaction in storage' do
      txid = result[:txid]
      expect(storage.find_transaction(txid)).to be_a(String)
    end

    it 'stores a change output as :spendable in the default basket' do
      result
      # Change outputs are stored in the default basket so they are selectable
      # by subsequent auto-fund calls.
      change = storage.find_spendable_outputs(basket: 'default').select { |o| o[:derivation_prefix] }
      expect(change).not_to be_empty
      expect(change.first[:satoshis]).to be_positive
      expect(change.first[:basket]).to eq('default')
    end

    it 'stores change with derivation metadata' do
      result
      change = storage.find_spendable_outputs.select { |o| o[:derivation_prefix] }
      expect(change.first[:derivation_prefix]).to be_a(String)
      expect(change.first[:derivation_suffix]).to be_a(String)
      expect(change.first[:sender_identity_key]).to eq(wallet.key_deriver.identity_key)
    end

    it 'produces a valid signed transaction (all inputs have unlocking scripts)' do
      txid = result[:txid]
      tx_hex = storage.find_transaction(txid)
      tx = BSV::Transaction::Transaction.from_hex(tx_hex)
      tx.inputs.each do |inp|
        expect(inp.unlocking_script).not_to be_nil
        expect(inp.unlocking_script.to_binary.bytesize).to be_positive
      end
    end
  end

  # -------------------------------------------------------------------------
  # Multiple UTXOs needed to cover the target
  # -------------------------------------------------------------------------
  describe 'multiple UTXOs accumulated to cover the target' do
    before do
      seed_utxo(satoshis: 3_000)
      seed_utxo(satoshis: 4_000)
    end

    let(:result) do
      wallet.create_action({
                             description: description,
                             auto_fund: true,
                             outputs: [{
                               locking_script: recipient_lock_hex,
                               satoshis: 6_000,
                               output_description: 'large payment'
                             }]
                           })
    end

    it 'succeeds and returns a txid' do
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'uses both UTXOs (transaction has 2 inputs)' do
      txid = result[:txid]
      tx = BSV::Transaction::Transaction.from_hex(storage.find_transaction(txid))
      expect(tx.inputs.size).to eq(2)
    end

    it 'marks both input UTXOs as spent' do
      result
      spendable = storage.find_spendable_outputs(basket: 'default')
      expect(spendable.none? { |o| [3_000, 4_000].include?(o[:satoshis]) }).to be true
    end
  end

  # -------------------------------------------------------------------------
  # Insufficient funds
  # -------------------------------------------------------------------------
  describe 'insufficient funds' do
    before { seed_utxo(satoshis: 100) }

    it 'raises InsufficientFundsError when available funds cannot cover the target' do
      expect do
        wallet.create_action({
                               description: description,
                               auto_fund: true,
                               outputs: [{
                                 locking_script: recipient_lock_hex,
                                 satoshis: 1_000,
                                 output_description: 'expensive output'
                               }]
                             })
      end.to raise_error(BSV::Wallet::InsufficientFundsError)
    end

    it 'does not modify output states when it raises' do
      begin
        wallet.create_action({
                               description: description,
                               auto_fund: true,
                               outputs: [{
                                 locking_script: recipient_lock_hex,
                                 satoshis: 1_000,
                                 output_description: 'expensive output'
                               }]
                             })
      rescue BSV::Wallet::InsufficientFundsError
        nil
      end

      spendable = storage.find_spendable_outputs(basket: 'default')
      expect(spendable.size).to eq(1)
      expect(spendable.first[:satoshis]).to eq(100)
    end
  end

  # -------------------------------------------------------------------------
  # State transitions: after create_action, only change is spendable
  # -------------------------------------------------------------------------
  describe 'state transitions' do
    before { seed_utxo(satoshis: 10_000) }

    it 'replaces the input UTXO with change in find_spendable_outputs' do
      wallet.create_action({
                             description: description,
                             auto_fund: true,
                             outputs: [{
                               locking_script: recipient_lock_hex,
                               satoshis: 1_000,
                               output_description: 'payment'
                             }]
                           })

      # Change outputs are stored in the default basket.
      spendable = storage.find_spendable_outputs(basket: 'default')
      # The original 10 000-sat UTXO must not appear; change output should.
      sats_values = spendable.map { |o| o[:satoshis] }
      expect(sats_values).not_to include(10_000)
      expect(spendable.size).to be >= 1
    end
  end

  # -------------------------------------------------------------------------
  # Regression: explicit inputs still work (existing behaviour unchanged)
  # -------------------------------------------------------------------------
  describe 'regression: explicit inputs path is unchanged' do
    def build_source_beef(satoshis: 5_000)
      source_tx = BSV::Transaction::Transaction.new
      source_tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: satoshis,
          locking_script: BSV::Script::Script.p2pkh_lock(private_key.public_key.hash160)
        )
      )
      [source_tx, source_tx.to_beef.unpack('C*')]
    end

    it 'creates a transaction with explicit inputs and outputs' do
      source_tx, beef_bytes = build_source_beef
      source_txid = source_tx.txid_hex

      result = wallet.create_action({
                                      description: 'explicit inputs regression check',
                                      input_beef: beef_bytes,
                                      inputs: [{
                                        outpoint: "#{source_txid}.0",
                                        unlocking_script: '00',
                                        input_description: 'explicit spend input'
                                      }],
                                      outputs: [{
                                        locking_script: recipient_lock_hex,
                                        satoshis: 1_000,
                                        output_description: 'explicit output'
                                      }]
                                    })

      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
      expect(result[:tx]).to be_a(Array)
    end

    it 'outputs-only without auto_fund: true creates a no-input transaction' do
      result = wallet.create_action({
                                      description: 'output only no auto fund',
                                      outputs: [{
                                        locking_script: recipient_lock_hex,
                                        satoshis: 1_000,
                                        output_description: 'standalone output'
                                      }]
                                    })

      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
      tx = BSV::Transaction::Transaction.from_hex(storage.find_transaction(result[:txid]))
      expect(tx.inputs.size).to eq(0)
    end
  end

  # -------------------------------------------------------------------------
  # Chain spending: change output from first action is spendable in second
  # -------------------------------------------------------------------------
  describe 'chain spending: change from first action funds the second' do
    before { seed_utxo(satoshis: 50_000) }

    it 'successfully spends change from a previous auto-funded transaction' do
      # First action: produces change in the default basket.
      result1 = wallet.create_action({
                                       description: 'first chain spending action',
                                       auto_fund: true,
                                       outputs: [{
                                         locking_script: recipient_lock_hex,
                                         satoshis: 1_000,
                                         output_description: 'first payment'
                                       }]
                                     })
      expect(result1[:txid]).to match(/\A[0-9a-f]{64}\z/)

      # At this point the original UTXO is spent; change is a spendable output
      # in the default basket with BRC-29 derivation metadata.
      change = storage.find_spendable_outputs(basket: 'default').select { |o| o[:derivation_prefix] }
      expect(change).not_to be_empty

      # Second action: auto-funded from the change.
      result2 = wallet.create_action({
                                       description: 'second chain spending action',
                                       auto_fund: true,
                                       outputs: [{
                                         locking_script: recipient_lock_hex,
                                         satoshis: 500,
                                         output_description: 'second payment'
                                       }]
                                     })

      expect(result2[:txid]).to match(/\A[0-9a-f]{64}\z/)
      expect(result2[:txid]).not_to eq(result1[:txid])
    end
  end

  # -------------------------------------------------------------------------
  # No UTXOs in storage at all
  # -------------------------------------------------------------------------
  describe 'when no UTXOs exist in storage' do
    it 'raises InsufficientFundsError immediately' do
      expect do
        wallet.create_action({
                               description: description,
                               auto_fund: true,
                               outputs: [{
                                 locking_script: recipient_lock_hex,
                                 satoshis: 1_000,
                                 output_description: 'any output'
                               }]
                             })
      end.to raise_error(BSV::Wallet::InsufficientFundsError)
    end
  end

  # -------------------------------------------------------------------------
  # Basket isolation: auto-fund must never touch custom baskets
  # -------------------------------------------------------------------------
  describe 'basket isolation' do
    let(:action_opts) do
      {
        description: description,
        auto_fund: true,
        outputs: [{
          locking_script: recipient_lock_hex,
          satoshis: 1_000,
          output_description: 'payment'
        }]
      }
    end

    it 'does not consume outputs from custom baskets' do
      tokens_utxo = seed_utxo(satoshis: 10_000, basket: 'tokens')
      seed_utxo(satoshis: 10_000, basket: 'default')

      wallet.create_action(action_opts)

      # The 'tokens' UTXO must remain untouched.
      tokens_remaining = storage.find_spendable_outputs(basket: 'tokens')
      expect(tokens_remaining.any? { |o| o[:outpoint] == tokens_utxo[:outpoint] }).to be true
    end

    it 'raises InsufficientFundsError when only a custom basket has funds' do
      seed_utxo(satoshis: 10_000, basket: 'tokens')

      expect do
        wallet.create_action(action_opts)
      end.to raise_error(BSV::Wallet::InsufficientFundsError)

      # The 'tokens' UTXO must remain untouched.
      expect(storage.find_spendable_outputs(basket: 'tokens').size).to eq(1)
    end

    it 'stores change output in the default basket' do
      seed_utxo(satoshis: 10_000, basket: 'default')

      wallet.create_action(action_opts)

      change = storage.find_spendable_outputs(basket: 'default').select { |o| o[:derivation_prefix] }
      expect(change).not_to be_empty
      expect(change.first[:basket]).to eq('default')
      expect(change.first[:satoshis]).to be_positive
    end

    it 'change is usable by subsequent auto-fund' do
      seed_utxo(satoshis: 50_000, basket: 'default')

      # First action consumes the seeded UTXO and produces change in 'default'.
      result1 = wallet.create_action(action_opts)
      expect(result1[:txid]).to match(/\A[0-9a-f]{64}\z/)

      # Second action must be able to spend the change output.
      result2 = wallet.create_action({
                                       description: 'second action',
                                       auto_fund: true,
                                       outputs: [{
                                         locking_script: recipient_lock_hex,
                                         satoshis: 500,
                                         output_description: 'second payment'
                                       }]
                                     })
      expect(result2[:txid]).to match(/\A[0-9a-f]{64}\z/)
      expect(result2[:txid]).not_to eq(result1[:txid])
    end

    it 'pool size counts only default basket outputs' do
      # Seed 3 outputs in 'default' and 2 in 'tokens'.
      3.times { seed_utxo(satoshis: 5_000, basket: 'default') }
      2.times { seed_utxo(satoshis: 5_000, basket: 'tokens') }

      # Set change params with a pool target larger than the default basket count.
      wallet.set_wallet_change_params(count: 6, satoshis: 1_000)

      wallet.create_action(action_opts)

      # Because pool_size reflects only the 3 default-basket UTXOs (below the
      # target of 6), the change generator should produce multiple change outputs.
      change_outputs = storage.find_spendable_outputs(basket: 'default').select { |o| o[:derivation_prefix] }
      expect(change_outputs.size).to be > 1
    end
  end

  # -------------------------------------------------------------------------
  # Broadcaster integration: broadcast-before-promote semantics
  # -------------------------------------------------------------------------
  describe 'with broadcaster configured' do
    let(:broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles
    let(:wallet) { BSV::Wallet::WalletClient.new(private_key, storage: storage, broadcaster: broadcaster) }

    let(:action_opts) do
      {
        description: 'broadcaster integration test',
        auto_fund: true,
        outputs: [{
          locking_script: recipient_lock_hex,
          satoshis: 1_000,
          output_description: 'payment'
        }]
      }
    end

    before { seed_utxo(satoshis: 10_000) }

    describe 'successful broadcast' do
      let(:broadcast_response) do
        BSV::Network::BroadcastResponse.new(txid: 'abc', tx_status: 'SEEN_ON_NETWORK')
      end

      before { allow(broadcaster).to receive(:broadcast).and_return(broadcast_response) }

      it 'returns :txid and :tx in the result' do
        result = wallet.create_action(action_opts)
        expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
        expect(result[:tx]).to be_a(Array)
      end

      it 'includes :broadcast_result in the response' do
        result = wallet.create_action(action_opts)
        expect(result[:broadcast_result]).to eq(broadcast_response)
      end

      it 'promotes input UTXOs to :spent' do
        wallet.create_action(action_opts)
        spendable = storage.find_spendable_outputs(basket: 'default')
        expect(spendable.none? { |o| o[:satoshis] == 10_000 }).to be true
      end

      it 'promotes change outputs to :spendable' do
        wallet.create_action(action_opts)
        change = storage.find_spendable_outputs(basket: 'default').select { |o| o[:derivation_prefix] }
        expect(change).not_to be_empty
      end

      it 'marks the action as completed' do
        wallet.create_action(action_opts)
        actions = storage.find_actions({ limit: 10, offset: 0 })
        expect(actions.first[:status]).to eq('completed')
      end
    end

    describe 'failed broadcast (BroadcastError)' do
      before do
        allow(broadcaster).to receive(:broadcast).and_raise(
          BSV::Network::BroadcastError.new('double spend attempted')
        )
      end

      it 'does not raise — returns a result hash with :broadcast_error' do
        result = wallet.create_action(action_opts)
        expect(result[:broadcast_error]).to eq('double spend attempted')
      end

      it 'still returns :txid and :tx' do
        result = wallet.create_action(action_opts)
        expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
        expect(result[:tx]).to be_a(Array)
      end

      it 'releases input UTXOs back to :spendable' do
        wallet.create_action(action_opts)
        spendable = storage.find_spendable_outputs(basket: 'default')
        expect(spendable.any? { |o| o[:satoshis] == 10_000 }).to be true
      end

      it 'deletes phantom change outputs' do
        # Only the original seeded UTXO should remain; rollback must not leave
        # extra outputs in storage.
        wallet.create_action(action_opts)
        spendable = storage.find_spendable_outputs(basket: 'default')
        expect(spendable.size).to eq(1)
        expect(spendable.first[:satoshis]).to eq(10_000)
      end

      it 'marks the action as failed' do
        result = wallet.create_action(action_opts)
        all_actions = storage.find_actions({ limit: 100, offset: 0 })
        action = all_actions.find { |a| a[:txid] == result[:txid] }
        expect(action[:status]).to eq('failed')
      end
    end

    describe 'failed broadcast (network error / StandardError)' do
      before do
        allow(broadcaster).to receive(:broadcast).and_raise(RuntimeError, 'connection timeout')
      end

      it 'returns :broadcast_error without raising' do
        result = wallet.create_action(action_opts)
        expect(result[:broadcast_error]).to eq('connection timeout')
      end

      it 'releases input UTXOs back to :spendable' do
        wallet.create_action(action_opts)
        spendable = storage.find_spendable_outputs(basket: 'default')
        expect(spendable.any? { |o| o[:satoshis] == 10_000 }).to be true
      end

      it 'deletes phantom change outputs' do
        # Only the original seeded UTXO should remain after rollback.
        wallet.create_action(action_opts)
        spendable = storage.find_spendable_outputs(basket: 'default')
        expect(spendable.size).to eq(1)
        expect(spendable.first[:satoshis]).to eq(10_000)
      end

      it 'marks the action as failed' do
        result = wallet.create_action(action_opts)
        all_actions = storage.find_actions({ limit: 100, offset: 0 })
        action = all_actions.find { |a| a[:txid] == result[:txid] }
        expect(action[:status]).to eq('failed')
      end
    end

    describe 'rollback does not affect other outputs or actions' do
      before { seed_utxo(satoshis: 50_000) }

      it 'leaves unrelated UTXOs intact after rollback' do
        # First action succeeds (we have two seeded UTXOs: 10_000 and 50_000).
        good_broadcaster = double('good_broadcaster') # rubocop:disable RSpec/VerifiedDoubles
        good_response = BSV::Network::BroadcastResponse.new(txid: 'ok', tx_status: 'SEEN_ON_NETWORK')
        allow(good_broadcaster).to receive(:broadcast).and_return(good_response)

        good_wallet = BSV::Wallet::WalletClient.new(private_key, storage: storage, broadcaster: good_broadcaster)
        good_wallet.create_action({
                                    description: 'first succeeds',
                                    auto_fund: true,
                                    outputs: [{
                                      locking_script: recipient_lock_hex,
                                      satoshis: 1_000,
                                      output_description: 'good payment'
                                    }]
                                  })

        # Remaining spendable UTXOs after the first action.
        before_count = storage.find_spendable_outputs(basket: 'default').size

        # Second action fails broadcast.
        allow(broadcaster).to receive(:broadcast).and_raise(
          BSV::Network::BroadcastError.new('rejected')
        )
        wallet.create_action(action_opts)

        # The spendable pool should not shrink permanently.
        after_count = storage.find_spendable_outputs(basket: 'default').size
        expect(after_count).to eq(before_count)
      end
    end
  end

  # -------------------------------------------------------------------------
  # Without broadcaster: backwards-compatible (no-broadcaster) behaviour
  # -------------------------------------------------------------------------
  describe 'without broadcaster (backwards-compatible)' do
    before { seed_utxo(satoshis: 10_000) }

    it 'promotes inputs to :spent immediately' do
      wallet.create_action({
                             description: 'no broadcaster test',
                             auto_fund: true,
                             outputs: [{
                               locking_script: recipient_lock_hex,
                               satoshis: 1_000,
                               output_description: 'payment'
                             }]
                           })
      spendable = storage.find_spendable_outputs(basket: 'default')
      expect(spendable.none? { |o| o[:satoshis] == 10_000 }).to be true
    end

    it 'promotes change to :spendable immediately' do
      wallet.create_action({
                             description: 'no broadcaster change test',
                             auto_fund: true,
                             outputs: [{
                               locking_script: recipient_lock_hex,
                               satoshis: 1_000,
                               output_description: 'payment'
                             }]
                           })
      change = storage.find_spendable_outputs(basket: 'default').select { |o| o[:derivation_prefix] }
      expect(change).not_to be_empty
    end

    it 'stores the action as completed' do
      result = wallet.create_action({
                                      description: 'no broadcaster action status test',
                                      auto_fund: true,
                                      outputs: [{
                                        locking_script: recipient_lock_hex,
                                        satoshis: 1_000,
                                        output_description: 'payment'
                                      }]
                                    })
      all_actions = storage.find_actions({ limit: 100, offset: 0 })
      action = all_actions.find { |a| a[:txid] == result[:txid] }
      expect(action[:status]).to eq('completed')
    end

    it 'does not include :broadcast_result or :broadcast_error in the result' do
      result = wallet.create_action({
                                      description: 'no broadcaster result shape test',
                                      auto_fund: true,
                                      outputs: [{
                                        locking_script: recipient_lock_hex,
                                        satoshis: 1_000,
                                        output_description: 'payment'
                                      }]
                                    })
      expect(result).not_to have_key(:broadcast_result)
      expect(result).not_to have_key(:broadcast_error)
    end
  end
end
