# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Primitives::KeyShares do
  let(:point_a) { BSV::Primitives::PointInFiniteField.new(OpenSSL::BN.new('0'), OpenSSL::BN.new('1')) }
  let(:point_b) { BSV::Primitives::PointInFiniteField.new(OpenSSL::BN.new('1'), OpenSSL::BN.new('2')) }
  let(:point_c) { BSV::Primitives::PointInFiniteField.new(OpenSSL::BN.new('2'), OpenSSL::BN.new('3')) }
  let(:integrity) { '6974656772697479' } # hex of "integrity"
  let(:key_shares) { described_class.new([point_a, point_b, point_c], 3, integrity) }

  describe '#initialize' do
    it 'stores points, threshold, and integrity' do
      expect(key_shares.points).to eq([point_a, point_b, point_c])
      expect(key_shares.threshold).to eq(3)
      expect(key_shares.integrity).to eq(integrity)
    end
  end

  describe '#to_backup_format' do
    it 'returns one string per point' do
      backup = key_shares.to_backup_format
      expect(backup.length).to eq(3)
    end

    it 'each string has exactly 4 dot-separated parts' do
      key_shares.to_backup_format.each do |share|
        expect(share.split('.').length).to eq(4)
      end
    end

    it 'embeds the threshold and integrity in each share' do
      key_shares.to_backup_format.each do |share|
        parts = share.split('.')
        expect(parts[2]).to eq('3')
        expect(parts[3]).to eq(integrity)
      end
    end
  end

  describe '.from_backup_format' do
    let(:backup) { key_shares.to_backup_format }

    it 'round-trips threshold and integrity' do
      rebuilt = described_class.from_backup_format(backup)
      expect(rebuilt.threshold).to eq(3)
      expect(rebuilt.integrity).to eq(integrity)
    end

    it 'round-trips points' do
      rebuilt = described_class.from_backup_format(backup)
      rebuilt.points.each_with_index do |pt, i|
        expect(pt.x).to eq(key_shares.points[i].x)
        expect(pt.y).to eq(key_shares.points[i].y)
      end
    end

    it 'raises ArgumentError for a share without 4 parts' do
      expect { described_class.from_backup_format(['invalid']) }.to raise_error(ArgumentError, /4 dot-separated parts/)
    end

    it 'raises ArgumentError for an empty threshold' do
      valid_x  = BSV::Primitives::Base58.encode(OpenSSL::BN.new('10').to_s(2))
      valid_y  = BSV::Primitives::Base58.encode(OpenSSL::BN.new('20').to_s(2))
      bad_share = "#{valid_x}.#{valid_y}..#{integrity}"
      expect { described_class.from_backup_format([bad_share]) }.to raise_error(ArgumentError, /threshold not found/)
    end

    it 'raises ArgumentError for an empty integrity' do
      valid_x   = BSV::Primitives::Base58.encode(OpenSSL::BN.new('10').to_s(2))
      valid_y   = BSV::Primitives::Base58.encode(OpenSSL::BN.new('20').to_s(2))
      bad_share = "#{valid_x}.#{valid_y}.3."
      expect { described_class.from_backup_format([bad_share]) }.to raise_error(ArgumentError, /integrity not found/)
    end

    it 'raises ArgumentError when threshold is non-numeric' do
      valid_x   = BSV::Primitives::Base58.encode(OpenSSL::BN.new('10').to_s(2))
      valid_y   = BSV::Primitives::Base58.encode(OpenSSL::BN.new('20').to_s(2))
      bad_share = "#{valid_x}.#{valid_y}.notanumber.#{integrity}"
      expect { described_class.from_backup_format([bad_share]) }.to raise_error(ArgumentError)
    end

    it 'raises ArgumentError when thresholds differ between shares' do
      share1 = backup[0]
      # Manually build a share with threshold 4 instead of 3
      parts = backup[1].split('.')
      share2 = "#{parts[0]}.#{parts[1]}.4.#{parts[3]}"
      expect { described_class.from_backup_format([share1, share2]) }.to raise_error(ArgumentError, /threshold mismatch/)
    end

    it 'raises ArgumentError when integrity differs between shares' do
      share1 = backup[0]
      parts  = backup[1].split('.')
      share2 = "#{parts[0]}.#{parts[1]}.#{parts[2]}.deadbeef"
      expect { described_class.from_backup_format([share1, share2]) }.to raise_error(ArgumentError, /integrity mismatch/)
    end

    it 'raises ArgumentError for invalid Base58 in x-coordinate' do
      bad_share = "0OIl.#{point_a.to_s.split('.')[1]}.3.#{integrity}"
      expect { described_class.from_backup_format([bad_share]) }.to raise_error(ArgumentError)
    end
  end
end
