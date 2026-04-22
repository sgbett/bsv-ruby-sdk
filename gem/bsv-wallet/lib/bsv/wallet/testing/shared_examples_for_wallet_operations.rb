# frozen_string_literal: true

require 'base64'
require 'fileutils'
require 'json'
require 'securerandom'
require 'time'
require 'tmpdir'

# Shared wallet-level operation examples for BSV::Wallet::Client.
#
# Each shared example group exercises a distinct area of wallet behaviour
# (certificates, auto-funding, broadcast, BEEF ancestry, etc.) and is
# parameterised via +let(:store)+ supplied by the including context:
#
#   STORE_FACTORIES.each do |label, factory|
#     context "(#{label})" do
#       let(:store) { factory.call }
#       it_behaves_like 'wallet certificate operations'
#     end
#   end
#
# Some shared example groups also expect +let(:store_label)+ — a human-readable
# name for the store backend (e.g. 'MemoryStore', 'FileStore', 'PostgresStore').
# This is used by the +'wallet local pool'+ and +'wallet pool health'+ groups
# to skip tests that are known to be unsafe on non-thread-safe backends.
# If not provided, no tests are skipped.
#
# Helper methods that depend on BSV internals (key derivation, script building,
# etc.) are defined inside each shared example group so they are in scope but
# do not pollute the global namespace.

