# frozen_string_literal: true

require 'spec_helper'

# Protocol conformance: BUMP (BRC-74 BSV Unified Merkle Path) parsing
#
# Vectors sourced from the canonical corpus:
#   sdk/transactions/merkle-path.json  (17 vectors)
#   regressions/merkle-path-odd-node.json  (5 vectors)
#
# See spec/conformance/vectors/README.md for provenance notes.

# Block 813706 BUMP used across mp-parse/serialize/computeroot vectors.
BUMP_HEX_813706 = 'fe8a6a0c000c04fde80b0011774f01d26412f0d16ea3f0447be0b5ebec67b0782e321a7a01cbdf7f734e30fde90b02' \
                  '004e53753e3fe4667073063a17987292cfdea278824e9888e52180581d7188d8fdea0b025e441996fc53f0191d649e68' \
                  'a200e752fb5f39e0d5617083408fa179ddc5c998fdeb0b0102fdf405000671394f72237d08a4277f4435e5b6edf7adc2' \
                  '72f25effef27cdfe805ce71a81fdf50500262bccabec6c4af3ed00cc7a7414edea9c5efa92fb8623dd6160a001450a52' \
                  '8201fdfb020101fd7c010093b3efca9b77ddec914f8effac691ecb54e2c81d0ab81cbc4c4b93befe418e8501bf01015e' \
                  '005881826eb6973c54003a02118fe270f03d46d02681c8bc71cd44c613e86302f8012e00e07a2bb8bb75e5accff26602' \
                  '2e1e5e6e7b4d6d943a04faadcf2ab4a22f796ff30116008120cafa17309c0bb0e0ffce835286b3a2dcae48e4497ae2d' \
                  '2b7ced4f051507d010a00502e59ac92f46543c23006bff855d96f5e648043f0fb87a7a5949e6a9bebae430104001ccd9' \
                  'f8f64f4d0489b30cc815351cf425e0e78ad79a589350e4341ac165dbe45010301010000af8764ce7e1cc132ab5ed2229' \
                  'a005c87201c9a5ee15c0f91dd53eff31ab30cd4'

# Block 125632 txids used across mp-block125632-* and mp-combine-001 vectors.
BLOCK125632_TXIDS = %w[
  17cba98da71fe75862aac894392f2ff604356db386767fec364877a5a9ff200c
  14ce64bd223ec9bb42662b74fdcf94f96a209a1aee72b7ba7639db503150ec2e
  90a2de85351cfadd2326b9b0098e9c453af09b2980835f57a1429bbb44beb872
  a31f2ddfea7ddd4581dca3007ee99e58ea6baa97a8ac3b32bb4610baac9f7206
  c36eeed6fbc0259d30804f59f804dfcda35a54461157d6ac9c094f0ea378f35c
  17752483868c52a98407a0e226d73b42e214e0fad548541619d858e1fd4a9549
  3b8c4460412cfc55be0d50308ba704a859bd6f83bfed01b0828c9b067cd69246
  a3f1b9d4b3ef3b061af352fdc2d02048417030fef9282c36da689cd899437cdb
  66e2b022da877621ef197e02c3ef7d3f820d33a86ead2e72bf966432ea6776f1
  e988b5d7a2cec8e0759ade2e151737d1cdfdde68accff42938583ad12eb98b99
  5e7a8a8ec3f912ac1c4e90279c04263f170ed055c0411c8d490b846f01e6a99e
].freeze

BLOCK125632_MERKLE_ROOT = '205b2e27c58601fc1a8de04c83b6b0c46f89c16b2161c93441b7e9269cf6bc4a'

# Combined compound BUMP for 3 txids in block 125632, used in mp-combine-001 and mp-extract-001.
BUMP_HEX_COMBINE_001 = 'fec0ea01000406020272b8be44bb9b42a1575f8380299bf03a459c8e09b0b92623ddfa1c3585dea2900' \
                       '30006729facba1046bb323baca897aa6bea589ee97e00a3dc8145dd7deadf2d1fa304005cf378a30e4f' \
                       '099cacd6571146545aa3cddf04f8594f80309d25c0fbd6ee6ec3050249954afde158d819165448d5fae' \
                       '014e2423bd726e2a00784a9528c86832475170802f17667ea326496bf722ead6ea8330d823f7defc3027' \
                       'e19ef217687da22b0e2660900998bb92ed13a583829f4cfac68defdcdd13717152ede9a75e0c8cea2d7b' \
                       '588e903000031c5d542872b0428110d960efec7abbcd940aaa3e31e32c080db58adf71885a70300fb71f0' \
                       '67fde6d8680c527d5bf95c3ad23816bd2d2876f8b250c7532a191dce15050056f0884ee1bd452bd4da1d' \
                       '07bb15e271b370065ac11bef56fe5cee8c2b12141101030100'

