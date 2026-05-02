# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Primitives::Hex do
  describe '.valid?' do
    it('accepts empty string')         { expect(described_class.valid?('')).to be true }
    it('accepts lowercase even hex')   { expect(described_class.valid?('deadbeef')).to be true }
    it('accepts uppercase even hex')   { expect(described_class.valid?('DEADBEEF')).to be true }
    it('accepts mixed-case even hex')  { expect(described_class.valid?('DeAdBeEf')).to be true }
    it('rejects odd-length hex')       { expect(described_class.valid?('abc')).to be false }
    it('rejects non-hex characters')   { expect(described_class.valid?('deadXYZbeef')).to be false }
    it('rejects spaces')               { expect(described_class.valid?('de ad')).to be false }
    it('rejects nil')                  { expect(described_class.valid?(nil)).to be false }
    it('rejects integers')             { expect(described_class.valid?(42)).to be false }
  end

  describe '.validate!' do
    it 'returns the input for valid hex' do
      expect(described_class.validate!('deadbeef')).to eq('deadbeef')
    end

    it 'raises ArgumentError on odd-length hex' do
      expect { described_class.validate!('abc') }.to raise_error(ArgumentError, /odd length/)
    end

    it 'raises ArgumentError on non-hex characters' do
      expect { described_class.validate!('nope') }.to raise_error(ArgumentError, /non-hex/)
    end

    it 'raises ArgumentError on non-String' do
      expect { described_class.validate!(42) }.to raise_error(ArgumentError, /expected String/)
    end

    it 'includes the custom name in the error message' do
      expect { described_class.validate!('XY', name: 'txid') }.to raise_error(ArgumentError, /txid/)
    end
  end

  describe '.decode' do
    it 'decodes valid hex to binary' do
      expect(described_class.decode('deadbeef')).to eq("\xDE\xAD\xBE\xEF".b)
    end

    it 'decodes empty string to empty binary' do
      expect(described_class.decode('')).to eq(''.b)
    end

    it 'is case-insensitive' do
      expect(described_class.decode('DEADBEEF')).to eq(described_class.decode('deadbeef'))
    end

    it 'raises on odd-length input' do
      expect { described_class.decode('abc') }.to raise_error(ArgumentError)
    end

    it 'raises on non-hex input' do
      expect { described_class.decode('nope') }.to raise_error(ArgumentError)
    end
  end

  describe '.validate_hash32!' do
    it 'returns the input for a valid 32-byte string' do
      hash = "\x00".b * 32
      expect(described_class.validate_hash32!(hash)).to equal(hash)
    end

    it 'raises on nil' do
      expect { described_class.validate_hash32!(nil) }.to raise_error(ArgumentError, /expected 32-byte hash/)
    end

    it 'raises on wrong-length binary' do
      expect { described_class.validate_hash32!("\x00".b * 16, name: 'test') }
        .to raise_error(ArgumentError, /expected 32-byte hash for test, got 16-byte/)
    end

    it 'hints when input looks like hex' do
      hex64 = 'aa' * 32
      expect { described_class.validate_hash32!(hex64) }
        .to raise_error(ArgumentError, /looks like hex/)
    end

    it 'does not hint for non-hex 64-byte strings' do
      non_hex = 'zz' * 32
      expect { described_class.validate_hash32!(non_hex) }
        .to raise_error(ArgumentError) { |e| expect(e.message).not_to include('looks like hex') }
    end
  end

  describe '.encode' do
    it 'encodes binary to lowercase hex' do
      expect(described_class.encode("\xDE\xAD\xBE\xEF".b)).to eq('deadbeef')
    end

    it 'encodes empty binary to empty string' do
      expect(described_class.encode(''.b)).to eq('')
    end

    it 'round-trips with decode' do
      hex = 'cafebabe01020304'
      expect(described_class.encode(described_class.decode(hex))).to eq(hex)
    end
  end
end