# ---------------------------------------------------------------------------
# wallet auto-funding
# ---------------------------------------------------------------------------
RSpec.shared_examples 'wallet auto-funding' do
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

  def p2pkh_hex
    dest_key = BSV::Primitives::PrivateKey.generate.public_key
    BSV::Script::Script.p2pkh_lock(dest_key.hash160).to_hex
  end

  let(:description) { 'auto-funded payment action' }
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:storage) { store }
  let(:broadcaster) { double('broadcaster') }
  let(:wallet) do
    BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster, allow_memory_store: true)
  end

  before do
    allow(broadcaster).to receive(:broadcast).and_return(
      BSV::Network::BroadcastResponse.new(txid: 'stub', tx_status: 'SEEN_ON_NETWORK')
    )
  end

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
      spendable = storage.find_spendable_outputs
      spendable_outpoints = spendable.map { |o| o[:outpoint] }
      expect(spendable_outpoints).not_to include(seeded[:outpoint])
    end

    it 'stores a change output as :spendable with derivation metadata' do
      result
      spendable = storage.find_spendable_outputs
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

    it 'stores the action as unproven' do
      result
      actions = storage.find_actions({})
      expect(actions).not_to be_empty
      expect(actions.last[:status]).to eq('unproven')
    end

    it 'produces a valid BEEF' do
      beef_binary = result[:tx].pack('C*')
      beef = BSV::Transaction::Beef.from_binary(beef_binary)
      expect(beef.valid?).to be true
    end
  end

  describe 'UTXO state lifecycle' do
    let!(:seeded) { seed_payment_output(wallet, satoshis: 5000) }

    it 'transitions from spendable to spent on success' do
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

      after_spend = storage.find_spendable_outputs
      expect(after_spend.map { |o| o[:outpoint] }).not_to include(seeded[:outpoint])
    end
  end

  describe 'change is spendable in a follow-on transaction' do
    before do
      seed_payment_output(wallet, satoshis: 10_000)
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

  describe 'no change when excess is zero or sub-dust' do
    it 'produces no change output when excess is below the dust floor' do
      estimator = BSV::Wallet::FeeEstimator.new
      fee = estimator.estimate(p2pkh_inputs: 1, p2pkh_outputs: 2)
      seed_payment_output(wallet, satoshis: 1000 + fee)

      result = wallet.create_action({
                                      description: 'exact coverage spend test',
                                      outputs: [{
                                        locking_script: p2pkh_hex,
                                        satoshis: 1000,
                                        output_description: 'exact coverage output'
                                      }]
                                    })

      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end
  end

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
      expect(tx.outputs.length).to be >= 3
    end
  end

  describe 'basket-only outputs are excluded from auto-spending' do
    before do
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

  describe 'error rollback: pending UTXOs released when signing fails' do
    let!(:seeded) { seed_payment_output(wallet, satoshis: 10_000) }

    it 'returns the UTXO to :spendable if signing raises' do
      bad_generator = instance_double(BSV::Wallet::ChangeGenerator)
      allow(bad_generator).to receive(:generate).and_raise(RuntimeError, 'forced failure')

      bad_wallet = BSV::Wallet::Client.new(
        private_key,
        storage: storage,
        broadcaster: broadcaster,
        change_generator: bad_generator,
        allow_memory_store: true
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

      spendable = storage.find_spendable_outputs
      spendable_outpoints = spendable.map { |o| o[:outpoint] }
      expect(spendable_outpoints).to include(seeded[:outpoint])
    end
  end

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

      spendable = storage.find_spendable_outputs
      spendable_outpoints = spendable.map { |o| o[:outpoint] }
      change_ops.each do |op|
        expect(spendable_outpoints).not_to include(op)
      end
    end

    it 'does not allow auto-fund to select no_send change outputs' do
      result
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

    it 'stores no_send change outputs as :pending immediately, with pending_reference set' do
      result
      change_ops = result[:no_send_change]
      expect(change_ops).not_to be_empty

      fund_ref = result[:reference]
      all_outputs = storage.find_outputs({ include_spent: true })
      change_ops.each do |op|
        output = all_outputs.find { |o| o[:outpoint] == op }
        expect(output).not_to be_nil
        expect(output[:state]).to eq(:pending)
        expect(output[:pending_reference]).to eq(fund_ref)
        expect(output[:no_send]).to be(true)
      end
    end
  end

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

      all_outputs = storage.find_outputs({ include_spent: true, limit: 1000, offset: 0 })
      all_outpoints = all_outputs.map { |o| o[:outpoint] }
      change_ops.each do |op|
        expect(all_outpoints).not_to include(op)
      end
    end
  end

  describe 'abort_action regression — signable transaction flow unaffected' do
    it 'raises WalletError for an unknown reference' do
      expect do
        wallet.abort_action({ reference: 'nonexistent-reference' })
      end.to raise_error(BSV::Wallet::WalletError)
    end
  end

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
      custom_wallet = BSV::Wallet::Client.new(
        private_key,
        storage: storage,
        broadcaster: broadcaster,
        fee_estimator: fee_estimator,
        coin_selector: coin_selector,
        change_generator: change_generator,
        allow_memory_store: true
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

# ---------------------------------------------------------------------------
# wallet BEEF ancestry round-trip
# ---------------------------------------------------------------------------
RSpec.shared_examples 'wallet BEEF ancestry round-trip' do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:pub_key) { private_key.public_key }
  let(:storage) { store }
  let(:broadcaster) { double('broadcaster') }
  let(:wallet) do
    BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster, allow_memory_store: true)
  end

  let(:grandparent_tx) do
    tx = BSV::Transaction::Transaction.new
    tx.add_output(
      BSV::Transaction::TransactionOutput.new(
        satoshis: 10_000,
        locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160)
      )
    )
    tx
  end

  let(:grandparent_merkle_path) do
    txid_bytes = grandparent_tx.txid.reverse
    sibling    = ("\xAB" * 32).b
    tx_elem      = BSV::Transaction::MerklePath::PathElement.new(
      offset: 0, hash: txid_bytes, txid: true
    )
    sibling_elem = BSV::Transaction::MerklePath::PathElement.new(
      offset: 1, hash: sibling
    )
    BSV::Transaction::MerklePath.new(block_height: 850_000, path: [[tx_elem, sibling_elem]])
  end

  let(:parent_tx) do
    tx = BSV::Transaction::Transaction.new
    tx.add_input(
      BSV::Transaction::TransactionInput.new(
        prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(grandparent_tx.txid_hex),
        prev_tx_out_index: 0,
        unlocking_script: BSV::Script::Script.new
      )
    )
    tx.add_output(
      BSV::Transaction::TransactionOutput.new(
        satoshis: 9_000,
        locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160)
      )
    )
    tx
  end

  let(:subject_tx) do
    tx = BSV::Transaction::Transaction.new
    tx.add_input(
      BSV::Transaction::TransactionInput.new(
        prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(parent_tx.txid_hex),
        prev_tx_out_index: 0,
        unlocking_script: BSV::Script::Script.new
      )
    )
    tx.add_output(
      BSV::Transaction::TransactionOutput.new(
        satoshis: 8_000,
        locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160)
      )
    )
    tx
  end

  let(:incoming_beef_binary) do
    grandparent_tx.merkle_path = grandparent_merkle_path

    beef     = BSV::Transaction::Beef.new
    bump_idx = beef.merge_bump(grandparent_merkle_path)
    beef.transactions << BSV::Transaction::Beef::BeefTx.new(
      format: BSV::Transaction::Beef::FORMAT_RAW_TX_AND_BUMP,
      transaction: grandparent_tx,
      bump_index: bump_idx
    )
    beef.transactions << BSV::Transaction::Beef::BeefTx.new(
      format: BSV::Transaction::Beef::FORMAT_RAW_TX,
      transaction: parent_tx
    )
    beef.transactions << BSV::Transaction::Beef::BeefTx.new(
      format: BSV::Transaction::Beef::FORMAT_RAW_TX,
      transaction: subject_tx
    )
    beef.to_binary
  end

  let(:subject_txid) { subject_tx.txid_hex }

  let(:internalize_args) do
    {
      tx: incoming_beef_binary.unpack('C*'),
      description: 'BEEF ancestry round-trip — incoming payment',
      outputs: [
        {
          output_index: 0,
          protocol: 'basket insertion',
          insertion_remittance: { basket: 'beef ancestry test' }
        }
      ]
    }
  end

  context 'with a correctly wired BEEF' do
    let(:broadcasted_txs) { [] }

    before do
      allow(broadcaster).to receive(:broadcast) do |tx|
        broadcasted_txs << tx
        BSV::Network::BroadcastResponse.new(txid: tx.txid_hex, tx_status: 'SEEN_ON_NETWORK')
      end
    end

    it 'internalises the incoming BEEF and stores the ancestor transactions' do
      wallet.internalize_action(internalize_args)

      expect(storage.find_transaction(subject_txid)).not_to be_nil
      expect(storage.find_transaction(parent_tx.txid_hex)).not_to be_nil
      expect(storage.find_transaction(grandparent_tx.txid_hex)).not_to be_nil
    end

    it 'stores the merkle proof for the confirmed grandparent' do
      wallet.internalize_action(internalize_args)

      proof = wallet.proof_store.resolve_proof(grandparent_tx.txid_hex)
      expect(proof).to be_a(BSV::Transaction::MerklePath)
      expect(proof.block_height).to eq(850_000)
    end

    it 'spend of the internalised output broadcasts with valid EF (full ancestry wired)' do
      wallet.internalize_action(internalize_args)

      result = wallet.create_action({
                                      description: 'spend internalised output — HLR #466',
                                      inputs: [
                                        {
                                          outpoint: "#{subject_txid}.0",
                                          input_description: 'internalised basket output',
                                          unlocking_script: BSV::Script::Script.new.to_hex
                                        }
                                      ],
                                      outputs: [
                                        {
                                          locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160).to_hex,
                                          satoshis: 7_000,
                                          output_description: 'recipient output'
                                        }
                                      ]
                                    })

      expect(broadcaster).to have_received(:broadcast).once
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
      expect(result[:tx]).to be_a(Array)
      ef_hex = broadcasted_txs.last.to_ef_hex
      ef_bytes = [ef_hex].pack('H*')
      expect(ef_bytes.byteslice(4, 6)).to eq("\x00\x00\x00\x00\x00\xEF".b)
    end

    it 'resulting BEEF from create_action contains ancestor transactions' do
      wallet.internalize_action(internalize_args)

      result = wallet.create_action({
                                      description: 'check BEEF ancestry — HLR #466',
                                      inputs: [
                                        {
                                          outpoint: "#{subject_txid}.0",
                                          input_description: 'internalised basket output',
                                          unlocking_script: BSV::Script::Script.new.to_hex
                                        }
                                      ],
                                      outputs: [
                                        {
                                          locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160).to_hex,
                                          satoshis: 7_000,
                                          output_description: 'recipient output'
                                        }
                                      ]
                                    })

      new_beef = BSV::Transaction::Beef.from_binary(result[:tx].pack('C*'))
      tx_txids = new_beef.transactions.filter_map { |bt| bt.transaction&.txid_hex }
      expect(tx_txids).to include(subject_txid)
    end
  end

  context 'when ancestry is stripped (regression defence)' do
    it 'to_ef_hex raises ArgumentError when source_transaction is not wired' do
      wallet.internalize_action(internalize_args)

      bare_input = BSV::Transaction::TransactionInput.new(
        prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(subject_txid),
        prev_tx_out_index: 0,
        unlocking_script: BSV::Script::Script.new
      )
      bare_tx = BSV::Transaction::Transaction.new
      bare_tx.add_input(bare_input)
      bare_tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: 7_000,
          locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160)
        )
      )

      expect { bare_tx.to_ef_hex }.to raise_error(ArgumentError, /source_satoshis/)
    end
  end

  context 'with parent tx unproven (raw only, no BUMP)' do
    let(:broadcasted_txs) { [] }

    before do
      allow(broadcaster).to receive(:broadcast) do |tx|
        broadcasted_txs << tx
        BSV::Network::BroadcastResponse.new(txid: tx.txid_hex, tx_status: 'SEEN_ON_NETWORK')
      end
    end

    it 'EF serialises when immediate parent has no BUMP' do
      wallet.internalize_action(internalize_args)

      result = wallet.create_action({
                                      description: 'unproven parent EF test — HLR #466',
                                      inputs: [
                                        {
                                          outpoint: "#{subject_txid}.0",
                                          input_description: 'internalised basket output',
                                          unlocking_script: BSV::Script::Script.new.to_hex
                                        }
                                      ],
                                      outputs: [
                                        {
                                          locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160).to_hex,
                                          satoshis: 7_000,
                                          output_description: 'recipient output'
                                        }
                                      ]
                                    })

      expect(broadcaster).to have_received(:broadcast).once
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
      ef_hex = broadcasted_txs.last.to_ef_hex
      ef_bytes = [ef_hex].pack('H*')
      expect(ef_bytes.byteslice(4, 6)).to eq("\x00\x00\x00\x00\x00\xEF".b)
    end
  end
end