MERKLE_PATH_ODD_NODE_VECTORS = [
  {
    id: 'regression.merkle-path.odd-node.0001',
    description: '5 leaves: MerkleTreeParent of leaf0+leaf1',
    left: '0000000000000000000000000000000000000000000000000000000000000001',
    right: '0000000000000000000000000000000000000000000000000000000000000002',
    expected: '9b1eb2a9e9a81cbbad8edffa901e93fd94f4405e63b61647cf9d3e602b1fb7b0'
  },
  {
    id: 'regression.merkle-path.odd-node.0002',
    description: '5 leaves: MerkleTreeParent of leaf2+leaf3',
    left: '0000000000000000000000000000000000000000000000000000000000000003',
    right: '0000000000000000000000000000000000000000000000000000000000000004',
    expected: 'fd310e3f704ef2f8dea5f1ac83afc0465848b21dffd112959dbf21ad5e464b42'
  },
  {
    id: 'regression.merkle-path.odd-node.0003',
    description: '5 leaves: leaf4 duplicated to pair with itself (odd node at level 0)',
    left: '0000000000000000000000000000000000000000000000000000000000000005',
    right: '0000000000000000000000000000000000000000000000000000000000000005',
    expected: 'b4dcc47aee63daed12d1446b8bbfdc033ebf1f624a168644b0f0cd6bd0b1b460'
  },
  {
    id: 'regression.merkle-path.odd-node.0004',
    description: '5 leaves: h45 duplicated (odd node at level 1 propagates to level 2)',
    left: 'b4dcc47aee63daed12d1446b8bbfdc033ebf1f624a168644b0f0cd6bd0b1b460',
    right: 'b4dcc47aee63daed12d1446b8bbfdc033ebf1f624a168644b0f0cd6bd0b1b460',
    expected: '46a5e7bfc4bd43b356a838a8335ab0ebb4a7c6cdd1d9d623a4590196b0e6e904'
  },
  {
    id: 'regression.merkle-path.odd-node.0005',
    description: '5 leaves: Merkle root — h0123 paired with h4545',
    left: '2c76ecc1f6a379b82aadc24b14cded50e6b59693b02cee76342c15cf0e31b700',
    right: '46a5e7bfc4bd43b356a838a8335ab0ebb4a7c6cdd1d9d623a4590196b0e6e904',
    expected: 'f0bf455a6a0785a84110fcd82c82a6b025acbd0098685789317f6cd6fdc03817'
  }
].freeze

