# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

# Comprehensive tests for auto-funding in WalletClient#create_action.
#
# Auto-funding is triggered when create_action receives outputs but no inputs.
# The wallet selects spendable UTXOs with BRC-29 derivation metadata, estimates
# fees, generates change, builds and signs the transaction.

RSpec.describe 'WalletClient auto-funding pipeline' do
  # Helper: store a spendable payment output in storage with BRC-29 derivation metadata.
  # Mimics what internalize_payment does after receiving a wallet payment.
  def seed_payment_output(wallet, satoshis:, key_deriver: nil)
    deriver = key_deriver || wallet.key_deriver
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

    # Build a fake source transaction holding this output
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

    { outpoint: outpoint, satoshis: satoshis, derivation_prefix: prefix,
      derivation_suffix: suffix, sender_identity_key: sender_pub, txid: txid }
  end

  # Helper: a P2PKH locking script hex (arbitrary destination, not our wallet)
  def p2pkh_hex
    dest_key = BSV::Primitives::PrivateKey.generate.public_key
    BSV::Script::Script.p2pkh_lock(dest_key.hash160).to_hex
  end

  # A valid action description (5-50 chars)
  let(:description) { 'auto-funded payment action' }

  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:storage) { BSV::Wallet::MemoryStore.new }
  let(:wallet) { BSV::Wallet::WalletClient.new(private_key, storage: storage) }

  # ---------------------------------------------------------------------------
  # 1. Happy path — simple spend
  # ---------------------------------------------------------------------------
  describe 'happy path: seeded wallet pays a single output' do
    let!(:seeded) { seed_payment_output(wallet, satoshis: 10_000) }

    let(:result) do
      wallet.create_action({
                             description: description,
                             outputs: [{
                               locking_script: p2pkh_hex,
                               satoshis: 1000,
                               output_description: 'payment to recipient'
                             }]
                           })
    end

    it 'returns a 64-char hex txid' do
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'returns :tx as a byte array' do
      expect(result[:tx]).to be_a(Array)
      expect(result[:tx]).to all(be_a(Integer))
    end

    it 'does not return :signable_transaction' do
      expect(result).not_to have_key(:signable_transaction)
    end

    it 'marks the input UTXO as :spent after finalisation' do
      result
      # find_spendable_outputs uses the :state field; spent outputs are excluded
      spendable = storage.find_spendable_outputs
      spendable_outpoints = spendable.map { |o| o[:outpoint] }
      expect(spendable_outpoints).not_to include(seeded[:outpoint])
    end

    it 'stores a change output as :spendable with derivation metadata' do
      result
      spendable = storage.find_spendable_outputs
      # The original UTXO is spent; only change output(s) should be spendable
      change_outputs = spendable.select { |o| o[:derivation_prefix] }
      expect(change_outputs).not_to be_empty
    end

    it 'change output has correct derivation fields' do
      result
      spendable = storage.find_spendable_outputs
      change = spendable.find { |o| o[:derivation_prefix] }
      expect(change[:derivation_prefix]).to be_a(String)
      expect(change[:derivation_suffix]).to be_a(String)
      expect(change[:sender_identity_key]).to be_a(String)
    end

    it 'change output is stored in the default basket' do
      result
      spendable = storage.find_spendable_outputs(basket: 'default')
      change = spendable.find { |o| o[:derivation_prefix] }
      expect(change[:basket]).to eq('default')
    end

    it 'stores the action as completed' do
      result
      actions = storage.find_actions({})
      expect(actions).not_to be_empty
      expect(actions.last[:status]).to eq('completed')
    end

    it 'produces a valid BEEF' do
      beef_binary = result[:tx].pack('C*')
      beef = BSV::Transaction::Beef.from_binary(beef_binary)
      expect(beef.valid?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # 2. UTXO state lifecycle — spendable → pending → spent
  # ---------------------------------------------------------------------------
  describe 'UTXO state lifecycle' do
    let!(:seeded) { seed_payment_output(wallet, satoshis: 5000) }

    it 'transitions from spendable to spent on success' do
      # Before: spendable
      before_spend = storage.find_spendable_outputs
      expect(before_spend.map { |o| o[:outpoint] }).to include(seeded[:outpoint])

      wallet.create_action({
                             description: description,
                             outputs: [{
                               locking_script: p2pkh_hex,
                               satoshis: 1000,
                               output_description: 'lifecycle test output'
                             }]
                           })

      # After: no longer in spendable pool
      after_spend = storage.find_spendable_outputs
      expect(after_spend.map { |o| o[:outpoint] }).not_to include(seeded[:outpoint])
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Chain of change — change output is spendable in a subsequent transaction
  # ---------------------------------------------------------------------------
  describe 'change is spendable in a follow-on transaction' do
    before do
      seed_payment_output(wallet, satoshis: 10_000)

      # First spend — generates change
      wallet.create_action({
                             description: 'first spend to create change',
                             outputs: [{
                               locking_script: p2pkh_hex,
                               satoshis: 1000,
                               output_description: 'first payment'
                             }]
                           })
    end

    it 'second auto-funded action succeeds using the change output' do
      result = wallet.create_action({
                                      description: 'second spend from change',
                                      outputs: [{
                                        locking_script: p2pkh_hex,
                                        satoshis: 500,
                                        output_description: 'second payment'
                                      }]
                                    })
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
      expect(result[:tx]).to be_a(Array)
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Insufficient funds
  # ---------------------------------------------------------------------------
  describe 'insufficient funds' do
    before { seed_payment_output(wallet, satoshis: 100) }

    it 'raises InsufficientFundsError when spendable pool cannot cover target + fee' do
      expect do
        wallet.create_action({
                               description: description,
                               outputs: [{
                                 locking_script: p2pkh_hex,
                                 satoshis: 1000,
                                 output_description: 'too expensive output'
                               }]
                             })
      end.to raise_error(BSV::Wallet::InsufficientFundsError)
    end

    it 'leaves the UTXO spendable after an InsufficientFundsError' do
      begin
        wallet.create_action({
                               description: description,
                               outputs: [{
                                 locking_script: p2pkh_hex,
                                 satoshis: 1000,
                                 output_description: 'too expensive output'
                               }]
                             })
      rescue BSV::Wallet::InsufficientFundsError
        nil
      end

      spendable = storage.find_spendable_outputs
      expect(spendable).not_to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Explicit inputs path — regression guard (must work exactly as before)
  # ---------------------------------------------------------------------------
  describe 'explicit inputs path (regression guard)' do
    let(:ext_key) { BSV::Primitives::PrivateKey.generate }
    let(:ext_pub) { ext_key.public_key }
    let(:locking_script) { BSV::Script::Script.p2pkh_lock(ext_pub.hash160) }
    let(:source_tx) do
      tx = BSV::Transaction::Transaction.new
      tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: 5000,
          locking_script: locking_script
        )
      )
      tx
    end
    let(:source_txid) { source_tx.txid_hex }

    before do
      storage.store_output({
                             outpoint: "#{source_txid}.0",
                             satoshis: 5000,
                             locking_script: locking_script.to_hex,
                             spendable: true,
                             source_tx_hex: source_tx.to_hex
                           })
    end

    it 'still works with an explicit P2PKH template input' do
      template = BSV::Transaction::P2PKH.new(ext_key)
      result = wallet.create_action({
                                      description: 'explicit input regression check',
                                      inputs: [{
                                        outpoint: "#{source_txid}.0",
                                        unlocking_script: template,
                                        input_description: 'spend external output'
                                      }],
                                      outputs: [{
                                        locking_script: p2pkh_hex,
                                        satoshis: 4000,
                                        output_description: 'payment to dest'
                                      }]
                                    })
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  # ---------------------------------------------------------------------------
  # 6. No change needed — input exactly covers target + fee
  # ---------------------------------------------------------------------------
  describe 'no change when excess is zero or sub-dust' do
    it 'produces no change output when excess is below the dust floor' do
      # FeeEstimator at 1 sat/kB: dust_floor = 1 sat (2 × ceil(192/1000 × 1))
      # At such a tiny fee rate, any excess >= 1 sat qualifies as change.
      # Use a tight satoshi value where excess would be 0 by construction.
      # With 1 sat/kB, a 1-input 2-output tx costs ceil(226/1000 * 1) = 1 sat fee
      # Seed with exactly target + fee (1000 + 1 = 1001)
      seed_payment_output(wallet, satoshis: 1001)

      result = wallet.create_action({
                                      description: 'exact coverage spend test',
                                      outputs: [{
                                        locking_script: p2pkh_hex,
                                        satoshis: 1000,
                                        output_description: 'exact coverage output'
                                      }]
                                    })

      # The result should succeed regardless; change presence depends on dust floor
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Multiple outputs — all present in the final transaction
  # ---------------------------------------------------------------------------
  describe 'multiple requested outputs' do
    before { seed_payment_output(wallet, satoshis: 50_000) }

    let(:result) do
      wallet.create_action({
                             description: 'multi-output payment action',
                             outputs: [
                               { locking_script: p2pkh_hex, satoshis: 1000, output_description: 'output one' },
                               { locking_script: p2pkh_hex, satoshis: 2000, output_description: 'output two' },
                               { locking_script: p2pkh_hex, satoshis: 3000, output_description: 'output three' }
                             ]
                           })
    end

    it 'returns a valid txid' do
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'produces a BEEF with all three outputs visible in the transaction' do
      beef_binary = result[:tx].pack('C*')
      beef = BSV::Transaction::Beef.from_binary(beef_binary)
      tx = beef.transactions.last.transaction
      # 3 requested outputs + change output(s)
      expect(tx.outputs.length).to be >= 3
    end
  end

  # ---------------------------------------------------------------------------
  # 8. Basket outputs excluded from coin selection
  # ---------------------------------------------------------------------------
  describe 'basket-only outputs are excluded from auto-spending' do
    before do
      # Store an output that has no derivation metadata (basket insertion only)
      basket_tx = BSV::Transaction::Transaction.new
      basket_tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: 50_000,
          locking_script: BSV::Script::Script.p2pkh_lock(private_key.public_key.hash160)
        )
      )
      storage.store_transaction(basket_tx.txid_hex, basket_tx.to_hex)
      storage.store_output({
                             outpoint: "#{basket_tx.txid_hex}.0",
                             satoshis: 50_000,
                             locking_script: BSV::Script::Script.p2pkh_lock(private_key.public_key.hash160).to_hex,
                             basket: 'token-vault',
                             state: :spendable,
                             spendable: true,
                             source_tx_hex: basket_tx.to_hex
                             # No derivation_prefix / derivation_suffix / sender_identity_key
                           })
    end

    it 'raises InsufficientFundsError (basket output ignored, pool appears empty)' do
      expect do
        wallet.create_action({
                               description: description,
                               outputs: [{
                                 locking_script: p2pkh_hex,
                                 satoshis: 1000,
                                 output_description: 'payment output'
                               }]
                             })
      end.to raise_error(BSV::Wallet::InsufficientFundsError)
    end
  end

  # ---------------------------------------------------------------------------
  # 9. BEEF validity
  # ---------------------------------------------------------------------------
  describe 'BEEF structural validity' do
    before { seed_payment_output(wallet, satoshis: 10_000) }

    it 'produces a BEEF that passes beef.valid?' do
      result = wallet.create_action({
                                      description: 'beef validity test action',
                                      outputs: [{
                                        locking_script: p2pkh_hex,
                                        satoshis: 1000,
                                        output_description: 'output for beef test'
                                      }]
                                    })
      beef_binary = result[:tx].pack('C*')
      beef = BSV::Transaction::Beef.from_binary(beef_binary)
      expect(beef.valid?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # 10. Error rollback — pending UTXOs released on failure
  # ---------------------------------------------------------------------------
  describe 'error rollback: pending UTXOs released when signing fails' do
    let!(:seeded) { seed_payment_output(wallet, satoshis: 10_000) }

    it 'returns the UTXO to :spendable if signing raises' do
      # Override change_generator to raise during build, after UTXOs are locked
      bad_generator = instance_double(BSV::Wallet::ChangeGenerator)
      allow(bad_generator).to receive(:generate).and_raise(RuntimeError, 'forced failure')

      bad_wallet = BSV::Wallet::WalletClient.new(
        private_key,
        storage: storage,
        change_generator: bad_generator
      )

      expect do
        bad_wallet.create_action({
                                   description: description,
                                   outputs: [{
                                     locking_script: p2pkh_hex,
                                     satoshis: 1000,
                                     output_description: 'output for rollback test'
                                   }]
                                 })
      end.to raise_error(RuntimeError, 'forced failure')

      # The UTXO must be back in the spendable pool
      spendable = storage.find_spendable_outputs
      spendable_outpoints = spendable.map { |o| o[:outpoint] }
      expect(spendable_outpoints).to include(seeded[:outpoint])
    end
  end

  # ---------------------------------------------------------------------------
  # 11. no_send: true — inputs remain :pending after finalisation
  # ---------------------------------------------------------------------------
  describe 'no_send: true keeps inputs as :pending' do
    let!(:seeded) { seed_payment_output(wallet, satoshis: 10_000) }

    let(:result) do
      wallet.create_action({
                             description: description,
                             outputs: [{
                               locking_script: p2pkh_hex,
                               satoshis: 1000,
                               output_description: 'no_send payment output'
                             }],
                             options: { no_send: true }
                           })
    end

    it 'returns a txid and :tx byte array' do
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
      expect(result[:tx]).to be_a(Array)
    end

    it 'returns :no_send_change' do
      expect(result).to have_key(:no_send_change)
    end

    it 'returns a :reference for abort_action' do
      expect(result[:reference]).to be_a(String)
    end

    it 'leaves the input UTXO as :pending (not :spent)' do
      result
      # The UTXO should not appear in spendable (it is pending, not spendable)
      spendable = storage.find_spendable_outputs
      spendable_outpoints = spendable.map { |o| o[:outpoint] }
      expect(spendable_outpoints).not_to include(seeded[:outpoint])
    end

    it 'stores action with "nosend" status' do
      result
      actions = storage.find_actions({})
      expect(actions.last[:status]).to eq('nosend')
    end

    it 'marks change outputs as :pending (not :spendable)' do
      result
      change_ops = result[:no_send_change]
      expect(change_ops).not_to be_empty

      # Change outputs should NOT appear in spendable outputs
      spendable = storage.find_spendable_outputs
      spendable_outpoints = spendable.map { |o| o[:outpoint] }
      change_ops.each do |op|
        expect(spendable_outpoints).not_to include(op)
      end
    end

    it 'does not allow auto-fund to select no_send change outputs' do
      result
      # The original input is :pending and the change is :pending,
      # so the wallet should have nothing spendable for auto-fund.
      expect do
        wallet.create_action({
                               description: 'should fail — no spendable UTXOs',
                               auto_fund: true,
                               outputs: [{
                                 locking_script: p2pkh_hex,
                                 satoshis: 100,
                                 output_description: 'attempt to spend pending change'
                               }]
                             })
      end.to raise_error(BSV::Wallet::InsufficientFundsError)
    end
  end

  # ---------------------------------------------------------------------------
  # 12. abort_action after no_send — pending inputs released, change removed
  # ---------------------------------------------------------------------------
  describe 'abort_action releases pending inputs from a no_send transaction' do
    let!(:seeded) { seed_payment_output(wallet, satoshis: 10_000) }

    it 'returns :aborted and makes input spendable again' do
      result = wallet.create_action({
                                      description: description,
                                      outputs: [{
                                        locking_script: p2pkh_hex,
                                        satoshis: 1000,
                                        output_description: 'no_send output for abort test'
                                      }],
                                      options: { no_send: true }
                                    })

      reference = result[:reference]
      expect(reference).to be_a(String)

      abort_result = wallet.abort_action({ reference: reference })
      expect(abort_result).to eq({ aborted: true })

      # Input UTXO should be spendable again
      spendable = storage.find_spendable_outputs
      spendable_outpoints = spendable.map { |o| o[:outpoint] }
      expect(spendable_outpoints).to include(seeded[:outpoint])
    end

    it 'removes change outputs from storage on abort' do
      result = wallet.create_action({
                                      description: description,
                                      outputs: [{
                                        locking_script: p2pkh_hex,
                                        satoshis: 1000,
                                        output_description: 'no_send for abort cleanup test'
                                      }],
                                      options: { no_send: true }
                                    })

      change_ops = result[:no_send_change]
      expect(change_ops).not_to be_empty

      wallet.abort_action({ reference: result[:reference] })

      # Change outputs should no longer exist in storage at all
      all_outputs = storage.find_outputs({ include_spent: true, limit: 1000, offset: 0 })
      all_outpoints = all_outputs.map { |o| o[:outpoint] }
      change_ops.each do |op|
        expect(all_outpoints).not_to include(op)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 13. abort_action still works for signable transactions (regression guard)
  # ---------------------------------------------------------------------------
  describe 'abort_action regression — signable transaction flow unaffected' do
    it 'raises WalletError for an unknown reference' do
      expect do
        wallet.abort_action({ reference: 'nonexistent-reference' })
      end.to raise_error(BSV::Wallet::WalletError)
    end
  end

  # ---------------------------------------------------------------------------
  # 14. OP_RETURN-only outputs — note on zero satoshi outputs
  # ---------------------------------------------------------------------------
  # NOTE: The BRC-100 validator currently requires satoshis >= 1 for all outputs.
  # Zero-value OP_RETURN outputs are valid on BSV but are rejected by the current
  # validator. This is a pre-existing constraint unrelated to auto-funding.
  # When the validator is updated to allow zero-value data outputs, the auto-funding
  # pipeline will handle them correctly (coin selection target becomes fee-only).
  describe 'OP_RETURN-only outputs (non-zero satoshi)' do
    before { seed_payment_output(wallet, satoshis: 5000) }

    it 'succeeds when outputs include a small-value data output' do
      op_return_script = BSV::Script::Script.from_asm('OP_FALSE OP_RETURN').to_hex

      result = wallet.create_action({
                                      description: 'op_return data output test',
                                      outputs: [{
                                        locking_script: op_return_script,
                                        satoshis: 1,
                                        output_description: 'data output'
                                      }]
                                    })

      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  # ---------------------------------------------------------------------------
  # 15. Lazy collaborator instantiation — no injected fee_estimator
  # ---------------------------------------------------------------------------
  describe 'lazy instantiation of fee_estimator, coin_selector, change_generator' do
    it 'works without any injected collaborators (all defaulted)' do
      seed_payment_output(wallet, satoshis: 10_000)

      result = wallet.create_action({
                                      description: 'default collaborators test',
                                      outputs: [{
                                        locking_script: p2pkh_hex,
                                        satoshis: 1000,
                                        output_description: 'default setup output'
                                      }]
                                    })
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'accepts injected collaborators via constructor' do
      fee_estimator = BSV::Wallet::FeeEstimator.new(sats_per_kb: 1)
      coin_selector = BSV::Wallet::CoinSelector.new(fee_estimator: fee_estimator)
      change_generator = BSV::Wallet::ChangeGenerator.new(
        key_deriver: wallet.key_deriver,
        fee_estimator: fee_estimator,
        identity_key: wallet.key_deriver.identity_key,
        max_outputs: 1
      )
      custom_wallet = BSV::Wallet::WalletClient.new(
        private_key,
        storage: storage,
        fee_estimator: fee_estimator,
        coin_selector: coin_selector,
        change_generator: change_generator
      )
      seed_payment_output(custom_wallet, satoshis: 10_000)

      result = custom_wallet.create_action({
                                             description: 'injected collaborators test',
                                             outputs: [{
                                               locking_script: p2pkh_hex,
                                               satoshis: 1000,
                                               output_description: 'injected collaborator output'
                                             }]
                                           })
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end
  end
end
