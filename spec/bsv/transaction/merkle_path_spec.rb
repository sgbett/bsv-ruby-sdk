# frozen_string_literal: true

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

      # After combining, path_a has all leaves
      mp_a.combine(mp_b)
      expect(mp_a.path[0].map(&:offset)).to contain_exactly(3048, 3049, 3050, 3051)
      expect(mp_a.path[1].map(&:offset)).to contain_exactly(1524, 1525)
      expect(mp_a.compute_root_hex).to eq(expected_root_hex)
    end

    it 'raises when block heights differ' do
      mp1 = described_class.new(block_height: 1, path: [[]])
      mp2 = described_class.new(block_height: 2, path: [[]])

      expect { mp1.combine(mp2) }.to raise_error(ArgumentError, /block heights/)
    end
  end
end
