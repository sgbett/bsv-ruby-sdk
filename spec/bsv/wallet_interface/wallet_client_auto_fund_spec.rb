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

    it 'stores a change output as :spendable with no basket assignment' do
      result
      # Change outputs are not assigned to a basket — they are free-floating
      # spendable outputs identifiable only by their BRC-29 derivation metadata.
      change = storage.find_spendable_outputs.select { |o| o[:derivation_prefix] }
      expect(change).not_to be_empty
      expect(change.first[:satoshis]).to be_positive
      expect(change.first[:basket]).to be_nil
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
        expect(inp.unlocking_script.to_binary.bytesize).to be > 0
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

      # Change outputs have no basket assignment; query all spendable outputs.
      spendable = storage.find_spendable_outputs
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

      # At this point the original UTXO is spent; change is a free-floating
      # spendable output (no basket assignment) with BRC-29 derivation metadata.
      change = storage.find_spendable_outputs.select { |o| o[:derivation_prefix] }
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
end
