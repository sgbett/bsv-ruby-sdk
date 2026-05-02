# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Transaction::MerklePath do
  # Go SDK test vector (BRC-74)
  let(:brc74_hex) do
    'fe8a6a0c000c04fde80b0011774f01d26412f0d16ea3f0447be0b5ebec67b0782e321a7a01cbdf7f734e30' \
      'fde90b02004e53753e3fe4667073063a17987292cfdea278824e9888e52180581d7188d8' \
      'fdea0b025e441996fc53f0191d649e68a200e752fb5f39e0d5617083408fa179ddc5c998' \
      'fdeb0b0102' \
      'fdf405000671394f72237d08a4277f4435e5b6edf7adc272f25effef27cdfe805ce71a81' \
      'fdf50500262bccabec6c4af3ed00cc7a7414edea9c5efa92fb8623dd6160a001450a5282' \
      '01fdfb020101' \
      'fd7c010093b3efca9b77ddec914f8effac691ecb54e2c81d0ab81cbc4c4b93befe418e85' \
      '01bf01015e005881826eb6973c54003a02118fe270f03d46d02681c8bc71cd44c613e86302f8' \
      '012e00e07a2bb8bb75e5accff266022e1e5e6e7b4d6d943a04faadcf2ab4a22f796ff3' \
      '0116008120cafa17309c0bb0e0ffce835286b3a2dcae48e4497ae2d2b7ced4f051507d' \
      '010a00502e59ac92f46543c23006bff855d96f5e648043f0fb87a7a5949e6a9bebae43' \
      '0104001ccd9f8f64f4d0489b30cc815351cf425e0e78ad79a589350e4341ac165dbe45' \
      '010301010000af8764ce7e1cc132ab5ed2229a005c87201c9a5ee15c0f91dd53eff31ab30cd4'
  end

  let(:expected_root_hex) { '57aab6e6fb1b697174ffb64e062c4728f2ffd33ddcfa02a43b64d8cd29b483b4' }

  describe '.merkle_tree_parent' do
    it 'matches the Go SDK test vector' do
      # Go SDK test values are display-order hex; reverse to internal byte order
      left = ['d6c79a6ef05572f0cb8e9a450c561fc40b0a8a7d48faad95e20d93ddeb08c231'].pack('H*').reverse
      right = ['b1ed931b79056438b990d8981ba46fae97e5574b142445a74a44b978af284f98'].pack('H*').reverse
      expected_display = 'b0d537b3ee52e472507f453df3d69561720346118a5a8c4d85ca0de73bc792be'

      result = described_class.merkle_tree_parent(left, right)
      expect(result.reverse.unpack1('H*')).to eq(expected_display)
    end
  end

  describe '.from_hex / #to_hex' do
    it 'round-trips the Go SDK BRC-74 vector' do
      mp = described_class.from_hex(brc74_hex)
      expect(mp.to_hex).to eq(brc74_hex)
    end
  end

  describe '.from_binary' do
    let(:mp) { described_class.from_hex(brc74_hex) }

    it 'parses the correct block height' do
      expect(mp.block_height).to eq(813_706)
    end

    it 'parses the correct number of levels' do
      expect(mp.path.length).to eq(12)
    end

    it 'parses level 0 with 4 leaves' do
      expect(mp.path[0].length).to eq(4)
    end

    it 'identifies the duplicate leaf' do
      dup_leaf = mp.path[0].find { |l| l.offset == 3051 }
      expect(dup_leaf.duplicate).to be true
      expect(dup_leaf.hash).to be_nil
    end

    it 'identifies txid-flagged leaves' do
      txid_offsets = mp.path[0].select(&:txid).map(&:offset)
      expect(txid_offsets).to contain_exactly(3049, 3050)
    end

    it 'returns the correct bytes consumed' do
      binary = [brc74_hex].pack('H*')
      _mp, consumed = described_class.from_binary(binary)
      expect(consumed).to eq(binary.bytesize)
    end

    it 'returns correct bytes consumed with trailing data' do
      binary = [brc74_hex].pack('H*') + ("\xFF".b * 10)
      _mp, consumed = described_class.from_binary(binary)
      expect(consumed).to eq(binary.bytesize - 10)
    end
  end

  describe '#compute_root_hex' do
    let(:mp) { described_class.from_hex(brc74_hex) }

    it 'computes the correct merkle root from the first leaf' do
      first_txid_hex = mp.path[0][0].hash.reverse.unpack1('H*')
      expect(mp.compute_root_hex(first_txid_hex)).to eq(expected_root_hex)
    end

    it 'computes the same root from each txid-flagged leaf' do
      mp.path[0].select(&:txid).each do |leaf|
        txid_hex = leaf.hash.reverse.unpack1('H*')
        expect(mp.compute_root_hex(txid_hex)).to eq(expected_root_hex)
      end
    end

    it 'computes the correct root with no txid argument' do
      expect(mp.compute_root_hex).to eq(expected_root_hex)
    end
  end

  describe '#compute_root' do
    it 'raises when txid is not in the path' do
      mp = described_class.from_hex(brc74_hex)
      fake_txid = "\x00".b * 32

      expect { mp.compute_root(fake_txid) }.to raise_error(ArgumentError, /does not contain/)
    end
  end

  describe '#combine' do
    it 'merges two sub-paths that share the same root' do
      mp = described_class.from_hex(brc74_hex)

      # Level 0: offsets 3048,3049 are siblings; 3050,3051 are siblings
      # Level 1: offset 1524 is parent of 3048/3049; 1525 is parent of 3050/3051
      # Split into two paths that can each independently compute the root:
      #   path_a: level 0 = [3048,3049], level 1 = [1525], levels 2+ same
      #   path_b: level 0 = [3050,3051], level 1 = [1524], levels 2+ same
      leaves_a = mp.path[0].select { |l| [3048, 3049].include?(l.offset) }
      leaves_b = mp.path[0].select { |l| [3050, 3051].include?(l.offset) }
      level1_for_a = mp.path[1].select { |l| l.offset == 1525 }
      level1_for_b = mp.path[1].select { |l| l.offset == 1524 }

      path_a = [leaves_a, level1_for_a] + mp.path[2..].map(&:dup)
      path_b = [leaves_b, level1_for_b] + mp.path[2..].map(&:dup)

      mp_a = described_class.new(block_height: mp.block_height, path: path_a)
      mp_b = described_class.new(block_height: mp.block_height, path: path_b)

      # Both can independently compute the correct root
      expect(mp_a.compute_root_hex).to eq(expected_root_hex)
      expect(mp_b.compute_root_hex).to eq(expected_root_hex)

      # After combining, path_a has the minimal compound proof for both
      # txid leaves. Level 0 keeps both txid leaves and their siblings
      # (3048/3051 are retained because 3049/3050 are txid-flagged).
      # Level 1 is trimmed to empty because both parents (1524, 1525) can
      # be computed from level 0. All higher levels retain only the
      # siblings still needed above the new "computed boundary".
      mp_a.combine(mp_b)
      expect(mp_a.path[0].map(&:offset)).to contain_exactly(3048, 3049, 3050, 3051)
      expect(mp_a.path[1]).to be_empty
      expect(mp_a.compute_root_hex).to eq(expected_root_hex)
    end

    it 'raises when block heights differ' do
      # Use real leaves to satisfy the constructor validation added in F5.10
      mp1 = described_class.from_hex(brc74_hex)
      mp2 = described_class.from_hex(brc74_hex)
      # Mutate the block height directly to simulate a different-height path
      mp2.instance_variable_set(:@block_height, mp1.block_height + 1)

      expect { mp1.combine(mp2) }.to raise_error(ArgumentError, /block heights/)
    end

    it 'does not mutate the other path' do
      mp = described_class.from_hex(brc74_hex)
      leaves_a = mp.path[0].select { |l| [3048, 3049].include?(l.offset) }
      leaves_b = mp.path[0].select { |l| [3050, 3051].include?(l.offset) }
      level1_a = mp.path[1].select { |l| l.offset == 1525 }
      level1_b = mp.path[1].select { |l| l.offset == 1524 }
      path_a = [leaves_a, level1_a] + mp.path[2..].map(&:dup)
      path_b = [leaves_b, level1_b] + mp.path[2..].map(&:dup)

      mp_a = described_class.new(block_height: mp.block_height, path: path_a)
      mp_b = described_class.new(block_height: mp.block_height, path: path_b)

      snapshot_b = mp_b.path.map { |level| level.map(&:offset) }
      mp_a.combine(mp_b)
      expect(mp_b.path.map { |level| level.map(&:offset) }).to eq(snapshot_b)
    end

    it 'upgrades an existing non-txid leaf when the incoming leaf is flagged' do
      # Two single-leaf paths in a synthetic 4-leaf block. In path_a, offset 2
      # is a non-txid sibling of the tx at offset 3. In path_b, offset 2 is
      # the txid leaf itself. Combining path_a and path_b must upgrade the
      # existing leaf at offset 2 from non-txid to txid, otherwise the
      # emitted BEEF would lose proof of the offset-2 tx.
      pe = described_class::PathElement
      leaf_hashes = (0..3).map { |i| BSV::Primitives::Digest.sha256("upgrade_leaf_#{i}") }
      level1_hashes = [
        described_class.merkle_tree_parent(leaf_hashes[0], leaf_hashes[1]),
        described_class.merkle_tree_parent(leaf_hashes[2], leaf_hashes[3])
      ]

      # Single-leaf proof for offset 3 — offset 2 appears as a non-txid sibling
      path_a = described_class.new(
        block_height: 950_000,
        path: [
          [pe.new(offset: 2, hash: leaf_hashes[2]),
           pe.new(offset: 3, hash: leaf_hashes[3], txid: true)],
          [pe.new(offset: 0, hash: level1_hashes[0])]
        ]
      )

      # Single-leaf proof for offset 2 — offset 2 is txid here
      path_b = described_class.new(
        block_height: 950_000,
        path: [
          [pe.new(offset: 2, hash: leaf_hashes[2], txid: true),
           pe.new(offset: 3, hash: leaf_hashes[3])],
          [pe.new(offset: 0, hash: level1_hashes[0])]
        ]
      )

      path_a.combine(path_b)

      txid_offsets = path_a.path[0].select(&:txid).map(&:offset)
      expect(txid_offsets).to contain_exactly(2, 3)
    end
  end

  describe '#trim' do
    let(:mp) { described_class.from_hex(brc74_hex) }

    it 'drops intermediate levels whose parents can be computed from level 0' do
      # The brc74 vector has both offsets 3049 and 3050 as txid leaves at
      # level 0, along with their siblings 3048 and 3051. Level 1 contains
      # 1524 and 1525 — the parents of those two pairs. After trim, level 1
      # is empty because both parents can be derived from level 0.
      mp.trim
      expect(mp.path[0].map(&:offset)).to contain_exactly(3048, 3049, 3050, 3051)
      expect(mp.path[1]).to be_empty
    end

    it 'preserves the merkle root after trimming' do
      original_root = mp.compute_root
      mp.trim
      expect(mp.compute_root).to eq(original_root)
    end

    it 'round-trips after trimming' do
      mp.trim
      hex = mp.to_hex
      parsed = described_class.from_hex(hex)
      expect(parsed.compute_root).to eq(mp.compute_root)
      expect(parsed.to_hex).to eq(hex)
    end

    it 'is a no-op on an already-minimal compound path' do
      mp.trim
      minimal_hex = mp.to_hex
      mp.trim
      expect(mp.to_hex).to eq(minimal_hex)
    end

    it 'returns self for chaining' do
      expect(mp.trim).to be(mp)
    end
  end

  describe '#extract' do
    let(:mp) { described_class.from_hex(brc74_hex) }
    let(:lower_target_hash) { mp.path[0].find { |l| l.offset == 3049 }.hash }
    let(:upper_target_hash) { mp.path[0].find { |l| l.offset == 3050 }.hash }

    it 'extracts a single-txid minimal compound path' do
      compound = mp.extract([lower_target_hash])

      expect(compound.compute_root).to eq(mp.compute_root)
      txid_leaves = compound.path[0].select(&:txid).map(&:hash)
      expect(txid_leaves).to contain_exactly(lower_target_hash)
    end

    it 'extracts multiple txids into one compound path' do
      compound = mp.extract([lower_target_hash, upper_target_hash])

      expect(compound.compute_root).to eq(mp.compute_root)
      txid_leaves = compound.path[0].select(&:txid).map(&:hash)
      expect(txid_leaves).to contain_exactly(lower_target_hash, upper_target_hash)
    end

    it 'returns a new MerklePath without mutating the source' do
      before_path = mp.path.map { |level| level.map(&:offset) }
      compound = mp.extract([lower_target_hash])

      expect(compound).not_to be(mp)
      expect(mp.path.map { |level| level.map(&:offset) }).to eq(before_path)
    end

    it 'strips phantom txid flags when extracting a subset' do
      # Both 3049 and 3050 are txid-flagged in the source. Extract only
      # the lower of the two and confirm the upper is absent as a txid
      # leaf in the compound.
      compound = mp.extract([lower_target_hash])
      compound_txids = compound.path[0].select(&:txid).map(&:hash)
      expect(compound_txids).not_to include(upper_target_hash)
    end

    it 'raises when wtxid_hashes is empty' do
      expect { mp.extract([]) }.to raise_error(ArgumentError, /at least one wtxid/)
    end

    it 'raises when a requested txid is not in the source path' do
      fake_txid = "\x00".b * 32
      expect { mp.extract([fake_txid]) }
        .to raise_error(ArgumentError, /not found in the Merkle Path/)
    end

    it 'extracts a single-level compound path with a duplicate sibling (F5.2)' do
      # A single-level BUMP where path.length == 1 but max_offset.bit_length > 1.
      # With F5.2 fixed, compute_root correctly walks to the implied tree height,
      # so extract and the source both compute the same root and extract succeeds.
      pe = described_class::PathElement
      tx_hash = BSV::Primitives::Digest.sha256('truncated_tx')
      source = described_class.new(
        block_height: 960_000,
        path: [
          [pe.new(offset: 2, hash: tx_hash, txid: true),
           pe.new(offset: 3, duplicate: true)]
        ]
      )

      extracted = source.extract([tx_hash])
      expect(extracted.compute_root(tx_hash)).to eq(source.compute_root(tx_hash))
    end
  end

  describe '#verify' do
    let(:mp) { described_class.from_hex(brc74_hex) }
    let(:txid_hex) { mp.path[0][0].hash.reverse.unpack1('H*') }

    it 'returns true when chain tracker confirms the root' do
      tracker = instance_double(BSV::Transaction::ChainTracker)
      allow(tracker).to receive(:valid_root_for_height?)
        .with(expected_root_hex, 813_706)
        .and_return(true)

      expect(mp.verify(txid_hex, tracker)).to be true
    end

    it 'returns false when chain tracker rejects the root' do
      tracker = instance_double(BSV::Transaction::ChainTracker)
      allow(tracker).to receive(:valid_root_for_height?)
        .with(expected_root_hex, 813_706)
        .and_return(false)

      expect(mp.verify(txid_hex, tracker)).to be false
    end

    it 'passes the correct root and height to the chain tracker' do
      tracker = instance_double(BSV::Transaction::ChainTracker)
      allow(tracker).to receive(:valid_root_for_height?).and_return(true)

      mp.verify(txid_hex, tracker)

      expect(tracker).to have_received(:valid_root_for_height?)
        .with(expected_root_hex, 813_706)
    end
  end

  # F5.11 — coinbase 100-block maturity check
  describe '#verify coinbase maturity (F5.11)' do
    # Build a minimal 2-leaf path at a known block height so we can control
    # the txid offset precisely.
    let(:pe) { BSV::Transaction::MerklePath::PathElement }
    let(:block_height) { 1_000 }
    let(:coinbase_hash) { BSV::Primitives::Digest.sha256('coinbase_tx') }
    let(:normal_hash)   { BSV::Primitives::Digest.sha256('normal_tx') }
    let(:expected_root) { described_class.merkle_tree_parent(coinbase_hash, normal_hash) }
    let(:root_hex)      { expected_root.reverse.unpack1('H*') }
    let(:coinbase_txid_hex) { coinbase_hash.reverse.unpack1('H*') }
    let(:normal_txid_hex)   { normal_hash.reverse.unpack1('H*') }

    # Coinbase tx is at offset 0; normal tx is at offset 1
    let(:coinbase_mp) do
      described_class.new(
        block_height: block_height,
        path: [
          [pe.new(offset: 0, hash: coinbase_hash, txid: true),
           pe.new(offset: 1, hash: normal_hash)]
        ]
      )
    end

    let(:normal_mp) do
      described_class.new(
        block_height: block_height,
        path: [
          [pe.new(offset: 0, hash: coinbase_hash),
           pe.new(offset: 1, hash: normal_hash, txid: true)]
        ]
      )
    end

    def tracker_returning(current_h, root_result)
      t = instance_double(BSV::Transaction::ChainTracker)
      allow(t).to receive_messages(current_height: current_h, valid_root_for_height?: root_result)
      t
    end

    it 'skips the maturity check for a non-coinbase tx (offset > 0)' do
      tracker = instance_double(BSV::Transaction::ChainTracker)
      allow(tracker).to receive(:valid_root_for_height?).and_return(true)

      result = normal_mp.verify(normal_txid_hex, tracker)

      expect(result).to be true
      # current_height must NOT be called for non-coinbase txs
      expect(tracker).not_to have_received(:current_height) if tracker.respond_to?(:current_height)
    end

    it 'returns false for coinbase tx with only 50 confirmations (immature)' do
      tracker = tracker_returning(block_height + 50, true)
      expect(coinbase_mp.verify(coinbase_txid_hex, tracker)).to be false
    end

    it 'returns false for coinbase tx with 99 confirmations (still immature)' do
      tracker = tracker_returning(block_height + 99, true)
      expect(coinbase_mp.verify(coinbase_txid_hex, tracker)).to be false
    end

    it 'proceeds to root check for coinbase tx with exactly 100 confirmations (mature)' do
      tracker = tracker_returning(block_height + 100, true)
      expect(coinbase_mp.verify(coinbase_txid_hex, tracker)).to be true
    end

    it 'returns false for mature coinbase when root check fails' do
      tracker = tracker_returning(block_height + 100, false)
      expect(coinbase_mp.verify(coinbase_txid_hex, tracker)).to be false
    end

    it 'returns false at 0 confirmations (current height == block height)' do
      tracker = tracker_returning(block_height, true)
      expect(coinbase_mp.verify(coinbase_txid_hex, tracker)).to be false
    end
  end

  # Issue #280 — TSC proof conversion
  describe '.from_tsc' do
    # Real WhatsOnChain TSC proof for tx 294cd1eb… in block 612251.
    # Captured from https://api.whatsonchain.com/v1/bsv/main/tx/294cd1ebd5689fdee03509f92c32184c0f52f037d4046af250229b97e0c8f1aa/proof/tsc
    let(:woc_txid) { '294cd1ebd5689fdee03509f92c32184c0f52f037d4046af250229b97e0c8f1aa' }
    let(:woc_index) { 799 }
    let(:woc_block_height) { 612_251 }
    let(:woc_expected_root) { 'fa37948946c4a356b99d0b335cc165a32de0cba7a4e0b8a0be39c5325189f446' }
    let(:woc_nodes) do
      %w[
        57a79dbc0be8225f4d9dc705a91096e60d3da8f3a7fdf009715dc28975a8dbb8
        deaab20855e7e018e8a5fc1b2414874e0392af5422b0af38576f3ff4cb0b6e29
        42e7d50a9fc732198d4e8ebf6056b19864c8928abe88f063f2060b525568add1
        bbc40d8d4c7415af5238075b0af3191ad234262d7c0d55b2891cbac947189634
        9a6d505bcf676e375660c264a1a2cee7d1951662a1cbbd843e3f56d9101aa157
        8c3b17405f9f8385a351f45f02f62327821d3be34592c7f49f1628f53c47ce72
        62ea964beeb128e2f286b90e7e79a2828d6b7392095b9f361199eedb1bd4a9b6
        85b522dec2714d35492edb824860f5b08ec065071cff7812c55c6d167285728f
        8b4309cc7d8872d37dec79aab24d106961f4997f3d6a7f3eddcb46cac54fcc2d
        f98edbe3e00de856d3013c16b1cb79f75825ffcbe04d726811affcf164d0d637
        2d62e81513f8b44359976b3566f8f622766d73b889fc8c5eebdc6f3686803ccd
        b136c3bd30688d245c06d9d96689387431102dc176ad2b9f492976fa493db2f0
      ]
    end

    let(:woc_path) do
      described_class.from_tsc(
        dtxid_hex: woc_txid,
        index: woc_index,
        nodes: woc_nodes,
        block_height: woc_block_height
      )
    end

    it 'computes the correct merkle root for a real WoC vector' do
      expect(woc_path.compute_root_hex(woc_txid)).to eq(woc_expected_root)
    end

    it 'sets the block height' do
      expect(woc_path.block_height).to eq(woc_block_height)
    end

    it 'produces a path with one level per TSC node' do
      expect(woc_path.path.length).to eq(woc_nodes.length)
    end

    it 'places the txid at the correct offset on level 0' do
      txid_leaf = woc_path.path[0].find(&:txid)
      expect(txid_leaf.offset).to eq(woc_index)
      expect(txid_leaf.hash.reverse.unpack1('H*')).to eq(woc_txid)
    end

    it 'level 0 contains the txid plus its direct sibling' do
      expect(woc_path.path[0].length).to eq(2)
      offsets = woc_path.path[0].map(&:offset)
      expect(offsets).to contain_exactly(woc_index, woc_index ^ 1)
    end

    it 'levels 1..N each contain exactly one sibling' do
      woc_path.path[1..].each_with_index do |level, i|
        expect(level.length).to eq(1), "level #{i + 1} had #{level.length} leaves, expected 1"
      end
    end

    it 'sibling offsets at each level match the TSC walk' do
      woc_path.path[1..].each_with_index do |level, i|
        height = i + 1
        expected_offset = (woc_index >> height) ^ 1
        expect(level.first.offset).to eq(expected_offset)
      end
    end

    it 'round-trips through to_hex / from_hex' do
      hex = woc_path.to_hex
      reparsed = described_class.from_hex(hex)
      expect(reparsed.compute_root_hex(woc_txid)).to eq(woc_expected_root)
      expect(reparsed.to_hex).to eq(hex)
    end

    context 'with a single-tx block' do
      it 'produces a one-level path containing only the txid' do
        mp = described_class.from_tsc(
          dtxid_hex: woc_txid,
          index: 0,
          nodes: [],
          block_height: 100
        )
        expect(mp.path.length).to eq(1)
        expect(mp.path[0].length).to eq(1)
        expect(mp.path[0].first.txid).to be true
        # For a single-tx block the txid IS the root.
        expect(mp.compute_root_hex(woc_txid)).to eq(woc_txid)
      end
    end

    context 'with duplicate ("*") nodes' do
      # Synthetic 3-leaf tree where the proven tx is the last leaf.
      # The final leaf is duplicated to form the right-hand pair at level 0,
      # so its sibling in the proof is itself ("*").
      let(:fake_hash) { ->(label) { BSV::Primitives::Digest.sha256(label) } }
      let(:leaves) { (0..2).map { |i| fake_hash.call("t#{i}") } }
      let(:level1) do
        [
          described_class.merkle_tree_parent(leaves[0], leaves[1]),
          described_class.merkle_tree_parent(leaves[2], leaves[2])
        ]
      end
      let(:expected_root) { described_class.merkle_tree_parent(level1[0], level1[1]).reverse.unpack1('H*') }

      let(:txid_hex) { leaves[2].reverse.unpack1('H*') }

      it 'computes the correct root when level 0 has a duplicate sibling' do
        mp = described_class.from_tsc(
          dtxid_hex: txid_hex,
          index: 2,
          nodes: ['*', level1[0].reverse.unpack1('H*')],
          block_height: 50
        )
        expect(mp.compute_root_hex(txid_hex)).to eq(expected_root)
      end

      it 'marks the duplicate level-0 sibling as duplicate' do
        mp = described_class.from_tsc(
          dtxid_hex: txid_hex,
          index: 2,
          nodes: ['*', level1[0].reverse.unpack1('H*')],
          block_height: 50
        )
        sibling = mp.path[0].find { |l| l.offset == 3 }
        expect(sibling.duplicate).to be true
        expect(sibling.hash).to be_nil
      end

      it 'round-trips a path with duplicate nodes' do
        mp = described_class.from_tsc(
          dtxid_hex: txid_hex,
          index: 2,
          nodes: ['*', level1[0].reverse.unpack1('H*')],
          block_height: 50
        )
        reparsed = described_class.from_hex(mp.to_hex)
        expect(reparsed.compute_root_hex(txid_hex)).to eq(expected_root)
      end
    end

    context 'with a small synthetic tree' do
      # 4-leaf tree, proving the leaf at index 2.
      let(:fake_hash) { ->(label) { BSV::Primitives::Digest.sha256(label) } }
      let(:leaves) { (0..3).map { |i| fake_hash.call("t#{i}") } }
      let(:level1) do
        [
          described_class.merkle_tree_parent(leaves[0], leaves[1]),
          described_class.merkle_tree_parent(leaves[2], leaves[3])
        ]
      end
      let(:root) { described_class.merkle_tree_parent(level1[0], level1[1]) }

      it 'computes the correct root from a hand-built TSC proof' do
        mp = described_class.from_tsc(
          dtxid_hex: leaves[2].reverse.unpack1('H*'),
          index: 2,
          nodes: [
            leaves[3].reverse.unpack1('H*'),  # level-0 sibling
            level1[0].reverse.unpack1('H*')   # level-1 sibling
          ],
          block_height: 1
        )
        expect(mp.compute_root_hex(leaves[2].reverse.unpack1('H*')))
          .to eq(root.reverse.unpack1('H*'))
      end
    end
  end

  # F5.10 — MerklePath constructor validation
  describe 'constructor validation (F5.10)' do
    let(:pe) { described_class::PathElement }
    let(:valid_leaf) { pe.new(offset: 0, hash: BSV::Primitives::Digest.sha256('tx'), txid: true) }
    let(:sibling) { pe.new(offset: 1, hash: BSV::Primitives::Digest.sha256('sib')) }

    it 'accepts a valid MerklePath' do
      expect do
        described_class.new(block_height: 800_000, path: [[valid_leaf, sibling]])
      end.not_to raise_error
    end

    it 'raises when block_height is negative' do
      expect do
        described_class.new(block_height: -1, path: [[valid_leaf]])
      end.to raise_error(ArgumentError, /block_height must be non-negative/)
    end

    it 'accepts block_height of zero' do
      expect do
        described_class.new(block_height: 0, path: [[valid_leaf]])
      end.not_to raise_error
    end

    it 'raises when path is empty' do
      expect do
        described_class.new(block_height: 1, path: [])
      end.to raise_error(ArgumentError, /path must be non-empty/)
    end

    it 'raises when a path level is not an Array' do
      expect do
        described_class.new(block_height: 1, path: ['not-an-array'])
      end.to raise_error(ArgumentError, /must be an Array/)
    end

    it 'raises when a path element is not a PathElement' do
      expect do
        described_class.new(block_height: 1, path: [['not-a-PathElement']])
      end.to raise_error(ArgumentError, /must be a PathElement/)
    end

    it 'raises when level 0 has no txid-flagged leaf' do
      non_txid_leaf = pe.new(offset: 0, hash: BSV::Primitives::Digest.sha256('x'))
      expect do
        described_class.new(block_height: 1, path: [[non_txid_leaf]])
      end.to raise_error(ArgumentError, /txid-flagged/)
    end

    it 'allows empty upper levels (only level 0 is checked)' do
      expect do
        described_class.new(block_height: 1, path: [[valid_leaf, sibling], []])
      end.not_to raise_error
    end
  end

  # F5.2 — compute_root for single-level compound paths
  describe '#compute_root single-level compound path (F5.2)' do
    let(:pe) { described_class::PathElement }

    it 'computes the correct root for a 2-tx single-level path (no separate upper levels)' do
      # A path where both txids sit at level 0 with no explicit level-1 node.
      # The root must be computed by walking from max_offset.bit_length.
      leaf0 = BSV::Primitives::Digest.sha256('tx0')
      leaf1 = BSV::Primitives::Digest.sha256('tx1')
      expected_root = described_class.merkle_tree_parent(leaf0, leaf1)

      mp = described_class.new(
        block_height: 900_000,
        path: [
          [pe.new(offset: 0, hash: leaf0, txid: true),
           pe.new(offset: 1, hash: leaf1, txid: true)]
        ]
      )

      expect(mp.compute_root(leaf0)).to eq(expected_root)
      expect(mp.compute_root(leaf1)).to eq(expected_root)
    end

    it 'produces the same root as computing the merkle parent directly' do
      leaf0 = BSV::Primitives::Digest.sha256('tx_a')
      leaf1 = BSV::Primitives::Digest.sha256('tx_b')
      expected_root = described_class.merkle_tree_parent(leaf0, leaf1)

      # Single-level compound path: both txids at level 0, no explicit level-1 node
      mp = described_class.new(
        block_height: 900_000,
        path: [
          [pe.new(offset: 0, hash: leaf0, txid: true),
           pe.new(offset: 1, hash: leaf1, txid: true)]
        ]
      )

      expect(mp.compute_root(leaf0)).to eq(expected_root)
      expect(mp.compute_root(leaf1)).to eq(expected_root)
    end

    it 'handles duplicate sibling at level 0 (odd leaf count)' do
      leaf2 = BSV::Primitives::Digest.sha256('tx_odd')
      # Offset 2 has a duplicate at offset 3; then we need to go up one more level
      mp = described_class.new(
        block_height: 960_000,
        path: [
          [pe.new(offset: 2, hash: leaf2, txid: true),
           pe.new(offset: 3, duplicate: true)]
        ]
      )

      # compute_root should not raise (single-level path with duplicate sibling)
      root = mp.compute_root(leaf2)
      expect(root).to be_a(String)
      expect(root.bytesize).to eq(32)
    end
  end

  describe '#compute_root_hex input validation' do
    let(:pe) { described_class::PathElement }
    let(:leaf) { BSV::Primitives::Digest.sha256('tx_val') }
    let(:sibling) { BSV::Primitives::Digest.sha256('sib_val') }
    let(:mp) do
      described_class.new(
        block_height: 100,
        path: [[pe.new(offset: 0, hash: leaf, txid: true),
                pe.new(offset: 1, hash: sibling)]]
      )
    end

    it 'raises on malformed hex input' do
      expect { mp.compute_root_hex('not_valid_hex') }
        .to raise_error(ArgumentError, /display-order hex/)
    end

    it 'raises on wrong-length hex' do
      expect { mp.compute_root_hex('aabb') }
        .to raise_error(ArgumentError, /64-char/)
    end

    it 'accepts nil (auto-detect)' do
      expect { mp.compute_root_hex }.not_to raise_error
    end

    it 'accepts a valid 64-char hex txid' do
      dtxid = leaf.reverse.unpack1('H*')
      expect { mp.compute_root_hex(dtxid) }.not_to raise_error
    end
  end

  describe '.from_tsc node validation' do
    let(:valid_dtxid) { 'aa' * 32 }

    it 'raises on non-hex node string' do
      expect do
        described_class.from_tsc(
          dtxid_hex: valid_dtxid,
          index: 0,
          nodes: ['not_valid_hex_at_all_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'],
          block_height: 100
        )
      end.to raise_error(ArgumentError, /TSC merkle node/)
    end

    it 'raises on short hex node string' do
      expect do
        described_class.from_tsc(
          dtxid_hex: valid_dtxid,
          index: 0,
          nodes: ['aabb'],
          block_height: 100
        )
      end.to raise_error(ArgumentError, /64-char/)
    end

    it 'accepts duplicate marker "*"' do
      expect do
        described_class.from_tsc(
          dtxid_hex: valid_dtxid,
          index: 0,
          nodes: ['*'],
          block_height: 100
        )
      end.not_to raise_error
    end

    it 'accepts valid 64-char hex nodes' do
      expect do
        described_class.from_tsc(
          dtxid_hex: valid_dtxid,
          index: 0,
          nodes: ['bb' * 32],
          block_height: 100
        )
      end.not_to raise_error
    end
  end
end