# ---------------------------------------------------------------------------
# wallet broadcast rollback
# ---------------------------------------------------------------------------
RSpec.shared_examples 'wallet broadcast rollback' do
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

  def recipient_lock_hex
    BSV::Script::Script.p2pkh_lock(BSV::Primitives::PrivateKey.generate.public_key.hash160).to_hex
  end

  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:storage)     { store }

  let(:broadcast_ok) do
    BSV::Network::BroadcastResponse.new(txid: 'aabbcc', tx_status: 'SEEN_ON_NETWORK')
  end

  describe 'broadcast succeeds → state promoted to final' do
    let(:broadcaster) { double('broadcaster') }
    let(:wallet) do
      BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster, allow_memory_store: true)
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
      tx.inputs.each do |inp|
        source_txid = inp.prev_tx_id.reverse.unpack1('H*')
        vout = inp.prev_tx_out_index
        outpoint = "#{source_txid}.#{vout}"
        stored = all.find { |o| o[:outpoint] == outpoint }
        next unless stored

        expect(stored[:state]).to eq(:spent)
      end
    end

    it 'marks change outputs as :spendable' do
      result
      spendable = storage.find_spendable_outputs(basket: 'default')
      change = spendable.select { |o| o[:derivation_prefix] }
      expect(change).not_to be_empty
      change.each { |o| expect(o[:state]).to eq(:spendable) }
    end

    it 'stores the action with status "unproven"' do
      txid = result[:txid]
      actions = storage.find_actions({ limit: 100, offset: 0 })
      action = actions.find { |a| a[:txid] == txid }
      expect(action[:status]).to eq('unproven')
    end
  end

  describe 'broadcast fails → full rollback' do
    let(:broadcaster) { double('broadcaster') }
    let(:wallet) do
      BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster, allow_memory_store: true)
    end
    let(:seeded_outpoint) { seed_payment_output(wallet, satoshis: 10_000)[:outpoint] }
    let(:result) do
      seeded_outpoint
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

  describe 'promotion failure after successful broadcast → no rollback of on-chain outputs' do
    let(:broadcaster) { double('broadcaster') }
    let(:wallet) do
      BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster, allow_memory_store: true)
    end

    before { seed_payment_output(wallet, satoshis: 10_000) }

    it 'propagates the promotion error without deleting change outputs' do
      allow(broadcaster).to receive(:broadcast).and_return(broadcast_ok)

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

      all = storage.find_outputs({ include_spent: true, limit: 1000, offset: 0 })
      expect(all.size).to be >= 2
    end
  end

  describe 'send_with broadcast succeeds → per-tx state promoted' do
    let(:broadcaster) { double('broadcaster') }
    let(:wallet) do
      BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster, allow_memory_store: true)
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

      spendable = storage.find_spendable_outputs
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

  describe 'send_with broadcast fails → per-tx rollback' do
    let(:broadcaster) { double('broadcaster') }
    let(:wallet) do
      BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster, allow_memory_store: true)
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

      first_input_ops.each { |op| expect(spendable_ops).to include(op) }
      second_input_ops.each { |op| expect(spendable_ops).not_to include(op) }
    end
  end

  describe 'concurrent auto-fund exclusion of pending change outputs' do
    let(:broadcaster) { double('broadcaster') }
    let(:wallet) do
      BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster, allow_memory_store: true)
    end

    before { seed_payment_output(wallet, satoshis: 10_000) }

    it 'raises InsufficientFundsError when the only spendable UTXO is locked as :pending' do
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

