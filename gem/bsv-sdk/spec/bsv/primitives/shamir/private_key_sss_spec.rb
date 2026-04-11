# frozen_string_literal: true

RSpec.describe BSV::Primitives::PrivateKey do
  let(:key) { described_class.from_hex('eaf02ca348c524e6392655ba4d29603cd1a7347d9d65cfe93ce1ebffdca22694') }

  # Cross-SDK compatibility: backup format strings produced by our Ruby SDK
  # must round-trip correctly and match the 4-part "x.y.threshold.integrity"
  # format used by the Go and TypeScript reference SDKs.
  let(:expected_integrity) { '35dbbf04' } # Hash160(compressed pubkey)[0..3].hex for known_hex key

  describe '#to_key_shares' do
    it 'returns a KeyShares with the correct point count' do
      shares = key.to_key_shares(2, 5)
      expect(shares.points.length).to eq(5)
    end

    it 'sets the threshold correctly' do
      shares = key.to_key_shares(3, 5)
      expect(shares.threshold).to eq(3)
    end

    it 'sets a non-empty integrity string' do
      shares = key.to_key_shares(2, 3)
      expect(shares.integrity).not_to be_empty
      expect(shares.integrity).to match(/\A[0-9a-f]{8}\z/)
    end

    it 'computes integrity from the public key hash160' do
      expected = key.public_key.hash160[0, 4].unpack1('H*')
      shares   = key.to_key_shares(2, 3)
      expect(shares.integrity).to eq(expected)
    end

    it 'generates unique x-coordinates across all shares' do
      shares = key.to_key_shares(2, 10)
      xs     = shares.points.map { |p| p.x.to_s }
      expect(xs.uniq.length).to eq(10)
    end

    it 'generates non-zero x-coordinates for all shares' do
      shares = key.to_key_shares(2, 5)
      shares.points.each { |p| expect(p.x).not_to eq(OpenSSL::BN.new('0')) }
    end

    it 'produces different x-coordinates on each call (non-deterministic)' do
      shares1 = key.to_key_shares(2, 3)
      shares2 = key.to_key_shares(2, 3)
      xs1     = shares1.points.map { |p| p.x.to_s }
      xs2     = shares2.points.map { |p| p.x.to_s }
      expect(xs1).not_to eq(xs2)
    end

    it 'raises ArgumentError when threshold < 2' do
      expect { key.to_key_shares(1, 3) }.to raise_error(ArgumentError, /threshold must be at least 2/)
    end

    it 'raises ArgumentError when total_shares < 2' do
      expect { key.to_key_shares(2, 1) }.to raise_error(ArgumentError, /total_shares must be at least 2/)
    end

    it 'raises ArgumentError when threshold > total_shares' do
      expect { key.to_key_shares(5, 3) }.to raise_error(ArgumentError, /threshold must be <= total_shares/)
    end

    it 'raises ArgumentError for non-integer threshold' do
      expect { key.to_key_shares('2', 3) }.to raise_error(ArgumentError, /threshold must be an integer/)
    end

    it 'raises ArgumentError for non-integer total_shares' do
      expect { key.to_key_shares(2, '3') }.to raise_error(ArgumentError, /total_shares must be an integer/)
    end
  end

  describe '#to_backup_shares' do
    it 'returns an array of strings' do
      backup = key.to_backup_shares(2, 3)
      expect(backup).to be_an(Array)
      expect(backup).to all(be_a(String))
    end

    it 'returns total_shares strings' do
      expect(key.to_backup_shares(2, 5).length).to eq(5)
    end

    it 'each string has 4 dot-separated parts' do
      key.to_backup_shares(2, 3).each do |share|
        expect(share.split('.').length).to eq(4)
      end
    end
  end

  describe '.from_key_shares' do
    it 'reconstructs the original key from a threshold subset of shares' do
      shares   = key.to_key_shares(2, 5)
      subset   = BSV::Primitives::KeyShares.new(shares.points[0, 2], 2, shares.integrity)
      recovered = described_class.from_key_shares(subset)
      expect(recovered.to_hex).to eq(key.to_hex)
    end

    it 'reconstructs with any threshold-sized subset of the shares' do
      shares = key.to_key_shares(3, 6)
      [[0, 1, 2], [1, 2, 3], [3, 4, 5], [0, 2, 5]].each do |indices|
        subset    = BSV::Primitives::KeyShares.new(indices.map { |i| shares.points[i] }, 3, shares.integrity)
        recovered = described_class.from_key_shares(subset)
        expect(recovered.to_hex).to eq(key.to_hex)
      end
    end

    it 'uses excess shares (takes only threshold of them) for reconstruction' do
      shares    = key.to_key_shares(2, 5)
      # Pass all 5 shares when threshold is 2 — should still work
      recovered = described_class.from_key_shares(shares)
      expect(recovered.to_hex).to eq(key.to_hex)
    end

    it 'raises ArgumentError when threshold < 2' do
      shares = BSV::Primitives::KeyShares.new([], 1, 'abc')
      expect { described_class.from_key_shares(shares) }.to raise_error(ArgumentError, /threshold must be at least 2/)
    end

    it 'raises ArgumentError when too few points are provided' do
      shares = key.to_key_shares(3, 5)
      subset = BSV::Primitives::KeyShares.new(shares.points[0, 2], 3, shares.integrity)
      expect { described_class.from_key_shares(subset) }.to raise_error(ArgumentError, /at least 3 shares/)
    end

    it 'raises ArgumentError when duplicate shares are provided' do
      shares     = key.to_key_shares(2, 5)
      dup_subset = BSV::Primitives::KeyShares.new([shares.points[0], shares.points[0]], 2, shares.integrity)
      expect { described_class.from_key_shares(dup_subset) }.to raise_error(ArgumentError, /duplicate share/)
    end

    it 'raises ArgumentError on integrity hash mismatch' do
      shares = key.to_key_shares(2, 3)
      bad_integrity = BSV::Primitives::KeyShares.new(shares.points[0, 2], 2, 'deadbeef')
      expect { described_class.from_key_shares(bad_integrity) }.to raise_error(ArgumentError, /integrity hash mismatch/)
    end
  end

  describe '.from_backup_shares' do
    it 'reconstructs the key from backup-format strings' do
      backup    = key.to_backup_shares(2, 3)
      recovered = described_class.from_backup_shares(backup[0, 2])
      expect(recovered.to_hex).to eq(key.to_hex)
    end

    it 'embeds the correct integrity string in backup shares' do
      # Verifies cross-SDK format compatibility: integrity is Hash160(pubkey)[0,4].hex
      backup = key.to_backup_shares(2, 3)
      backup.each { |share| expect(share.split('.')[3]).to eq(expected_integrity) }
    end

    it 'backup shares use the 4-part Go/TS-SDK-compatible format' do
      backup = key.to_backup_shares(2, 3)
      backup.each do |share|
        parts = share.split('.', -1)
        expect(parts.length).to eq(4)
        expect(parts[2]).to eq('2') # threshold
        expect(parts[3]).to match(/\A[0-9a-f]{8}\z/) # 8-char hex integrity
      end
    end

    it 'raises ArgumentError for invalid share format' do
      expect { described_class.from_backup_shares(['bad.share']) }.to raise_error(ArgumentError)
    end
  end

  describe 'full round-trip: split → backup → reconstruct' do
    it 'works for threshold=2, total=5' do
      backup    = key.to_backup_shares(2, 5)
      recovered = described_class.from_backup_shares(backup[0, 2])
      expect(recovered.to_hex).to eq(key.to_hex)
    end

    it 'works for threshold=3, total=5' do
      backup    = key.to_backup_shares(3, 5)
      recovered = described_class.from_backup_shares(backup[0, 3])
      expect(recovered.to_hex).to eq(key.to_hex)
    end

    it 'works for threshold equal to total_shares' do
      backup    = key.to_backup_shares(5, 5)
      recovered = described_class.from_backup_shares(backup)
      expect(recovered.to_hex).to eq(key.to_hex)
    end

    it 'works for a randomly generated key' do
      random_key = described_class.generate
      backup     = random_key.to_backup_shares(2, 3)
      recovered  = described_class.from_backup_shares(backup[0, 2])
      expect(recovered.to_hex).to eq(random_key.to_hex)
    end
  end
end
