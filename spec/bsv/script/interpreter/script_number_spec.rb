# frozen_string_literal: true

RSpec.describe BSV::Script::ScriptNumber do # rubocop:disable RSpec/SpecFilePathFormat
  describe '.from_bytes / #to_bytes round-trip' do
    # Test vectors from Go SDK (number.go documentation)
    {
      0 => '',
      1 => '01',
      -1 => '81',
      127 => '7f',
      -127 => 'ff',
      128 => '8000',
      -128 => '8080',
      129 => '8100',
      -129 => '8180',
      256 => '0001',
      -256 => '0081',
      32_767 => 'ff7f',
      -32_767 => 'ffff',
      32_768 => '008000',
      -32_768 => '008080'
    }.each do |value, hex|
      it "round-trips #{value}" do
        bytes = [hex].pack('H*')
        num = described_class.from_bytes(bytes)
        expect(num.value).to eq(value)
        expect(num.to_bytes.unpack1('H*')).to eq(hex)
      end
    end

    it 'decodes empty bytes as 0' do
      expect(described_class.from_bytes(''.b).value).to eq(0)
    end

    it 'encodes 0 as empty bytes' do
      expect(described_class.new(0).to_bytes).to eq(''.b)
    end
  end

  describe '.from_bytes with max_length' do
    it 'raises when bytes exceed max_length' do
      bytes = "\x01\x02\x03\x04\x05".b
      expect do
        described_class.from_bytes(bytes, max_length: 4)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:number_too_big)
      }
    end

    it 'accepts bytes within max_length' do
      bytes = "\x01\x02\x03\x04".b
      expect(described_class.from_bytes(bytes, max_length: 4).value).to eq(0x04030201)
    end
  end

  describe '.from_bytes with require_minimal' do
    it 'accepts minimal encodings' do
      expect(described_class.from_bytes(''.b, require_minimal: true).value).to eq(0)
      expect(described_class.from_bytes("\x7f".b, require_minimal: true).value).to eq(127)
      expect(described_class.from_bytes("\x80\x00".b, require_minimal: true).value).to eq(128)
    end

    it 'rejects negative zero (0x80)' do
      expect do
        described_class.from_bytes("\x80".b, require_minimal: true)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:minimal_data)
      }
    end

    it 'rejects unnecessary zero padding' do
      # 127 should be [0x7f] not [0x7f 0x00]
      expect do
        described_class.from_bytes("\x7f\x00".b, require_minimal: true)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:minimal_data)
      }
    end

    it 'accepts sign-extension byte when needed' do
      # 128 = [0x80 0x00] — needs the 0x00 because 0x80 has sign bit set
      expect(described_class.from_bytes("\x80\x00".b, require_minimal: true).value).to eq(128)
      # -128 = [0x80 0x80]
      expect(described_class.from_bytes("\x80\x80".b, require_minimal: true).value).to eq(-128)
    end
  end

  describe 'arithmetic' do
    let(:a) { described_class.new(10) }
    let(:b) { described_class.new(3) }

    it 'adds' do
      expect((a + b).value).to eq(13)
    end

    it 'subtracts' do
      expect((a - b).value).to eq(7)
    end

    it 'multiplies' do
      expect((a * b).value).to eq(30)
    end

    it 'divides toward zero' do
      expect((a / b).value).to eq(3)
      expect((described_class.new(-7) / described_class.new(2)).value).to eq(-3)
      expect((described_class.new(7) / described_class.new(-2)).value).to eq(-3)
      expect((described_class.new(-7) / described_class.new(-2)).value).to eq(3)
    end

    it 'raises on division by zero' do
      expect do
        a / described_class.new(0)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:divide_by_zero)
      }
    end

    it 'computes remainder with sign of dividend' do
      expect((a % b).value).to eq(1)
      expect((described_class.new(-7) % described_class.new(2)).value).to eq(-1)
      expect((described_class.new(7) % described_class.new(-2)).value).to eq(1)
    end

    it 'raises on modulo by zero' do
      expect do
        a % described_class.new(0)
      end.to raise_error(BSV::Script::ScriptError) { |e|
        expect(e.code).to eq(:divide_by_zero)
      }
    end

    it 'negates' do
      expect((-a).value).to eq(-10)
      expect((-described_class.new(-5)).value).to eq(5)
    end

    it 'computes absolute value' do
      expect(described_class.new(-42).abs.value).to eq(42)
      expect(described_class.new(42).abs.value).to eq(42)
    end
  end

  describe 'comparison (Comparable)' do
    it 'compares two ScriptNumbers' do
      expect(described_class.new(5)).to be > described_class.new(3)
      expect(described_class.new(3)).to be < described_class.new(5)
    end

    it 'reports equal ScriptNumbers' do
      a = described_class.new(5)
      b = described_class.new(5)
      expect(a).to eq(b)
    end

    it 'compares with integers' do
      expect(described_class.new(5)).to be > 3
      expect(described_class.new(5)).to eq(5)
    end
  end

  describe '#zero?' do
    it 'returns true for zero' do
      expect(described_class.new(0)).to be_zero
    end

    it 'returns false for non-zero' do
      expect(described_class.new(1)).not_to be_zero
    end
  end

  describe '#to_i32' do
    it 'returns value within int32 range' do
      expect(described_class.new(100).to_i32).to eq(100)
    end

    it 'clamps to INT32_MAX' do
      expect(described_class.new(2**31).to_i32).to eq(described_class::INT32_MAX)
    end

    it 'clamps to INT32_MIN' do
      expect(described_class.new(-(2**31) - 1).to_i32).to eq(described_class::INT32_MIN)
    end
  end

  describe '#to_i' do
    it 'returns the raw integer value' do
      expect(described_class.new(42).to_i).to eq(42)
    end
  end

  describe '.minimally_encode' do
    it 'returns empty for empty input' do
      expect(described_class.minimally_encode(''.b)).to eq(''.b)
    end

    it 'strips unnecessary padding' do
      # [0x7f 0x00] -> [0x7f]
      expect(described_class.minimally_encode("\x7f\x00".b).unpack1('H*')).to eq('7f')
    end

    it 'preserves sign-extension byte when needed' do
      # [0x80 0x00] is already minimal (128)
      expect(described_class.minimally_encode("\x80\x00".b).unpack1('H*')).to eq('8000')
    end

    it 'strips multiple trailing zero bytes' do
      # [0x7f 0x00 0x00] -> [0x7f]
      expect(described_class.minimally_encode("\x7f\x00\x00".b).unpack1('H*')).to eq('7f')
    end

    it 'returns empty for all-zero input' do
      expect(described_class.minimally_encode("\x00\x00".b)).to eq(''.b)
    end

    it 'preserves negative sign' do
      # [0xff] is -127, already minimal
      expect(described_class.minimally_encode("\xff".b).unpack1('H*')).to eq('ff')
    end

    it 'returns empty for single zero byte' do
      expect(described_class.minimally_encode("\x00".b)).to eq(''.b)
    end

    it 'returns empty for negative zero' do
      expect(described_class.minimally_encode("\x80".b)).to eq(''.b)
    end
  end

  describe 'large numbers (after-genesis)' do
    it 'handles numbers larger than 4 bytes' do
      large = 2**40
      num = described_class.new(large)
      round_tripped = described_class.from_bytes(num.to_bytes)
      expect(round_tripped.value).to eq(large)
    end

    it 'handles very large negative numbers' do
      large = -(2**100)
      num = described_class.new(large)
      round_tripped = described_class.from_bytes(num.to_bytes)
      expect(round_tripped.value).to eq(large)
    end
  end
end
