# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe 'WalletClient P2PKH template signing' do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:template) { BSV::Transaction::P2PKH.new(private_key) }
  let(:result) do
    wallet.create_action({
                           description: 'P2PKH template signing test',
                           inputs: [{
                             outpoint: source_outpoint,
                             unlocking_script: template,
                             input_description: 'spend tracked P2PKH output'
                           }],
                           outputs: [{
                             locking_script: locking_script_hex,
                             satoshis: 4000,
                             output_description: 'payment output'
                           }]
                         })
  end
  let(:pub_key) { private_key.public_key }
  let(:storage) { BSV::Wallet::MemoryStore.new }
  let(:wallet) { BSV::Wallet::WalletClient.new(private_key, storage: storage) }

  # P2PKH locking script for the wallet's own public key
  let(:locking_script) { BSV::Script::Script.p2pkh_lock(pub_key.hash160) }
  let(:locking_script_hex) { locking_script.to_hex }

  # A real source transaction (needed to produce valid hex for BEEF ancestry)
  let(:source_tx) do
    tx = BSV::Transaction::Transaction.new
    tx.add_output(BSV::Transaction::TransactionOutput.new(
                    satoshis: source_satoshis,
                    locking_script: locking_script
                  ))
    tx
  end
  let(:source_tx_hex) { source_tx.to_hex }
  let(:source_txid) { source_tx.txid_hex }
  let(:source_outpoint) { "#{source_txid}.0" }
  let(:source_satoshis) { 5000 }

  before do
    storage.store_output({
                           outpoint: source_outpoint,
                           satoshis: source_satoshis,
                           locking_script: locking_script_hex,
                           basket: 'test-basket',
                           tags: [],
                           spendable: true,
                           source_tx_hex: source_tx_hex
                         })
  end

  # --- Gap 1: UnlockingScriptTemplate is accepted ---

  describe 'Gap 1: build_inputs accepts UnlockingScriptTemplate objects' do
    it 'does not raise when an UnlockingScriptTemplate is given as unlocking_script' do
      expect { result }.not_to raise_error
    end

    it 'returns a finalised result (not a signable_transaction)' do
      expect(result).not_to have_key(:signable_transaction)
      expect(result[:txid]).to be_a(String)
    end
  end

  # --- Gap 2: source data wired from storage ---

  describe 'Gap 2: wire_source_from_storage populates source data' do
    it 'produces a valid txid (sign_all requires source_satoshis and source_locking_script)' do
      # If source data were missing, sign_all / sighash would raise ArgumentError.
      # A valid 64-char hex txid confirms the transaction was signed successfully.
      expect(result[:txid]).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  # --- Gap 3: finalize_action calls sign_all ---

  describe 'Gap 3: finalize_action resolves templates via sign_all' do
    it 'returns a byte-array BEEF payload' do
      expect(result[:tx]).to be_a(Array)
      expect(result[:tx]).to all(be_a(Integer))
    end

    it 'produces a signed transaction that verifies the P2PKH script' do
      beef_binary = result[:tx].pack('C*')
      beef = BSV::Transaction::Beef.from_binary(beef_binary)
      tx = beef.transactions.last.transaction

      # Source transaction is now included in the BEEF; wire it for verification
      input = tx.inputs.first
      input.source_satoshis = source_satoshis
      input.source_locking_script = locking_script

      expect(tx.verify_input(0)).to be true
    end
  end

  # --- Gap 4: BEEF contains parent transactions via source_tx_hex ---

  describe 'Gap 4: to_beef includes ancestor transactions from source_transaction' do
    it 'produces a BEEF with more than one transaction entry' do
      beef_binary = result[:tx].pack('C*')
      beef = BSV::Transaction::Beef.from_binary(beef_binary)
      tx_entries = beef.transactions.select(&:transaction)
      expect(tx_entries.length).to be > 1
    end

    it 'includes the source transaction as a BEEF ancestor' do
      beef_binary = result[:tx].pack('C*')
      beef = BSV::Transaction::Beef.from_binary(beef_binary)
      txids = beef.transactions.select(&:transaction).map { |bt| bt.transaction.txid_hex }
      expect(txids).to include(source_txid)
    end

    it 'wire_source_from_storage sets source_transaction on the input' do
      # Verify by checking the BEEF contains the ancestor rather than inspecting internals
      beef_binary = result[:tx].pack('C*')
      beef = BSV::Transaction::Beef.from_binary(beef_binary)
      subject_tx = beef.transactions.last.transaction
      expect(subject_tx.inputs.first.source_transaction).not_to be_nil
    end
  end
end
