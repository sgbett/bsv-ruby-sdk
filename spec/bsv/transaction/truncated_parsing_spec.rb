# frozen_string_literal: true

# Defensive parsing tests: ensure every from_binary method raises ArgumentError
# with a descriptive message when given truncated input, rather than producing
# NoMethodError or returning corrupt data.

RSpec.describe 'truncated binary parsing' do
  describe BSV::Transaction::VarInt do
    it 'raises on empty data' do
      expect { described_class.decode(''.b) }.to raise_error(ArgumentError, /truncated varint/)
    end

    it 'raises on truncated 3-byte varint' do
      expect { described_class.decode("\xFD\x01".b) }.to raise_error(ArgumentError, /truncated varint.*need 3/)
    end

    it 'raises on truncated 5-byte varint' do
      expect { described_class.decode("\xFE\x01\x00".b) }.to raise_error(ArgumentError, /truncated varint.*need 5/)
    end

    it 'raises on truncated 9-byte varint' do
      expect { described_class.decode("\xFF\x01\x00\x00\x00".b) }.to raise_error(ArgumentError, /truncated varint.*need 9/)
    end

    it 'raises when offset is past end of data' do
      expect { described_class.decode("\x01".b, 5) }.to raise_error(ArgumentError, /truncated varint/)
    end
  end

  describe BSV::Transaction::TransactionInput do
    it 'raises on empty data' do
      expect { described_class.from_binary(''.b) }.to raise_error(ArgumentError, /truncated input.*outpoint/)
    end

    it 'raises on data shorter than outpoint (36 bytes)' do
      expect { described_class.from_binary("\x00" * 20) }.to raise_error(ArgumentError, /truncated input.*need 36/)
    end

    it 'raises when script length exceeds remaining data' do
      # 32-byte txid + 4-byte index + varint(100) but no script data
      data = ("\x00" * 36) + "\x64"
      expect { described_class.from_binary(data.b) }.to raise_error(ArgumentError, /truncated input.*script/)
    end

    it 'raises when sequence bytes are missing' do
      # 32-byte txid + 4-byte index + varint(0) for empty script + NO sequence
      data = ("\x00" * 36) + "\x00"
      expect { described_class.from_binary(data.b) }.to raise_error(ArgumentError, /truncated input.*sequence/)
    end
  end

  describe BSV::Transaction::TransactionOutput do
    it 'raises on empty data' do
      expect { described_class.from_binary(''.b) }.to raise_error(ArgumentError, /truncated output.*satoshis/)
    end

    it 'raises on data shorter than 8 bytes' do
      expect { described_class.from_binary("\x00\x00\x00".b) }.to raise_error(ArgumentError, /truncated output.*need 8/)
    end

    it 'raises when script length exceeds remaining data' do
      # 8-byte satoshis + varint(50) but no script data
      data = ("\x00" * 8) + "\x32"
      expect { described_class.from_binary(data.b) }.to raise_error(ArgumentError, /truncated output.*script/)
    end
  end

  describe BSV::Transaction::Transaction do
    describe '.from_binary' do
      it 'raises on empty data' do
        expect { described_class.from_binary(''.b) }.to raise_error(ArgumentError, /truncated transaction/)
      end

      it 'raises on data shorter than minimum transaction' do
        expect { described_class.from_binary("\x01\x00\x00\x00".b) }.to raise_error(ArgumentError, /truncated transaction/)
      end

      it 'raises when lock_time bytes are missing' do
        # Build a valid tx body but truncate the lock_time
        # version(4) + 1 input (varint(1) + 36-byte outpoint + varint(0) script + 4-byte seq = 41)
        # + 0 outputs (varint(0) = 1) = 46 bytes, then only 2 bytes for lock_time
        input_bin = ("\x00" * 36) + "\x00" + ("\xFF" * 4)
        data = "\x01\x00\x00\x00".b + "\x01".b + input_bin.b + "\x00".b + "\x01\x00".b
        expect { described_class.from_binary(data) }.to raise_error(ArgumentError, /truncated transaction.*lock_time/)
      end
    end

    describe '.from_binary_with_offset' do
      it 'raises on empty data' do
        expect { described_class.from_binary_with_offset(''.b) }.to raise_error(ArgumentError, /truncated transaction/)
      end

      it 'raises when offset puts remaining data below minimum' do
        data = "\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00".b
        expect { described_class.from_binary_with_offset(data, 5) }.to raise_error(ArgumentError, /truncated transaction/)
      end
    end

    describe '.from_ef' do
      it 'raises on empty data' do
        expect { described_class.from_ef(''.b) }.to raise_error(ArgumentError, /truncated EF/)
      end

      it 'raises on data shorter than minimum' do
        expect { described_class.from_ef("\x01\x00\x00\x00".b) }.to raise_error(ArgumentError, /truncated EF/)
      end
    end
  end

  describe BSV::Transaction::Beef do
    describe '.from_binary' do
      it 'raises on empty data' do
        expect { described_class.from_binary(''.b) }.to raise_error(ArgumentError, /truncated BEEF/)
      end

      it 'raises on data shorter than 4 bytes' do
        expect { described_class.from_binary("\x01\x00".b) }.to raise_error(ArgumentError, /truncated BEEF/)
      end

      it 'raises on truncated Atomic BEEF (missing subject txid)' do
        # Atomic BEEF version marker + only 10 bytes (need 36 more)
        data = "\x01\x01\x01\x01" + ("\x00" * 10)
        expect { described_class.from_binary(data.b) }.to raise_error(ArgumentError, /truncated Atomic BEEF/)
      end
    end
  end
end