# ---------------------------------------------------------------------------
# wallet certificate operations
# ---------------------------------------------------------------------------
RSpec.shared_examples 'wallet certificate operations' do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:wallet) { BSV::Wallet::Client.new(private_key, storage: store, allow_memory_store: true) }
  let(:certifier_key) { BSV::Primitives::PrivateKey.generate }
  let(:certifier_hex) { certifier_key.public_key.to_hex }
  let(:certifier_wallet) { BSV::Wallet::Client.new(certifier_key, storage: store, allow_memory_store: true) }

  let(:cert_type) { Base64.strict_encode64(SecureRandom.random_bytes(32)) }
  let(:serial_number) { Base64.strict_encode64(SecureRandom.random_bytes(32)) }
  let(:revocation_outpoint) { "#{'ab' * 32}.0" }

  let(:fields) { { 'name' => 'Alice', 'email' => 'alice@example.com' } }
  let(:keyring) { { 'name' => Base64.strict_encode64('key1'), 'email' => Base64.strict_encode64('key2') } }

  let(:signature) do
    preimage = BSV::Wallet::CertificateSignature.serialise_preimage(
      type: cert_type,
      serial_number: serial_number,
      subject: wallet.key_deriver.identity_key,
      certifier: certifier_hex,
      revocation_outpoint: revocation_outpoint,
      fields: fields
    )
    result = certifier_wallet.create_signature({
                                                 data: preimage.unpack('C*'),
                                                 protocol_id: [2, 'certificate signature'],
                                                 key_id: "#{cert_type} #{serial_number}",
                                                 counterparty: 'anyone'
                                               })
    result[:signature].pack('C*').unpack1('H*')
  end

  let(:direct_args) do
    {
      type: cert_type,
      certifier: certifier_hex,
      acquisition_protocol: 'direct',
      fields: fields,
      serial_number: serial_number,
      revocation_outpoint: revocation_outpoint,
      signature: signature,
      keyring_revealer: 'certifier',
      keyring_for_subject: keyring
    }
  end

  # -------------------------------------------------------------------------
  # acquire_certificate
  # -------------------------------------------------------------------------
  describe '#acquire_certificate' do
    it 'stores and returns a direct certificate' do
      result = wallet.acquire_certificate(direct_args)
      expect(result[:type]).to eq(cert_type)
      expect(result[:subject]).to eq(wallet.key_deriver.identity_key)
      expect(result[:serial_number]).to eq(serial_number)
      expect(result[:certifier]).to eq(certifier_hex)
      expect(result[:fields]).to eq(fields)
    end

    it 'does not return the keyring in the result' do
      result = wallet.acquire_certificate(direct_args)
      expect(result).not_to have_key(:keyring)
    end

    # Regression for https://github.com/sgbett/bsv-ruby-sdk/issues/305 (F8.15)
    describe 'BRC-52 certifier signature verification (issue #305)' do
      it 'rejects a certificate with an invalid signature' do
        tampered = direct_args.merge(signature: 'ff' * 70)

        expect { wallet.acquire_certificate(tampered) }
          .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)
      end

      it 'rejects a certificate whose fields have been tampered with after signing' do
        tampered = direct_args.merge(fields: fields.merge('email' => 'attacker@example.com'))

        expect { wallet.acquire_certificate(tampered) }
          .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)
      end

      it 'rejects a certificate whose subject is overridden' do
        other_wallet_signature = begin
          other_key = BSV::Primitives::PrivateKey.generate
          preimage = BSV::Wallet::CertificateSignature.serialise_preimage(
            type: cert_type,
            serial_number: serial_number,
            subject: other_key.public_key.to_hex,
            certifier: certifier_hex,
            revocation_outpoint: revocation_outpoint,
            fields: fields
          )
          result = certifier_wallet.create_signature({
                                                       data: preimage.unpack('C*'),
                                                       protocol_id: [2, 'certificate signature'],
                                                       key_id: "#{cert_type} #{serial_number}",
                                                       counterparty: 'anyone'
                                                     })
          result[:signature].pack('C*').unpack1('H*')
        end

        tampered = direct_args.merge(signature: other_wallet_signature)

        expect { wallet.acquire_certificate(tampered) }
          .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)
      end

      it 'rejects a certificate signed by a different certifier' do
        imposter_key = BSV::Primitives::PrivateKey.generate
        imposter_wallet = BSV::Wallet::Client.new(imposter_key, storage: store, allow_memory_store: true)
        preimage = BSV::Wallet::CertificateSignature.serialise_preimage(
          type: cert_type,
          serial_number: serial_number,
          subject: wallet.key_deriver.identity_key,
          certifier: certifier_hex,
          revocation_outpoint: revocation_outpoint,
          fields: fields
        )
        imposter_sig = imposter_wallet.create_signature({
                                                          data: preimage.unpack('C*'),
                                                          protocol_id: [2, 'certificate signature'],
                                                          key_id: "#{cert_type} #{serial_number}",
                                                          counterparty: 'anyone'
                                                        })[:signature].pack('C*').unpack1('H*')

        tampered = direct_args.merge(signature: imposter_sig)

        expect { wallet.acquire_certificate(tampered) }
          .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)
      end

      it 'rejects a certificate with a malformed (non-hex) signature' do
        tampered = direct_args.merge(signature: 'not hex at all')

        expect { wallet.acquire_certificate(tampered) }
          .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)
      end

      it 'does not persist an unverified certificate to storage' do
        tampered = direct_args.merge(signature: 'ff' * 70)

        expect { wallet.acquire_certificate(tampered) }
          .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)

        certs = wallet.list_certificates({ certifiers: [certifier_hex], types: [cert_type] })
        expect(certs[:total_certificates]).to eq(0)
      end
    end

    # Follow-up hardening from PR #306 review.
    describe 'CertificateSignature input validation (#306 review)' do
      # #2 — strict base64 decode
      it 'rejects a certificate whose type has whitespace-injected base64' do
        raw32 = "\x01".b * 32
        valid_type = Base64.strict_encode64(raw32)
        whitespace_injected = valid_type.chars.each_slice(8).map(&:join).join("\n")

        tampered = direct_args.merge(type: whitespace_injected)

        expect { wallet.acquire_certificate(tampered) }
          .to raise_error(BSV::Wallet::CertificateSignature::InvalidError, /base64/)
      end

      it 'rejects a certificate whose serial_number has non-base64 characters' do
        tampered = direct_args.merge(serial_number: 'not valid base64!!@#$%^&*()_+|')

        expect { wallet.acquire_certificate(tampered) }
          .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)
      end

      # #3 — EncodingError → InvalidError
      it 'rejects a certificate with non-UTF-8 bytes in a field value as InvalidError' do
        bad_field_value = "\x80".b
        tampered = direct_args.merge(fields: fields.merge('email' => bad_field_value))

        expect { wallet.acquire_certificate(tampered) }
          .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)
      end

      # #4 — duplicate field names
      it 'rejects fields containing both symbol and string forms of the same name' do
        ambiguous = { 'email' => 'one@example.com', email: 'two@example.com' }
        tampered = direct_args.merge(fields: ambiguous)

        expect { wallet.acquire_certificate(tampered) }
          .to raise_error(BSV::Wallet::CertificateSignature::InvalidError, /duplicate field name/)
      end

      # #6 — hex_to_bytes even-length guard
      it 'rejects an odd-length signature hex' do
        tampered = direct_args.merge(signature: signature[0...-1])

        expect { wallet.acquire_certificate(tampered) }
          .to raise_error(BSV::Wallet::CertificateSignature::InvalidError, /even/)
      end
    end

    it 'raises InvalidParameterError for issuance without certifier_url' do
      args = direct_args.merge(acquisition_protocol: 'issuance')
      args.delete(:serial_number)
      args.delete(:revocation_outpoint)
      args.delete(:signature)
      args.delete(:keyring_for_subject)
      expect { wallet.acquire_certificate(args) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    context 'with issuance protocol' do
      let(:issuance_response_body) do
        JSON.generate({
                        'type' => cert_type,
                        'subject' => wallet.key_deriver.identity_key,
                        'serialNumber' => serial_number,
                        'certifier' => certifier_hex,
                        'revocationOutpoint' => revocation_outpoint,
                        'signature' => signature,
                        'fields' => fields,
                        'keyringForSubject' => keyring
                      })
      end

      let(:mock_auth_response) do
        BSV::Auth::AuthResponse.new(
          status: 200,
          headers: {},
          body: issuance_response_body,
          identity_key: certifier_hex
        )
      end

      let(:mock_auth_fetch) do
        double('auth_fetch', fetch: mock_auth_response)
      end

      let(:issuance_wallet) do
        w = BSV::Wallet::Client.new(private_key, storage: store, allow_memory_store: true)
        allow(w).to receive(:auth_fetch_client).and_return(mock_auth_fetch)
        w
      end

      let(:issuance_args) do
        {
          type: cert_type,
          certifier: certifier_hex,
          acquisition_protocol: 'issuance',
          fields: fields,
          certifier_url: 'https://certifier.example.com/api/issue'
        }
      end

      it 'acquires a certificate via issuance protocol' do
        result = issuance_wallet.acquire_certificate(issuance_args)
        expect(result[:type]).to eq(cert_type)
        expect(result[:subject]).to eq(wallet.key_deriver.identity_key)
        expect(result[:serial_number]).to eq(serial_number)
        expect(result[:certifier]).to eq(certifier_hex)
      end

      it 'does not return the keyring in the result' do
        result = issuance_wallet.acquire_certificate(issuance_args)
        expect(result).not_to have_key(:keyring)
      end

      it 'stores the certificate in storage' do
        issuance_wallet.acquire_certificate(issuance_args)
        certs = issuance_wallet.list_certificates({ certifiers: [certifier_hex], types: [cert_type] })
        expect(certs[:total_certificates]).to eq(1)
      end

      it 'calls AuthFetch#fetch with correct URL, method, headers, and body' do
        expected_body = JSON.generate({
                                        type: cert_type,
                                        subject: issuance_wallet.key_deriver.identity_key,
                                        certifier: certifier_hex,
                                        fields: fields
                                      })
        allow(mock_auth_fetch).to receive(:fetch).and_return(mock_auth_response)
        issuance_wallet.acquire_certificate(issuance_args)
        expect(mock_auth_fetch).to have_received(:fetch).with(
          'https://certifier.example.com/api/issue',
          method: 'POST',
          headers: { 'content-type' => 'application/json' },
          body: expected_body
        )
      end

      it 'raises WalletError on HTTP failure' do
        failing_auth_fetch = double('auth_fetch')
        allow(failing_auth_fetch).to receive(:fetch).and_return(
          BSV::Auth::AuthResponse.new(status: 500, headers: {}, body: 'error', identity_key: certifier_hex)
        )
        w = BSV::Wallet::Client.new(private_key, storage: store, allow_memory_store: true)
        allow(w).to receive(:auth_fetch_client).and_return(failing_auth_fetch)
        expect { w.acquire_certificate(issuance_args) }.to raise_error(BSV::Wallet::WalletError, /HTTP 500/)
      end

      it 'raises WalletError on invalid JSON response' do
        bad_auth_fetch = double('auth_fetch')
        allow(bad_auth_fetch).to receive(:fetch).and_return(
          BSV::Auth::AuthResponse.new(status: 200, headers: {}, body: 'not json', identity_key: certifier_hex)
        )
        w = BSV::Wallet::Client.new(private_key, storage: store, allow_memory_store: true)
        allow(w).to receive(:auth_fetch_client).and_return(bad_auth_fetch)
        expect { w.acquire_certificate(issuance_args) }.to raise_error(BSV::Wallet::WalletError, /invalid JSON/)
      end

      it 'verifies the certifier signature on the issuance response' do
        tampered_auth_fetch = double('auth_fetch')
        tampered_body = JSON.generate({
                                        'type' => cert_type,
                                        'serialNumber' => serial_number,
                                        'revocationOutpoint' => revocation_outpoint,
                                        'signature' => 'ff' * 70,
                                        'fields' => fields
                                      })
        allow(tampered_auth_fetch).to receive(:fetch).and_return(
          BSV::Auth::AuthResponse.new(status: 200, headers: {}, body: tampered_body, identity_key: certifier_hex)
        )
        w = BSV::Wallet::Client.new(private_key, storage: store, allow_memory_store: true)
        allow(w).to receive(:auth_fetch_client).and_return(tampered_auth_fetch)
        expect { w.acquire_certificate(issuance_args) }
          .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)
      end

      it 'lazily initialises auth_fetch_client on first call and memoises it' do
        w = BSV::Wallet::Client.new(private_key, storage: store, allow_memory_store: true)
        allow(BSV::Auth::AuthFetch).to receive(:new).and_call_original
        client1 = w.send(:auth_fetch_client)
        client2 = w.send(:auth_fetch_client)
        expect(client1).to be(client2)
        expect(BSV::Auth::AuthFetch).to have_received(:new).once
      end

      it 'passes self as the wallet to AuthFetch' do
        w = BSV::Wallet::Client.new(private_key, storage: store, allow_memory_store: true)
        allow(BSV::Auth::AuthFetch).to receive(:new).and_call_original
        w.send(:auth_fetch_client)
        expect(BSV::Auth::AuthFetch).to have_received(:new).with(wallet: w)
      end
    end

    it 'raises InvalidParameterError for invalid protocol' do
      args = direct_args.merge(acquisition_protocol: 'unknown')
      expect { wallet.acquire_certificate(args) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError when missing required direct fields' do
      %i[serial_number revocation_outpoint signature keyring_for_subject].each do |field|
        args = direct_args.dup
        args.delete(field)
        expect { wallet.acquire_certificate(args) }.to raise_error(BSV::Wallet::InvalidParameterError)
      end
    end

    it 'raises InvalidParameterError for invalid certifier' do
      args = direct_args.merge(certifier: 'bad')
      expect { wallet.acquire_certificate(args) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  # -------------------------------------------------------------------------
  # list_certificates
  # -------------------------------------------------------------------------
  describe '#list_certificates' do
    before { wallet.acquire_certificate(direct_args) }

    it 'lists certificates by certifier and type' do
      result = wallet.list_certificates({ certifiers: [certifier_hex], types: [cert_type] })
      expect(result[:total_certificates]).to eq(1)
      expect(result[:certificates].first[:serial_number]).to eq(serial_number)
    end

    it 'does not include the keyring' do
      result = wallet.list_certificates({ certifiers: [certifier_hex], types: [cert_type] })
      expect(result[:certificates].first).not_to have_key(:keyring)
    end

    it 'returns empty when no match' do
      result = wallet.list_certificates({ certifiers: ['aa' * 33], types: [cert_type] })
      expect(result[:total_certificates]).to eq(0)
      expect(result[:certificates]).to be_empty
    end

    it 'raises InvalidParameterError for missing certifiers' do
      expect { wallet.list_certificates({ types: [cert_type] }) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError for missing types' do
      expect { wallet.list_certificates({ certifiers: [certifier_hex] }) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  # -------------------------------------------------------------------------
  # prove_certificate
  # -------------------------------------------------------------------------
  describe '#prove_certificate' do
    let(:verifier_key) { BSV::Primitives::PrivateKey.generate }
    let(:verifier_hex) { verifier_key.public_key.to_hex }

    before { wallet.acquire_certificate(direct_args) }

    it 'returns encrypted keyring entries for the verifier' do
      result = wallet.prove_certificate({
                                          certificate: { type: cert_type, serial_number: serial_number, certifier: certifier_hex },
                                          fields_to_reveal: ['name'],
                                          verifier: verifier_hex
                                        })
      expect(result[:keyring_for_verifier]).to have_key('name')
      expect(result[:keyring_for_verifier]['name']).to be_a(Array)
    end

    it 'encrypts multiple fields when requested' do
      result = wallet.prove_certificate({
                                          certificate: { type: cert_type, serial_number: serial_number, certifier: certifier_hex },
                                          fields_to_reveal: %w[name email],
                                          verifier: verifier_hex
                                        })
      expect(result[:keyring_for_verifier].keys).to contain_exactly('name', 'email')
    end

    it 'allows the verifier to decrypt the keyring entry' do
      verifier_wallet = BSV::Wallet::Client.new(verifier_key, storage: store, allow_memory_store: true)
      prover_identity = wallet.key_deriver.identity_key

      result = wallet.prove_certificate({
                                          certificate: { type: cert_type, serial_number: serial_number, certifier: certifier_hex },
                                          fields_to_reveal: ['name'],
                                          verifier: verifier_hex
                                        })

      decrypted = verifier_wallet.decrypt({
                                            ciphertext: result[:keyring_for_verifier]['name'],
                                            protocol_id: [2, 'certificate field encryption'],
                                            key_id: "#{serial_number} name",
                                            counterparty: prover_identity
                                          })
      expect(decrypted[:plaintext].pack('C*')).to eq(keyring['name'])
    end

    it 'raises WalletError when certificate not found' do
      expect do
        wallet.prove_certificate({
                                   certificate: { type: 'nonexistent', serial_number: 'x', certifier: certifier_hex },
                                   fields_to_reveal: ['name'],
                                   verifier: verifier_hex
                                 })
      end.to raise_error(BSV::Wallet::WalletError)
    end

    it 'raises InvalidParameterError for invalid verifier' do
      expect do
        wallet.prove_certificate({
                                   certificate: { type: cert_type, serial_number: serial_number, certifier: certifier_hex },
                                   fields_to_reveal: ['name'],
                                   verifier: 'bad'
                                 })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  # -------------------------------------------------------------------------
  # relinquish_certificate
  # -------------------------------------------------------------------------
  describe '#relinquish_certificate' do
    before { wallet.acquire_certificate(direct_args) }

    it 'removes the certificate and returns relinquished: true' do
      result = wallet.relinquish_certificate({ type: cert_type, serial_number: serial_number, certifier: certifier_hex })
      expect(result[:relinquished]).to be true

      listed = wallet.list_certificates({ certifiers: [certifier_hex], types: [cert_type] })
      expect(listed[:total_certificates]).to eq(0)
    end

    it 'raises WalletError when certificate not found' do
      expect do
        wallet.relinquish_certificate({ type: 'nonexistent', serial_number: 'x', certifier: certifier_hex })
      end.to raise_error(BSV::Wallet::WalletError)
    end
  end

  # -------------------------------------------------------------------------
  # discover_by_identity_key
  # -------------------------------------------------------------------------
  describe '#discover_by_identity_key' do
    before { wallet.acquire_certificate(direct_args) }

    it 'finds certificates for the wallet identity key' do
      result = wallet.discover_by_identity_key({ identity_key: wallet.key_deriver.identity_key })
      expect(result[:total_certificates]).to eq(1)
      expect(result[:certificates].first[:type]).to eq(cert_type)
    end

    it 'returns empty for an unknown identity key' do
      other_key = BSV::Primitives::PrivateKey.generate.public_key.to_hex
      result = wallet.discover_by_identity_key({ identity_key: other_key })
      expect(result[:total_certificates]).to eq(0)
    end

    it 'does not include the keyring' do
      result = wallet.discover_by_identity_key({ identity_key: wallet.key_deriver.identity_key })
      expect(result[:certificates].first).not_to have_key(:keyring)
    end

    it 'raises InvalidParameterError for invalid identity key' do
      expect do
        wallet.discover_by_identity_key({ identity_key: 'bad' })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  # -------------------------------------------------------------------------
  # discover_by_attributes
  # -------------------------------------------------------------------------
  describe '#discover_by_attributes' do
    before { wallet.acquire_certificate(direct_args) }

    it 'finds certificates matching field values' do
      result = wallet.discover_by_attributes({ attributes: { 'name' => 'Alice' } })
      expect(result[:total_certificates]).to eq(1)
    end

    it 'returns empty when no fields match' do
      result = wallet.discover_by_attributes({ attributes: { 'name' => 'Bob' } })
      expect(result[:total_certificates]).to eq(0)
    end

    it 'raises InvalidParameterError for empty attributes' do
      expect do
        wallet.discover_by_attributes({ attributes: {} })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end
end

# ---------------------------------------------------------------------------
# wallet UTXO pending locks
# ---------------------------------------------------------------------------
RSpec.shared_examples 'wallet UTXO pending locks' do
  def seed_output(store, outpoint: 'tx0:0', satoshis: 1000, basket: 'default')
    store.store_output(
      outpoint: outpoint,
      satoshis: satoshis,
      basket: basket,
      state: :spendable
    )
  end

  describe 'marking an output as pending with a reference' do
    it 'sets :pending_since as an ISO 8601 UTC timestamp' do
      seed_output(store)
      before = Time.now.utc
      store.update_output_state('tx0:0', :pending, pending_reference: 'action-123')
      after = Time.now.utc

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      raw = outputs.first[:pending_since]

      expect(raw).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)

      pending_since = Time.parse(raw)
      expect(pending_since).to be >= (before - 1)
      expect(pending_since).to be <= after
    end

    it 'stores the caller-supplied :pending_reference' do
      seed_output(store)
      store.update_output_state('tx0:0', :pending, pending_reference: 'action-123')

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      expect(outputs.first[:pending_reference]).to eq('action-123')
    end
  end

  describe '#find_spendable_outputs' do
    it 'excludes outputs in :pending state' do
      seed_output(store, outpoint: 'tx0:0', satoshis: 500)
      seed_output(store, outpoint: 'tx1:0', satoshis: 300)
      store.update_output_state('tx0:0', :pending, pending_reference: 'ref-xyz')

      results = store.find_spendable_outputs
      expect(results.map { |o| o[:outpoint] }).to eq(['tx1:0'])
    end
  end

  describe '#release_stale_pending!' do
    it 'releases a lock that is older than the timeout' do
      seed_output(store)
      store.update_output_state('tx0:0', :pending, pending_reference: 'stale-ref')

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      outputs.first[:pending_since] = (Time.now.utc - 360).iso8601

      released = store.release_stale_pending!(timeout: 300)
      expect(released).to eq(1)

      spendable = store.find_spendable_outputs
      expect(spendable.map { |o| o[:outpoint] }).to include('tx0:0')
    end

    it 'clears :pending_since and :pending_reference after release' do
      seed_output(store)
      store.update_output_state('tx0:0', :pending, pending_reference: 'stale-ref')

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      outputs.first[:pending_since] = (Time.now.utc - 360).iso8601

      store.release_stale_pending!(timeout: 300)

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      expect(outputs.first).not_to have_key(:pending_since)
      expect(outputs.first).not_to have_key(:pending_reference)
    end

    it 'preserves a lock that is within the timeout window' do
      seed_output(store)
      store.update_output_state('tx0:0', :pending, pending_reference: 'fresh-ref')

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      outputs.first[:pending_since] = (Time.now.utc - 60).iso8601

      released = store.release_stale_pending!(timeout: 300)
      expect(released).to eq(0)

      spendable = store.find_spendable_outputs
      expect(spendable).to be_empty
    end
  end

  describe 'abort_action releases pending UTXOs' do
    let(:private_key) { BSV::Primitives::PrivateKey.generate }
    let(:storage)     { store }
    let(:broadcaster) { double('broadcaster') }
    let(:wallet) do
      BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster, allow_memory_store: true)
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

      spendable = storage.find_spendable_outputs
      expect(spendable.map { |o| o[:outpoint] }).to include(outpoint)
    end
  end

  describe 'thread safety' do
    it 'allows only one thread to lock a single UTXO as pending' do
      seed_output(store, outpoint: 'shared:0', satoshis: 1000)

      results = Array.new(2)
      barrier = Queue.new

      threads = 2.times.map do |i|
        Thread.new do
          barrier.pop

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

      2.times { barrier.push(:go) }
      threads.each(&:join)

      locked_count = results.count(:locked)
      expect(locked_count).to eq(1), "Expected exactly 1 thread to lock the UTXO; got #{locked_count} (results: #{results.inspect})"

      spendable_after = store.find_spendable_outputs
      expect(spendable_after.map { |o| o[:outpoint] }).not_to include('shared:0')
    end
  end

  describe 'full state lifecycle' do
    it 'transitions correctly through spendable → pending → spent' do
      seed_output(store)

      expect(store.find_spendable_outputs.map { |o| o[:outpoint] }).to include('tx0:0')

      store.update_output_state('tx0:0', :pending, pending_reference: 'lifecycle-ref')
      spendable_after_lock = store.find_spendable_outputs
      expect(spendable_after_lock.map { |o| o[:outpoint] }).not_to include('tx0:0')

      pending_output = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 }).first
      expect(pending_output[:state]).to eq(:pending)
      expect(pending_output[:pending_reference]).to eq('lifecycle-ref')
      expect(pending_output[:pending_since]).not_to be_nil

      store.update_output_state('tx0:0', :spent)
      spent_output = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 }).first
      expect(spent_output[:state]).to eq(:spent)
      expect(spent_output).not_to have_key(:pending_since)
      expect(spent_output).not_to have_key(:pending_reference)
    end
  end

  describe 'no_send lock exemption' do
    it 'does not release a stale no_send lock during release_stale_pending!' do
      seed_output(store)
      store.update_output_state('tx0:0', :pending, pending_reference: 'no-send-ref', no_send: true)

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      outputs.first[:pending_since] = (Time.now.utc - 600).iso8601

      released = store.release_stale_pending!(timeout: 300)
      expect(released).to eq(0)

      spendable = store.find_spendable_outputs
      expect(spendable).to be_empty
    end

    it 'stores the :no_send flag on the output when marking pending with no_send: true' do
      seed_output(store)
      store.update_output_state('tx0:0', :pending, pending_reference: 'ns-ref', no_send: true)

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      expect(outputs.first[:no_send]).to be true
    end

    it 'clears the :no_send flag when transitioning away from pending' do
      seed_output(store)
      store.update_output_state('tx0:0', :pending, pending_reference: 'ns-ref', no_send: true)
      store.update_output_state('tx0:0', :spendable)

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      expect(outputs.first).not_to have_key(:no_send)
    end

    it 'does not set :no_send on an ordinary pending lock' do
      seed_output(store)
      store.update_output_state('tx0:0', :pending, pending_reference: 'ordinary-ref')

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      expect(outputs.first).not_to have_key(:no_send)
    end
  end

  # -----------------------------------------------------------------------
  # Clearing metadata on transition to spent
  # -----------------------------------------------------------------------
  describe 'clearing metadata on transition to spent' do
    it 'removes :pending_since and :pending_reference when marking spent' do
      seed_output(store)
      store.update_output_state('tx0:0', :pending, pending_reference: 'to-be-spent')

      store.update_output_state('tx0:0', :spent)

      outputs = store.find_outputs({ outpoint: 'tx0:0', include_spent: true, limit: 1, offset: 0 })
      output = outputs.first
      expect(output[:state]).to eq(:spent)
      expect(output).not_to have_key(:pending_since)
      expect(output).not_to have_key(:pending_reference)
    end
  end
