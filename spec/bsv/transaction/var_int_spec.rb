# frozen_string_literal: true

RSpec.describe BSV::Transaction::VarInt do
  describe '.encode' do
    it 'encodes values 0-252 as a single byte' do
      expect(described_class.encode(0)).to eq("\x00".b)
      expect(described_class.encode(252)).to eq("\xFC".b)
    end

    it 'encodes values 253-65535 with 0xFD prefix' do
      expect(described_class.encode(253)).to eq("\xFD\xFD\x00".b)
      expect(described_class.encode(0xFFFF)).to eq("\xFD\xFF\xFF".b)
    end

    it 'encodes values 65536-2^32-1 with 0xFE prefix' do
      expect(described_class.encode(0x10000)).to eq("\xFE\x00\x00\x01\x00".b)
      expect(described_class.encode(0xFFFFFFFF)).to eq("\xFE\xFF\xFF\xFF\xFF".b)
    end

    it 'encodes values >= 2^32 with 0xFF prefix' do
      expect(described_class.encode(0x100000000)).to eq("\xFF\x00\x00\x00\x00\x01\x00\x00\x00".b)
    end
  end

  describe '.decode' do
    it 'decodes single-byte values' do
      value, consumed = described_class.decode("\xFC".b)
      expect(value).to eq(252)
      expect(consumed).to eq(1)
    end

    it 'decodes 3-byte values' do
      value, consumed = described_class.decode("\xFD\xFD\x00".b)
      expect(value).to eq(253)
      expect(consumed).to eq(3)
    end

    it 'decodes 5-byte values' do
      value, consumed = described_class.decode("\xFE\x00\x00\x01\x00".b)
      expect(value).to eq(0x10000)
      expect(consumed).to eq(5)
    end

    it 'decodes 9-byte values' do
      value, consumed = described_class.decode("\xFF\x00\x00\x00\x00\x01\x00\x00\x00".b)
      expect(value).to eq(0x100000000)
      expect(consumed).to eq(9)
    end

    it 'decodes from an offset' do
      data = "\x00\x00\xFD\x01\x00".b
      value, consumed = described_class.decode(data, 2)
      expect(value).to eq(1)
      expect(consumed).to eq(3)
    end

    it 'round-trips all encoding ranges' do
      [0, 1, 252, 253, 0xFFFF, 0x10000, 0xFFFFFFFF, 0x100000000].each do |v|
        encoded = described_class.encode(v)
        decoded, = described_class.decode(encoded)
        expect(decoded).to eq(v)
      end
    end
  end
end
