# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::LocalProofStore do
  let(:storage) { BSV::Wallet::Store::Memory.new }
  let(:store) { described_class.new(storage) }

  # Build a minimal two-leaf merkle path (one txid leaf + one sibling).
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
    expect(described_class.ancestors).to include(BSV::Wallet::Interface::ProofStore)
  end

  describe '#store_proof / #resolve_proof round-trip' do
    it 'returns an equivalent MerklePath after storing' do
      store.store_proof(txid_hex, merkle_path)
      resolved = store.resolve_proof(txid_hex)

      expect(resolved).to be_a(BSV::Transaction::MerklePath)
      expect(resolved.block_height).to eq(merkle_path.block_height)
      expect(resolved.to_hex).to eq(merkle_path.to_hex)
    end
  end

  describe '#resolve_proof' do
    it 'returns nil for an unknown txid' do
      expect(store.resolve_proof('deadbeef' * 8)).to be_nil
    end

    it 'stores the proof as hex in the underlying storage adapter' do
      store.store_proof(txid_hex, merkle_path)
      expect(storage.find_proof(txid_hex)).to eq(merkle_path.to_hex)
    end
  end
end