end

# ---------------------------------------------------------------------------
# wallet pool health
# ---------------------------------------------------------------------------
RSpec.shared_examples 'wallet pool health' do
  # --- balance ---

  describe 'Client#balance' do
    let(:private_key) { BSV::Primitives::PrivateKey.generate }
    let(:client)      { BSV::Wallet::Client.new(private_key, storage: store, allow_memory_store: true) }

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
    let(:client)      { BSV::Wallet::Client.new(private_key, storage: store, allow_memory_store: true) }

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
    let(:client)      { BSV::Wallet::Client.new(private_key, storage: store, allow_memory_store: true) }

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

# ---------------------------------------------------------------------------
# wallet proof round-trip
# ---------------------------------------------------------------------------
RSpec.shared_examples 'wallet proof round-trip' do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:pub_key) { private_key.public_key }
  let(:source_tx) do
    tx = BSV::Transaction::Transaction.new
    tx.add_output(
      BSV::Transaction::TransactionOutput.new(
        satoshis: 5000,
        locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160)
      )
    )
    tx
  end
  let(:merkle_path) do
    txid_bytes = source_tx.txid.reverse
    sibling = ("\xCD" * 32).b
    tx_elem = BSV::Transaction::MerklePath::PathElement.new(
      offset: 0, hash: txid_bytes, txid: true
    )
    sibling_elem = BSV::Transaction::MerklePath::PathElement.new(
      offset: 1, hash: sibling
    )
    BSV::Transaction::MerklePath.new(block_height: 800_000, path: [[tx_elem, sibling_elem]])
  end
  let(:beef_for_internalize) do
    source_tx.merkle_path = merkle_path

    subject_tx = BSV::Transaction::Transaction.new
    subject_tx.add_input(
      BSV::Transaction::TransactionInput.new(
        prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(source_tx.txid_hex),
        prev_tx_out_index: 0,
        unlocking_script: BSV::Script::Script.new
      )
    )
    subject_tx.add_output(
      BSV::Transaction::TransactionOutput.new(
        satoshis: 4000,
        locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160)
      )
    )

    beef = BSV::Transaction::Beef.new
    bump_idx = beef.merge_bump(merkle_path)
    beef.transactions << BSV::Transaction::Beef::BeefTx.new(
      format: BSV::Transaction::Beef::FORMAT_RAW_TX_AND_BUMP,
      transaction: source_tx,
      bump_index: bump_idx
    )
    beef.transactions << BSV::Transaction::Beef::BeefTx.new(
      format: BSV::Transaction::Beef::FORMAT_RAW_TX,
      transaction: subject_tx
    )

    beef.to_binary
  end
  let(:subject_txid) do
    beef = BSV::Transaction::Beef.from_binary(beef_for_internalize)
    beef.transactions.last.transaction.txid_hex
  end
  let(:internalize_args) do
    {
      tx: beef_for_internalize.unpack('C*'),
      description: 'payment from sender',
      outputs: [
        {
          output_index: 0,
          protocol: 'basket insertion',
          insertion_remittance: { basket: 'inbound payments' }
        }
      ]
    }
  end
  let(:storage) { store }
  let(:broadcaster) { double('broadcaster') }
  let(:wallet) { BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster, allow_memory_store: true) }

  before do
    allow(broadcaster).to receive(:broadcast).and_return(
      BSV::Network::BroadcastResponse.new(txid: 'stub', tx_status: 'SEEN_ON_NETWORK')
    )
  end

  describe 'internalize_action' do
    it 'stores the merkle proof from the BEEF' do
      wallet.internalize_action(internalize_args)

      proof = wallet.proof_store.resolve_proof(source_tx.txid_hex)
      expect(proof).to be_a(BSV::Transaction::MerklePath)
      expect(proof.block_height).to eq(800_000)
      expect(proof.to_hex).to eq(merkle_path.to_hex)
    end
  end

  describe 'create_action spending an internalised output' do
    before { wallet.internalize_action(internalize_args) }

    it 'produces valid BEEF (with BUMP) when spending the internalised output' do
      outpoint = "#{subject_txid}.0"

      result = wallet.create_action({
                                      description: 'spend internalised output',
                                      inputs: [
                                        {
                                          outpoint: outpoint,
                                          input_description: 'from basket',
                                          unlocking_script: BSV::Script::Script.new.to_hex
                                        }
                                      ],
                                      outputs: [
                                        {
                                          locking_script: BSV::Script::Script.p2pkh_lock(pub_key.hash160).to_hex,
                                          satoshis: 3000,
                                          output_description: 'change output'
                                        }
                                      ]
                                    })

      beef = BSV::Transaction::Beef.from_binary(result[:tx].pack('C*'))
      expect(beef.valid?).to be true
    end
  end
