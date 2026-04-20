# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe 'Proof round-trip: internalize_action → create_action → valid BEEF' do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  # Build a minimal source transaction (coin we're receiving).
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
  # Build a simple merkle proof for the source transaction.
  # Level 0 leaf hashes are in internal byte order (reverse of display
  # order), matching the BRC-74 wire format and compute_root lookup.
  let(:merkle_path) do
    txid_bytes = source_tx.txid.reverse # display → internal byte order
    sibling = ("\xCD" * 32).b
    tx_elem = BSV::Transaction::MerklePath::PathElement.new(
      offset: 0, hash: txid_bytes, txid: true
    )
    sibling_elem = BSV::Transaction::MerklePath::PathElement.new(
      offset: 1, hash: sibling
    )
    BSV::Transaction::MerklePath.new(block_height: 800_000, path: [[tx_elem, sibling_elem]])
  end
  # Attach the proof to the source tx, then build a BEEF that carries it.
  let(:beef_for_internalize) do
    source_tx.merkle_path = merkle_path

    # Build a "subject" transaction that we're internalising (spends the source).
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

    # Assemble BEEF manually: BUMP + source tx (proven) + subject tx (raw).
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
    # Parse the BEEF to retrieve the subject transaction's txid.
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
  let(:pub_key) { private_key.public_key }
  let(:storage) { BSV::Wallet::MemoryStore.new }
  # Post-HLR #455: broadcaster required; create_action raises without one.
  let(:broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles
  let(:wallet) { BSV::Wallet::WalletClient.new(private_key, storage: storage, broadcaster: broadcaster) }

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