RSpec.describe 'sdk.transactions.merklepath' do
  subject(:mp_class) { BSV::Transaction::MerklePath }

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
      mp = mp_class.from_hex(BUMP_HEX_813706)
      expect(mp.block_height).to eq(813_706)
      expect(mp.path.length).to eq(12)
      expect(mp.path[0].length).to eq(4)
    end
  end

  describe 'mp-serialize-001 — serialise MerklePath back to original hex' do
    it 'round-trips through from_hex / to_hex unchanged' do
      mp = mp_class.from_hex(BUMP_HEX_813706)
      expect(mp.to_hex).to eq(BUMP_HEX_813706)
    end
  end

  describe 'mp-computeroot-001/002/003 — computeRoot returns known merkle root for block 813706' do
    let(:mp) { mp_class.from_hex(BUMP_HEX_813706) }
    let(:expected_root) { '57aab6e6fb1b697174ffb64e062c4728f2ffd33ddcfa02a43b64d8cd29b483b4' }

    it 'mp-computeroot-001: txid1 yields the known root' do
      expect(mp.compute_root_hex('304e737fdfcb017a1a322e78b067ecebb5e07b44f0a36ed1f01264d2014f7711')).to eq(expected_root)
    end

    it 'mp-computeroot-002: txid2 yields the same root' do
      expect(mp.compute_root_hex('d888711d588021e588984e8278a2decf927298173a06737066e43f3e75534e00')).to eq(expected_root)
    end

    it 'mp-computeroot-003: txid3 yields the same root' do
      expect(mp.compute_root_hex('98c9c5dd79a18f40837061d5e0395ffb52e700a2689e641d19f053fc9619445e')).to eq(expected_root)
    end
  end

  describe 'mp-single-tx-001 — single-transaction block: merkle root equals the sole txid' do
    let(:bump_hex) { 'fdd2040101000202ef57aa9f29c8141ae17935c88434457b2117890f23efba0d0e0cba7a7a37d5' }
    let(:txid) { 'd5377a7aba0c0e0dbaef230f8917217b453484c83579e11a14c8299faa57ef02' }
    let(:mp) { mp_class.from_hex(bump_hex) }

    it 'parses to block height 1234' do
      expect(mp.block_height).to eq(1234)
    end

    it 'computeRoot returns the txid itself (single-tx block)' do
      expect(mp.compute_root_hex(txid)).to eq(txid)
    end
  end

  describe 'mp-compound-001 — compound path from 4 txids at level 0' do
    let(:bump_hex) do
      '6401040002aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
        '0102bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
        '0202cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' \
        '0302dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
    end
    let(:txids) do
      %w[
        aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
        cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
        dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
      ]
    end
    let(:expected_root) { 'fd02fb9070e9f55fe8a7674be02515d3a61deabff94db50f3b519d516fb6e8ef' }
    let(:mp) { mp_class.from_hex(bump_hex) }

    it 'serialises back to the original hex' do
      expect(mp.to_hex).to eq(bump_hex)
    end

    it 'computeRoot returns the same root for all 4 txids' do
      txids.each do |txid|
        expect(mp.compute_root_hex(txid)).to eq(expected_root)
      end
    end
  end

  describe 'mp-coinbase-001 — single-tx BUMP at coinbase offset (fromCoinbaseTxidAndHeight equivalent)' do
    # Ruby does not expose fromCoinbaseTxidAndHeight; the equivalent is constructing
    # a single PathElement at offset 0. This test verifies that construction produces
    # the expected BRC-74 hex and a correct merkle root.
    let(:txid) { 'd5377a7aba0c0e0dbaef230f8917217b453484c83579e11a14c8299faa57ef02' }
    let(:height) { 1 }
    let(:expected_bump_hex) { '010101000202ef57aa9f29c8141ae17935c88434457b2117890f23efba0d0e0cba7a7a37d5' }
    let(:mp) do
      wtxid = [txid].pack('H*').reverse
      leaf = BSV::Transaction::MerklePath::PathElement.new(offset: 0, hash: wtxid, txid: true)
      BSV::Transaction::MerklePath.new(block_height: height, path: [[leaf]])
    end

    it 'serialises to the expected BUMP hex' do
      expect(mp.to_hex).to eq(expected_bump_hex)
    end

    it 'block height is 1' do
      expect(mp.block_height).to eq(height)
    end

    it 'computeRoot returns the txid (single-tx block merkle root equals txid)' do
      expect(mp.compute_root_hex(txid)).to eq(txid)
    end
  end

  describe 'mp-block125632-001 — full-block compound path from 11-tx block 125632' do
    let(:expected_root) { BLOCK125632_MERKLE_ROOT }

    it 'computeRoot from each txid single-leaf proof yields the block merkle root' do
      BLOCK125632_TXIDS.each_with_index do |dtxid, i|
        siblings = merkle_siblings_for(BLOCK125632_TXIDS, i)
        mp = build_single_leaf_proof(block_height: 125_632, dtxid: dtxid, index: i, sibling_hashes: siblings)
        expect(mp.compute_root_hex(dtxid)).to eq(expected_root)
      end
    end
  end

  describe 'mp-block125632-002 — per-txid proof for tx[2] computes correct merkle root' do
    let(:txid) { '90a2de85351cfadd2326b9b0098e9c453af09b2980835f57a1429bbb44beb872' }

    it 'computeRoot returns the block 125632 merkle root' do
      siblings = merkle_siblings_for(BLOCK125632_TXIDS, 2)
      mp = build_single_leaf_proof(block_height: 125_632, dtxid: txid, index: 2, sibling_hashes: siblings)
      expect(mp.compute_root_hex(txid)).to eq(BLOCK125632_MERKLE_ROOT)
    end
  end

  describe 'mp-block125632-003 — per-txid proof for tx[8] exercises odd-level duplication' do
    let(:txid) { '66e2b022da877621ef197e02c3ef7d3f820d33a86ead2e72bf966432ea6776f1' }

    it 'computeRoot handles the odd-level duplicate propagation and returns the correct root' do
      siblings = merkle_siblings_for(BLOCK125632_TXIDS, 8)
      mp = build_single_leaf_proof(block_height: 125_632, dtxid: txid, index: 8, sibling_hashes: siblings)
      expect(mp.compute_root_hex(txid)).to eq(BLOCK125632_MERKLE_ROOT)
    end
  end

  describe 'mp-combine-001 — combined compound path of 3 txids in block 125632' do
    let(:mp) { mp_class.from_hex(BUMP_HEX_COMBINE_001) }

    it 'serialises back to the original combined hex' do
      expect(mp.to_hex).to eq(BUMP_HEX_COMBINE_001)
    end

    it 'computeRoot for tx[2] returns the correct merkle root' do
      expect(mp.compute_root_hex('90a2de85351cfadd2326b9b0098e9c453af09b2980835f57a1429bbb44beb872'))
        .to eq(BLOCK125632_MERKLE_ROOT)
    end

    it 'computeRoot for tx[5] returns the correct merkle root' do
      expect(mp.compute_root_hex('17752483868c52a98407a0e226d73b42e214e0fad548541619d858e1fd4a9549'))
        .to eq(BLOCK125632_MERKLE_ROOT)
    end

    it 'computeRoot for tx[8] returns the correct merkle root' do
      expect(mp.compute_root_hex('66e2b022da877621ef197e02c3ef7d3f820d33a86ead2e72bf966432ea6776f1'))
        .to eq(BLOCK125632_MERKLE_ROOT)
    end
  end

  describe 'mp-findleaf-001 — hash256(leaf0 || leaf0) when duplicate=true overrides sibling' do
    # The TS SDK's findOrComputeLeaf is an internal tree-walk helper that returns
    # hash256(leaf || leaf) when the sibling has duplicate=true. Ruby exposes the
    # same primitive as MerklePath.merkle_tree_parent. The expected value in the
    # vector is in display (reversed) byte order.
    let(:leaf0_hex) { 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' }
    let(:expected_display_hex) { '57520342e8e855431fd5ee1e36dd9677a47f251a47222e1bfe195968776c88cd' }

    it 'hash256(leaf0 || leaf0) in display byte order equals the expected hash' do
      leaf0 = [leaf0_hex].pack('H*')
      result_wire = BSV::Transaction::MerklePath.merkle_tree_parent(leaf0, leaf0)
      expect(result_wire.reverse.unpack1('H*')).to eq(expected_display_hex)
    end
  end

  describe 'mp-extract-001 — extract() a single txid proof from a compound path' do
    let(:mp) { mp_class.from_hex(BUMP_HEX_COMBINE_001) }
    let(:extract_dtxid) { '90a2de85351cfadd2326b9b0098e9c453af09b2980835f57a1429bbb44beb872' }
    let(:extract_wtxid) { [extract_dtxid].pack('H*').reverse }

    it 'extracted path computes the correct merkle root' do
      extracted = mp.extract([extract_wtxid])
      expect(extracted.compute_root_hex(extract_dtxid)).to eq(BLOCK125632_MERKLE_ROOT)
    end

    it 'extracted path is smaller than the source compound path' do
      extracted = mp.extract([extract_wtxid])
      expect(extracted.to_hex.length).to be < mp.to_hex.length
    end
  end

  describe 'mp-extract-002 — extract() raises ArgumentError for an empty txid list' do
    let(:mp) { mp_class.from_hex(BUMP_HEX_COMBINE_001) }

    it 'raises ArgumentError' do
      expect { mp.extract([]) }.to raise_error(ArgumentError)
    end
  end

  describe 'mp-extract-003 — extract() raises ArgumentError for a txid not in the path' do
    let(:mp) { mp_class.from_hex(BUMP_HEX_COMBINE_001) }

    it 'raises ArgumentError' do
      bad_wtxid = ['deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef'].pack('H*').reverse
      expect { mp.extract([bad_wtxid]) }.to raise_error(ArgumentError)
    end
  end

  describe 'regressions/merkle-path-odd-node — MerkleTreeParent for 5-leaf tree' do
    # The odd-node regression verifies that MerkleTreeParent correctly propagates
    # duplicate nodes at intermediate levels (not just level 0). The go-sdk had a bug
    # prior to v1.2.18 where ComputeMissingHashes only duplicated at level 0.
    # merkle_tree_parent is a pure hash function; each vector independently exercises
    # one pair-and-hash step of the 5-leaf tree.

    MERKLE_PATH_ODD_NODE_VECTORS.each do |v|
      it "#{v[:id]}: #{v[:description]}" do
        left = [v[:left]].pack('H*')
        right = [v[:right]].pack('H*')
        result = BSV::Transaction::MerklePath.merkle_tree_parent(left, right)
        expect(result.unpack1('H*')).to eq(v[:expected])
      end
    end
  end
end