end

# ---------------------------------------------------------------------------
# wallet local pool
# ---------------------------------------------------------------------------
RSpec.shared_examples 'wallet local pool' do
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
    let(:replenisher) { double('replenisher', signal: nil, stop: nil) }

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
      replenisher = double('replenisher', signal: nil, stop: nil)
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
      replenisher = double('replenisher', stop: nil)
      pool.replenisher = replenisher
      pool.shutdown
      expect(replenisher).to have_received(:stop)
    end
  end

  # -----------------------------------------------------------------------
  # Concurrent acquire (barrier pattern)
  # -----------------------------------------------------------------------

  describe 'concurrent acquire' do
    # FileStore uses a per-store mutex but shares a single .tmp file path across threads,
    # making the atomic write pattern unsafe under concurrent load. Concurrent tests are
    # MemoryStore-only.
    before { skip 'FileStore is not thread-safe for concurrent writes (see #613)' if defined?(store_label) && store_label == 'FileStore' }

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
  # Client#utxo_pool factory integration
  # -----------------------------------------------------------------------

  describe 'Client#utxo_pool factory' do
    let(:private_key) { BSV::Primitives::PrivateKey.generate }
    let(:storage)     { store }
    let(:broadcaster) { double('broadcaster') }
    let(:wallet) do
      BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster, allow_memory_store: true)
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

