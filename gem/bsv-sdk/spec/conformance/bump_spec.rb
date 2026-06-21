# frozen_string_literal: true

require 'spec_helper'

# Protocol conformance: BUMP (BRC-74 BSV Unified Merkle Path) parsing
#
# Vectors loaded directly from the canonical ts-stack corpus via
# ConformanceVectors.each_canonical_vector. All `bump_hex`, `txid`, and
# `expected.merkle_root` values come from the pinned upstream — bumping
# the corpus SHA (via bin/conformance/sync) will exercise updated data.
#
#   sdk/transactions/merkle-path.json       (17 vectors: parse, serialize,
#                                            computeroot, compound, coinbase,
#                                            findleaf, extract, block125632)
#   regressions/merkle-path-odd-node.json   (5 merkle_tree_parent steps for
#                                            the 5-leaf odd-node tree)
#
# See spec/conformance/vectors/README.md for provenance notes.

RSpec.describe 'sdk.transactions.merklepath' do
  subject(:mp_class) { BSV::Transaction::MerklePath }

  # Index canonical vectors by id (memoised) so each `it` can grab its own
  # fixture without re-iterating the envelope.
  def self.canonical_vectors_by_id
    @canonical_vectors_by_id ||= {}.tap do |index|
      ConformanceVectors.each_canonical_vector('sdk.transactions.merkle-path') do |_env, v|
        index[v['id']] = v
      end
    end
  end

  let(:vectors) { self.class.canonical_vectors_by_id }

  # Build a minimal single-leaf MerklePath from a pre-computed sibling hash list
  # (leaf-to-root order, one sibling hash per tree level above the txid).
  def build_single_leaf_proof(block_height:, dtxid:, index:, sibling_hashes:)
    wtxid = [dtxid].pack('H*').reverse
    leaf = BSV::Transaction::MerklePath::PathElement

    level0 = [
      leaf.new(offset: index, hash: wtxid, txid: true),
      leaf.new(offset: index ^ 1, hash: sibling_hashes[0])
    ].sort_by(&:offset)

    upper = sibling_hashes[1..].each_with_index.map do |sibling_hash, i|
      height = i + 1
      [leaf.new(offset: (index >> height) ^ 1, hash: sibling_hash)]
    end

    BSV::Transaction::MerklePath.new(block_height: block_height, path: [level0] + upper)
  end

  # Walk the full Merkle tree of dtxid hex strings (display order) and return
  # the sibling hashes for `target_index` in leaf-to-root order. Uses the
  # Bitcoin duplicate rule for odd-count levels.
  def merkle_siblings_for(dtxids, target_index)
    current = dtxids.map { |d| [d].pack('H*').reverse }
    siblings = []
    idx = target_index

    while current.length > 1
      sibling_offset = idx ^ 1
      siblings << (current[sibling_offset] || current[idx])
      next_level = []
      i = 0
      while i < current.length
        left = current[i]
        right = current[i + 1] || current[i]
        next_level << BSV::Transaction::MerklePath.merkle_tree_parent(left, right)
        i += 2
      end
      current = next_level
      idx >>= 1
    end

    siblings
  end

  describe 'mp-parse-001 — parse BRC-74 BUMP: block height 813706, 3 txids, 12 levels' do
    it 'parses to the correct block height, level count, and level-0 leaf count' do
      mp = mp_class.from_hex(vectors.fetch('mp-parse-001').dig('input', 'bump_hex'))
      expect(mp.block_height).to eq(813_706)
      expect(mp.path.length).to eq(12)
      expect(mp.path[0].length).to eq(4)
    end
  end

  describe 'mp-serialize-001 — serialise MerklePath back to original hex' do
    it 'round-trips through from_hex / to_hex unchanged' do
      bump_hex = vectors.fetch('mp-serialize-001').dig('input', 'bump_hex')
      mp = mp_class.from_hex(bump_hex)
      expect(mp.to_hex).to eq(bump_hex)
    end
  end

  describe 'mp-computeroot-001/002/003 — computeRoot returns known merkle root for block 813706' do
    %w[mp-computeroot-001 mp-computeroot-002 mp-computeroot-003].each do |id|
      it "#{id}: txid yields the expected merkle root" do
        v = vectors.fetch(id)
        mp = mp_class.from_hex(v.dig('input', 'bump_hex'))
        expect(mp.compute_root_hex(v.dig('input', 'txid'))).to eq(v.dig('expected', 'merkle_root'))
      end
    end
  end

  describe 'mp-single-tx-001 — single-transaction block: merkle root equals the sole txid' do
    let(:v) { vectors.fetch('mp-single-tx-001') }
    let(:mp) { mp_class.from_hex(v.dig('input', 'bump_hex')) }

    it 'parses to the canonical block height' do
      expect(mp.block_height).to eq(v.dig('expected', 'block_height'))
    end

    it 'computeRoot returns the txid itself (single-tx block)' do
      expect(mp.compute_root_hex(v.dig('input', 'txid'))).to eq(v.dig('expected', 'merkle_root'))
    end
  end

  describe 'mp-compound-001 — compound path from 4 txids at level 0' do
    let(:v) { vectors.fetch('mp-compound-001') }
    let(:mp) { mp_class.from_hex(v.dig('input', 'bump_hex')) }

    it 'serialises back to the canonical bump hex' do
      expect(mp.to_hex).to eq(v.dig('expected', 'serialized_bump_hex'))
    end

    it 'computeRoot returns the same root for all 4 txids' do
      v.dig('input', 'txids_at_level_0').each_with_index do |txid, i|
        expect(mp.compute_root_hex(txid)).to eq(v.dig('expected', "merkle_root_for_tx#{i}"))
      end
    end
  end

  describe 'mp-coinbase-001 — single-tx BUMP at coinbase offset (fromCoinbaseTxidAndHeight equivalent)' do
    # Ruby does not expose fromCoinbaseTxidAndHeight; the equivalent is constructing
    # a single PathElement at offset 0. This test verifies that construction produces
    # the canonical BRC-74 hex and merkle root from upstream.
    let(:v) { vectors.fetch('mp-coinbase-001') }
    let(:mp) do
      wtxid = [v.dig('input', 'txid')].pack('H*').reverse
      leaf = BSV::Transaction::MerklePath::PathElement.new(offset: 0, hash: wtxid, txid: true)
      BSV::Transaction::MerklePath.new(block_height: v.dig('input', 'height'), path: [[leaf]])
    end

    it 'serialises to the canonical BUMP hex' do
      expect(mp.to_hex).to eq(v.dig('expected', 'bump_hex'))
    end

    it 'block height matches the canonical expected value' do
      expect(mp.block_height).to eq(v.dig('expected', 'block_height'))
    end

    it 'computeRoot returns the txid (single-tx block merkle root equals txid)' do
      expect(mp.compute_root_hex(v.dig('input', 'txid'))).to eq(v.dig('expected', 'merkle_root'))
    end
  end

  describe 'mp-block125632-001 — full-block compound path from 11-tx block 125632' do
    let(:v) { vectors.fetch('mp-block125632-001') }

    it 'computeRoot from each txid single-leaf proof yields the block merkle root' do
      txids = v.dig('input', 'txids')
      expected_root = v.dig('expected', 'merkle_root')
      txids.each_with_index do |dtxid, i|
        siblings = merkle_siblings_for(txids, i)
        mp = build_single_leaf_proof(
          block_height: v.dig('input', 'block_height'),
          dtxid: dtxid, index: i, sibling_hashes: siblings
        )
        expect(mp.compute_root_hex(dtxid)).to eq(expected_root)
      end
    end
  end

  describe 'mp-block125632-002 — per-txid proof for tx[2] computes correct merkle root' do
    # Needs the full block's txid list to build sibling hashes — source from mp-block125632-001.
    let(:v) { vectors.fetch('mp-block125632-002') }
    let(:full_block_txids) { vectors.fetch('mp-block125632-001').dig('input', 'txids') }

    it 'computeRoot returns the block 125632 merkle root' do
      txid = v.dig('input', 'txid')
      siblings = merkle_siblings_for(full_block_txids, full_block_txids.index(txid))
      mp = build_single_leaf_proof(
        block_height: v.dig('input', 'block_height'),
        dtxid: txid, index: full_block_txids.index(txid), sibling_hashes: siblings
      )
      expect(mp.compute_root_hex(txid)).to eq(v.dig('expected', 'merkle_root'))
    end
  end

  describe 'mp-block125632-003 — per-txid proof for tx[8] exercises odd-level duplication' do
    let(:v) { vectors.fetch('mp-block125632-003') }
    let(:full_block_txids) { vectors.fetch('mp-block125632-001').dig('input', 'txids') }

    it 'computeRoot handles the odd-level duplicate propagation and returns the correct root' do
      txid = v.dig('input', 'txid')
      index = full_block_txids.index(txid)
      siblings = merkle_siblings_for(full_block_txids, index)
      mp = build_single_leaf_proof(
        block_height: v.dig('input', 'block_height'),
        dtxid: txid, index: index, sibling_hashes: siblings
      )
      expect(mp.compute_root_hex(txid)).to eq(v.dig('expected', 'merkle_root'))
    end
  end

  describe 'mp-combine-001 — combined compound path of 3 txids in block 125632' do
    let(:v) { vectors.fetch('mp-combine-001') }
    let(:mp) { mp_class.from_hex(v.dig('input', 'combined_bump_hex')) }
    let(:expected_root) { v.dig('expected', 'merkle_root') }

    it 'serialises back to the canonical combined hex' do
      expect(mp.to_hex).to eq(v.dig('expected', 'serialized_bump_hex'))
    end

    %w[txid_tx2 txid_tx5 txid_tx8].each do |key|
      it "computeRoot for input.#{key} returns the correct merkle root" do
        expect(mp.compute_root_hex(v.dig('input', key))).to eq(expected_root)
      end
    end
  end

  describe 'mp-findleaf-001 — hash256(leaf0 || leaf0) when duplicate=true overrides sibling' do
    # The TS SDK's findOrComputeLeaf is an internal tree-walk helper that returns
    # hash256(leaf || leaf) when the sibling has duplicate=true. Ruby exposes the
    # same primitive as MerklePath.merkle_tree_parent. The canonical expected
    # value is in display (reversed) byte order.
    let(:v) { vectors.fetch('mp-findleaf-001') }

    it 'hash256(leaf0 || leaf0) in display byte order equals the expected hash' do
      leaf0 = [v.dig('input', 'leaf0_hash')].pack('H*')
      result_wire = BSV::Transaction::MerklePath.merkle_tree_parent(leaf0, leaf0)
      expect(result_wire.reverse.unpack1('H*')).to eq(v.dig('expected', 'computed_hash'))
    end
  end

  describe 'mp-extract-001 — extract() a single txid proof from a compound path' do
    let(:v) { vectors.fetch('mp-extract-001') }
    let(:combined_v) { vectors.fetch('mp-combine-001') }
    let(:mp) { mp_class.from_hex(combined_v.dig('input', 'combined_bump_hex')) }
    let(:extract_dtxid) { v.dig('input', 'extract_txid') }
    let(:extract_wtxid) { [extract_dtxid].pack('H*').reverse }

    it 'extracted path computes the canonical merkle root' do
      extracted = mp.extract([extract_wtxid])
      expect(extracted.compute_root_hex(extract_dtxid)).to eq(v.dig('expected', 'merkle_root'))
    end

    it 'extracted path is smaller than the source compound path' do
      expect(v.dig('expected', 'extracted_smaller_than_full')).to be true
      extracted = mp.extract([extract_wtxid])
      expect(extracted.to_hex.length).to be < mp.to_hex.length
    end
  end

  describe 'mp-extract-002 — extract() raises ArgumentError for an empty txid list' do
    let(:combined_v) { vectors.fetch('mp-combine-001') }
    let(:mp) { mp_class.from_hex(combined_v.dig('input', 'combined_bump_hex')) }

    it 'raises ArgumentError' do
      expect { mp.extract([]) }.to raise_error(ArgumentError)
    end
  end

  describe 'mp-extract-003 — extract() raises ArgumentError for a txid not in the path' do
    let(:v) { vectors.fetch('mp-extract-003') }
    let(:combined_v) { vectors.fetch('mp-combine-001') }
    let(:mp) { mp_class.from_hex(combined_v.dig('input', 'combined_bump_hex')) }

    it 'raises ArgumentError' do
      bad_wtxid = [v.dig('input', 'txid')].pack('H*').reverse
      expect { mp.extract([bad_wtxid]) }.to raise_error(ArgumentError)
    end
  end

  describe 'regressions/merkle-path-odd-node — MerkleTreeParent for 5-leaf tree' do
    # The odd-node regression verifies that MerkleTreeParent correctly propagates
    # duplicate nodes at intermediate levels (not just level 0). The go-sdk had a
    # bug prior to v1.2.18 where ComputeMissingHashes only duplicated at level 0.
    # Each canonical vector exercises one pair-and-hash step of the 5-leaf tree.

    odd_node_vectors = ConformanceVectors.canonical_regression('merkle-path-odd-node').fetch('vectors')

    odd_node_vectors.each do |v|
      it "#{v['id']}: #{v['description']}" do
        left = [v.dig('input', 'left_hex')].pack('H*')
        right = [v.dig('input', 'right_hex')].pack('H*')
        result = BSV::Transaction::MerklePath.merkle_tree_parent(left, right)
        expect(result.unpack1('H*')).to eq(v.dig('expected', 'parent_hex'))
      end
    end
  end
end
