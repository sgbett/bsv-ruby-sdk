# frozen_string_literal: true

require 'spec_helper'

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

  describe 'boundary transitions' do
    # Verify exact encoded sizes and correct prefix selection at boundaries
    {
      # value => [expected_size, description]
      0 => [1, '1-byte minimum'],
      0xFC => [1, '1-byte maximum (252)'],
      0xFD => [3, '3-byte minimum (253)'],
      0xFFFF => [3, '3-byte maximum (65535)'],
      0x10000 => [5, '5-byte minimum (65536)'],
      0xFFFFFFFF => [5, '5-byte maximum (4294967295)'],
      0x100000000 => [9, '9-byte minimum (4294967296)']
    }.each do |value, (expected_size, description)|
      it "encodes #{description} as #{expected_size} byte(s) and round-trips" do
        encoded = described_class.encode(value)
        expect(encoded.bytesize).to eq(expected_size)
        decoded, consumed = described_class.decode(encoded)
        expect(decoded).to eq(value)
        expect(consumed).to eq(expected_size)
      end
    end

    it 'selects correct prefix at 1-byte/3-byte boundary' do
      expect(described_class.encode(252).getbyte(0)).to eq(0xFC)  # direct
      expect(described_class.encode(253).getbyte(0)).to eq(0xFD)  # prefix
    end

    it 'selects correct prefix at 3-byte/5-byte boundary' do
      expect(described_class.encode(0xFFFF).getbyte(0)).to eq(0xFD)   # 3-byte
      expect(described_class.encode(0x10000).getbyte(0)).to eq(0xFE)  # 5-byte
    end

    it 'selects correct prefix at 5-byte/9-byte boundary' do
      expect(described_class.encode(0xFFFFFFFF).getbyte(0)).to eq(0xFE)   # 5-byte
      expect(described_class.encode(0x100000000).getbyte(0)).to eq(0xFF)  # 9-byte
    end
  end

  # Regression for https://github.com/sgbett/bsv-ruby-sdk/issues/305 (F1.3)
  #
  # Prior behaviour: `VarInt.encode(-1)` fell into the `value < 0xFD` branch and
  # emitted `[value].pack('C')`, which masks the two's-complement low byte —
  # producing 0xFF, the marker byte for a 9-byte encoding. A downstream reader
  # would then try to consume 8 more bytes from whatever followed, silently
  # corrupting the transaction stream with no exception raised. The docstring
  # required a non-negative integer but the implementation did not enforce it.
  describe '.encode input validation (issue #305)' do
    it 'raises ArgumentError on -1 (silent 0xFF marker corruption)' do
      expect { described_class.encode(-1) }
        .to raise_error(ArgumentError, /non-negative/)
    end

    it 'raises ArgumentError on a large negative integer' do
      expect { described_class.encode(-0xFFFFFFFFFFFFFFFF) }
        .to raise_error(ArgumentError, /non-negative/)
    end

    it 'accepts the uint64 maximum (2^64 - 1)' do
      expected = "\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF".b
      expect(described_class.encode(0xFFFFFFFFFFFFFFFF)).to eq(expected)
    end

    it 'raises ArgumentError on 2^64 (just past uint64 max)' do
      expect { described_class.encode(0x10000000000000000) }
        .to raise_error(ArgumentError, /exceeds uint64/)
    end

    it 'raises ArgumentError on a very large value far above uint64' do
      expect { described_class.encode(2**128) }
        .to raise_error(ArgumentError, /exceeds uint64/)
    end
  end
end
