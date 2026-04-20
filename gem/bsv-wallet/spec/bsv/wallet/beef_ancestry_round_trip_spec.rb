# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

# End-to-end round-trip spec for HLR #466.
#
# Exercises the full lifecycle:
#   1. Build a synthetic 2-generation BEEF (grandparent confirmed, parent raw).
#   2. internalize_action — wallet stores the BEEF contents (subject output + ancestors).
#   3. create_action — spend the internalised output; wallet builds a new tx with ancestry.
#   4. Mocked ARC accepts the broadcast by calling tx.to_ef_hex — proves EF serialises.
#
# The spec fails intentionally when Tasks 1 or 2 are absent:
#   - Without Task 1 (to_ef fallback): to_ef_hex raises because source data is missing.
#   - Without Task 2 (from_beef wiring): ancestry is not wired, source_transaction is nil,
#     and to_ef_hex raises for the same reason.
RSpec.describe 'BEEF ancestry round-trip (HLR #466)' do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:pub_key) { private_key.public_key }
  let(:storage) { BSV::Wallet::MemoryStore.new }
  let(:broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles
  let(:wallet) do
    BSV::Wallet::Client.new(private_key, storage: storage, broadcaster: broadcaster)
  end

  # -------------------------------------------------------------------------
  # BEEF construction helpers
  # -------------------------------------------------------------------------

  # Grandparent transaction — confirmed on-chain (has a merkle proof).
  # Outputs a simple coin; the parent tx will spend it.
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

  # Merkle proof for the grandparent tx (simulated, structurally valid).
  let(:grandparent_merkle_path) do
    txid_bytes = grandparent_tx.txid.reverse # display → internal byte order
    sibling    = ("\xAB" * 32).b
    tx_elem      = BSV::Transaction::MerklePath::PathElement.new(
      offset: 0, hash: txid_bytes, txid: true
    )
    sibling_elem = BSV::Transaction::MerklePath::PathElement.new(
      offset: 1, hash: sibling
    )
    BSV::Transaction::MerklePath.new(block_height: 850_000, path: [[tx_elem, sibling_elem]])
  end

  # Parent transaction — raw only (no BUMP).  Spends the grandparent output
  # and creates an output that the subject tx will spend.
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

  # Subject transaction — the payment arriving at the wallet.
  # Spends the parent output and creates a wallet-addressable output.
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

  # Assemble a 2-generation BEEF:
  #   grandparent (FORMAT_RAW_TX_AND_BUMP) → parent (FORMAT_RAW_TX) → subject (FORMAT_RAW_TX)
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

  # -------------------------------------------------------------------------
  # Happy path
  # -------------------------------------------------------------------------

  context 'with a correctly wired BEEF' do
    # broadcasted_txs collects every tx object passed to broadcaster.broadcast
    # so examples can assert on EF serialisation after the fact.
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
      # EF marker: 4-byte version + 6-byte marker (00 00 00 00 00 EF).
      # This call raises ArgumentError if ancestry is not wired — that is the fix under test.
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
      # The new tx's immediate parent (subject_tx) must be present in the new BEEF.
      expect(tx_txids).to include(subject_txid)
    end
  end

  # -------------------------------------------------------------------------
  # Sanity check — regression defence
  #
  # Verify the test genuinely exercises the fix: when source_transaction is
  # stripped from inputs before broadcasting, to_ef_hex raises ArgumentError.
  # -------------------------------------------------------------------------

  context 'when ancestry is stripped (regression defence)' do
    it 'to_ef_hex raises ArgumentError when source_transaction is not wired' do
      wallet.internalize_action(internalize_args)

      # Build the spending tx manually without wiring ancestry.
      bare_input = BSV::Transaction::TransactionInput.new(
        prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(subject_txid),
        prev_tx_out_index: 0,
        unlocking_script: BSV::Script::Script.new
      )
      # Explicitly do NOT set source_satoshis, source_locking_script, or source_transaction.
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

  # -------------------------------------------------------------------------
  # Edge case — parent unproven (raw only)
  #
  # The parent tx has no BUMP — only a raw tx entry.  EF must still serialise
  # because source data is derivable from the wired source_transaction chain.
  # -------------------------------------------------------------------------

  context 'with parent tx unproven (raw only, no BUMP)' do
    let(:broadcasted_txs) { [] }

    before do
      allow(broadcaster).to receive(:broadcast) do |tx|
        broadcasted_txs << tx
        BSV::Network::BroadcastResponse.new(txid: tx.txid_hex, tx_status: 'SEEN_ON_NETWORK')
      end
    end

    it 'EF serialises when immediate parent has no BUMP' do
      # The incoming_beef_binary already has subject_tx and parent_tx as raw-only
      # (no BUMP); only grandparent has a proof.  This is exactly the edge case.
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
      # EF marker check — raises if ancestry not wired (parent unproven edge case).
      ef_hex = broadcasted_txs.last.to_ef_hex
      ef_bytes = [ef_hex].pack('H*')
      expect(ef_bytes.byteslice(4, 6)).to eq("\x00\x00\x00\x00\x00\xEF".b)
    end
  end
end
