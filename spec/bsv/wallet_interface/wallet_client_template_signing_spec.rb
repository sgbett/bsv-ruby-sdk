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

  # A tracked source output stored directly in the MemoryStore
  let(:source_txid) { 'a' * 64 }
  let(:source_outpoint) { "#{source_txid}.0" }
  let(:source_satoshis) { 5000 }

  before do
    storage.store_output({
                           outpoint: source_outpoint,
                           satoshis: source_satoshis,
                           locking_script: locking_script_hex,
                           basket: 'test-basket',
                           tags: [],
                           spendable: true
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

      # Wire source data for verification (not present in BEEF for a 1-hop tx)
      tx.inputs.first.source_satoshis = source_satoshis
      tx.inputs.first.source_locking_script = locking_script

      expect(tx.verify_input(0)).to be true
    end
  end
end