# ---------------------------------------------------------------------------
# wallet replenishment worker
# ---------------------------------------------------------------------------
RSpec.shared_examples 'wallet replenishment worker' do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:broadcaster) { double('broadcaster') }
  let(:wallet) do
    BSV::Wallet::Client.new(private_key, storage: store, broadcaster: broadcaster, allow_memory_store: true)
  end

  before do
    allow(broadcaster).to receive(:broadcast).and_return(
      BSV::Network::BroadcastResponse.new(txid: 'stub', tx_status: 'SEEN_ON_NETWORK')
    )
  end

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

# ---------------------------------------------------------------------------
# wallet local proof store
# ---------------------------------------------------------------------------
RSpec.shared_examples 'wallet local proof store' do
  let(:storage) { store }
  let(:proof_store) { BSV::Wallet::LocalProofStore.new(storage) }

  let(:txid_bytes) { ("\xAB" * 32).b }
  let(:sibling_bytes) { ("\xCD" * 32).b }
  let(:merkle_path) do
    tx_elem = BSV::Transaction::MerklePath::PathElement.new(
      offset: 0, hash: txid_bytes, txid: true
    )
    sibling_elem = BSV::Transaction::MerklePath::PathElement.new(
      offset: 1, hash: sibling_bytes
    )
    BSV::Transaction::MerklePath.new(block_height: 800_000, path: [[tx_elem, sibling_elem]])
  end
  let(:txid_hex) { 'abcdef1234567890' * 4 }

  it 'includes ProofStore' do
    expect(BSV::Wallet::LocalProofStore.ancestors).to include(BSV::Wallet::Interface::ProofStore)
  end

  describe '#store_proof / #resolve_proof round-trip' do
    it 'returns an equivalent MerklePath after storing' do
      proof_store.store_proof(txid_hex, merkle_path)
      resolved = proof_store.resolve_proof(txid_hex)

      expect(resolved).to be_a(BSV::Transaction::MerklePath)
      expect(resolved.block_height).to eq(merkle_path.block_height)
      expect(resolved.to_hex).to eq(merkle_path.to_hex)
    end
  end

  describe '#resolve_proof' do
    it 'returns nil for an unknown txid' do
      expect(proof_store.resolve_proof('deadbeef' * 8)).to be_nil
    end

    it 'stores the proof as hex in the underlying storage adapter' do
      proof_store.store_proof(txid_hex, merkle_path)
      expect(storage.find_proof(txid_hex)).to eq(merkle_path.to_hex)
    end
  end
