# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe 'internalize_action BEEF chain tracker verification' do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:pub_key)     { private_key.public_key }
  let(:storage)     { BSV::Wallet::Store::Memory.new }

  # A simple source transaction with one output.
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

  # A minimal merkle proof for the source transaction.
  let(:merkle_path) do
    txid_bytes = source_tx.txid.reverse
    sibling    = ("\xCD" * 32).b
    tx_elem      = BSV::Transaction::MerklePath::PathElement.new(offset: 0, hash: txid_bytes, txid: true)
    sibling_elem = BSV::Transaction::MerklePath::PathElement.new(offset: 1, hash: sibling)
    BSV::Transaction::MerklePath.new(block_height: 800_000, path: [[tx_elem, sibling_elem]])
  end

  # Computed root hex (what a chain tracker would be asked to confirm).
  let(:root_hex) { merkle_path.compute_root.reverse.unpack1('H*') }

  # A valid BEEF carrying source_tx (proven) + subject_tx (raw).
  let(:beef_binary) do
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

  let(:internalize_args) do
    {
      tx: beef_binary.unpack('C*'),
      description: 'payment received',
      outputs: [
        {
          output_index: 0,
          protocol: 'basket insertion',
          insertion_remittance: { basket: 'inbound payments' }
        }
      ]
    }
  end

  def build_wallet(chain_data_source: nil)
    BSV::Wallet::Client.new(
      private_key,
      storage: storage,
      allow_memory_store: true,
      chain_data_source: chain_data_source
    )
  end

  describe 'without a chain_data_source' do
    it 'accepts valid BEEF using structural-only verification' do
      wallet = build_wallet

      expect { wallet.internalize_action(internalize_args) }.not_to raise_error
    end
  end

  describe 'with a chain_data_source that responds to valid_root_for_height?' do
    # Use a real object that genuinely responds to valid_root_for_height?
    # instead of stubbing respond_to?, which is brittle on Ruby 2.7 where
    # the two-arg form (symbol, include_private) causes mock mismatches.
    let(:accepting_tracker) do
      obj = Object.new
      def obj.valid_root_for_height?(_root, _height)
        true
      end
      obj
    end

    let(:rejecting_tracker) do
      obj = Object.new
      def obj.valid_root_for_height?(_root, _height)
        false
      end
      obj
    end

    it 'passes the chain_data_source to beef.verify' do
      wallet = build_wallet(chain_data_source: accepting_tracker)

      expect { wallet.internalize_action(internalize_args) }.not_to raise_error
    end

    it 'raises WalletError when the chain tracker rejects the merkle root' do
      wallet = build_wallet(chain_data_source: rejecting_tracker)

      expect { wallet.internalize_action(internalize_args) }
        .to raise_error(BSV::Wallet::WalletError, /merkle root not confirmed/)
    end
  end

  describe 'with a chain_data_source that does NOT respond to valid_root_for_height?' do
    it 'falls back to beef.verify(nil) — structural verification only' do
      chain_source = Object.new

      wallet = build_wallet(chain_data_source: chain_source)

      expect { wallet.internalize_action(internalize_args) }.not_to raise_error
    end
  end
end
