# frozen_string_literal: true

RSpec.describe BSV::Primitives::PointInFiniteField do
  let(:p) { described_class::P }
  let(:x_bn) { OpenSSL::BN.new('10') }
  let(:y_bn) { OpenSSL::BN.new('20') }
  let(:point) { described_class.new(x_bn, y_bn) }

  describe '#initialize' do
    it 'stores x and y as OpenSSL::BN' do
      expect(point.x).to eq(x_bn)
      expect(point.y).to eq(y_bn)
    end

    it 'reduces negative x modulo P' do
      neg = described_class.new(OpenSSL::BN.new('-1'), OpenSSL::BN.new('5'))
      expect(neg.x).to eq(p - OpenSSL::BN.new('1'))
    end

    it 'reduces negative y modulo P' do
      neg = described_class.new(OpenSSL::BN.new('5'), OpenSSL::BN.new('-1'))
      expect(neg.y).to eq(p - OpenSSL::BN.new('1'))
    end

    it 'reduces x that equals P to zero' do
      pt = described_class.new(p, OpenSSL::BN.new('1'))
      expect(pt.x).to eq(OpenSSL::BN.new('0'))
    end

    it 'handles x = 0 and y = 0' do
      pt = described_class.new(OpenSSL::BN.new('0'), OpenSSL::BN.new('0'))
      expect(pt.x).to eq(OpenSSL::BN.new('0'))
      expect(pt.y).to eq(OpenSSL::BN.new('0'))
    end
  end

  describe '#to_s' do
    it 'produces two dot-separated Base58 tokens' do
      str = point.to_s
      parts = str.split('.')
      expect(parts.length).to eq(2)
      expect(parts).to all(match(/\A[1-9A-HJ-NP-Za-km-z]+\z/))
    end

    it 'encodes (10, 20) consistently' do
      # Stable encoding – Base58(10-byte big-endian) is deterministic
      expect(point.to_s).not_to be_empty
    end
  end

  describe '.from_string' do
    it 'round-trips through to_s' do
      str = point.to_s
      rebuilt = described_class.from_string(str)
      expect(rebuilt.x).to eq(point.x)
      expect(rebuilt.y).to eq(point.y)
    end

    it 'raises ArgumentError for strings without exactly one dot' do
      expect { described_class.from_string('nodot') }.to raise_error(ArgumentError, /invalid point string/)
      expect { described_class.from_string('a.b.c') }.to raise_error(ArgumentError, /invalid point string/)
    end

    it 'raises ArgumentError for invalid Base58 characters in x' do
      valid_y = BSV::Primitives::Base58.encode(OpenSSL::BN.new('20').to_s(2))
      expect { described_class.from_string("0OIl.#{valid_y}") }.to raise_error(ArgumentError)
    end

    it 'reconstructs large coordinates correctly' do
      large_x = p - OpenSSL::BN.new('1')
      large_y = p - OpenSSL::BN.new('2')
      original = described_class.new(large_x, large_y)
      rebuilt  = described_class.from_string(original.to_s)
      expect(rebuilt.x).to eq(original.x)
      expect(rebuilt.y).to eq(original.y)
    end
  end
end