end

# ---------------------------------------------------------------------------
# wallet inline broadcast queue
# ---------------------------------------------------------------------------
RSpec.shared_examples 'wallet inline broadcast queue' do
  let(:storage)     { store }
  let(:broadcaster) { double('broadcaster') }

  # --------------------------------------------------------------------------
  # Shared seeding helpers
  # --------------------------------------------------------------------------

  # Seeds a spendable output and returns its outpoint string.
  def seed_output(s, outpoint:, satoshis: 1_000)
    s.store_output(
      outpoint: outpoint,
      satoshis: satoshis,
      state: :spendable,
      basket: 'default'
    )
    outpoint
  end

  # Seeds a pending output (locked as input) and returns its outpoint string.
  def seed_pending_output(s, outpoint:, satoshis: 1_000, fund_ref: 'ref-001')
    s.store_output(
      outpoint: outpoint,
      satoshis: satoshis,
      state: :pending,
      basket: 'default',
      pending_reference: fund_ref
    )
    outpoint
  end

  # Seeds a pending change output and returns its outpoint string.
  def seed_change_output(s, outpoint:, satoshis: 500)
    s.store_output(
      outpoint: outpoint,
      satoshis: satoshis,
      state: :pending,
      basket: 'default'
    )
    outpoint
  end

  # Seeds an action in 'signed' state and returns the txid.
  def seed_action(s, txid:, status: 'signed')
    s.store_action(txid: txid, description: 'test action', status: status)
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
    let(:queue)  { BSV::Wallet::BroadcastQueue::Inline.new(storage: storage, broadcaster: broadcaster) }
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

    # Post-HLR #455: 'unproven' until a merkle proof lands via internalize_action
    it 'updates action status to "unproven"' do
      result
      actions = storage.find_actions({ limit: 10, offset: 0 })
      action = actions.find { |a| a[:txid] == txid }
      expect(action[:status]).to eq('unproven')
    end
  end

  # --------------------------------------------------------------------------
  # 2. With broadcaster — broadcast fails
  # --------------------------------------------------------------------------
  describe 'with broadcaster, broadcast fails' do
    let(:queue)  { BSV::Wallet::BroadcastQueue::Inline.new(storage: storage, broadcaster: broadcaster) }
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
  # 3. Without broadcaster — raises WalletError (HLR #455: no silent fallback)
  # --------------------------------------------------------------------------
  describe 'without broadcaster, no accept_delayed_broadcast' do
    let(:queue) { BSV::Wallet::BroadcastQueue::Inline.new(storage: storage) }
    let(:payload) do
      build_payload(
        txid: txid,
        input_outpoints: ['in2:0'],
        change_outpoints: ['ch2:0'],
        fund_ref: 'ref-nb'
      )
    end
    let(:txid) { 'c' * 64 }

    before do
      seed_pending_output(storage, outpoint: 'in2:0', fund_ref: 'ref-nb')
      seed_change_output(storage, outpoint: 'ch2:0')
      seed_action(storage, txid: txid)
    end

    # Post-HLR #455: silent fallback to 'completed' removed; raises WalletError
    # unless accept_delayed_broadcast is explicitly set on the payload.
    it 'raises WalletError when accept_delayed_broadcast is false' do
      expect { queue.enqueue(payload) }.to raise_error(
        BSV::Wallet::WalletError,
        /accept_delayed_broadcast/
      )
    end
  end

  # --------------------------------------------------------------------------
  # 4. Without broadcaster + accept_delayed_broadcast
  # --------------------------------------------------------------------------
  describe 'without broadcaster, accept_delayed_broadcast: true' do
    let(:queue) { BSV::Wallet::BroadcastQueue::Inline.new(storage: storage) }
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
    let(:queue) { BSV::Wallet::BroadcastQueue::Inline.new(storage: storage, broadcaster: broadcaster) }
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

    # Post-HLR #455: 'unproven' until a merkle proof lands via internalize_action
    it 'updates action status to "unproven"' do
      result
      actions = storage.find_actions({ limit: 10, offset: 0 })
      action = actions.find { |a| a[:txid] == txid }
      expect(action[:status]).to eq('unproven')
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
    let(:queue) { BSV::Wallet::BroadcastQueue::Inline.new(storage: storage, broadcaster: broadcaster) }
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
      queue = BSV::Wallet::BroadcastQueue::Inline.new(storage: storage)
      expect(queue.async?).to be(false)
    end
  end

  # --------------------------------------------------------------------------
  # 8. #status — delegates to storage
  # --------------------------------------------------------------------------
  describe '#status' do
    let(:queue) { BSV::Wallet::BroadcastQueue::Inline.new(storage: storage) }
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
