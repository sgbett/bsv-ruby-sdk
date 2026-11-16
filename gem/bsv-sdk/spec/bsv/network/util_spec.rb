# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::Util do
  describe '.safe_parse_json' do
    it 'parses valid JSON' do
      expect(described_class.safe_parse_json('{"a":1}')).to eq('a' => 1)
    end

    it 'returns a detail hash for invalid JSON' do
      expect(described_class.safe_parse_json('not json')).to eq('detail' => 'not json')
    end

    it 'returns detail: nil for an empty string' do
      expect(described_class.safe_parse_json('')).to eq('detail' => nil)
    end

    it 'returns detail: nil for nil' do
      expect(described_class.safe_parse_json(nil)).to eq('detail' => nil)
    end

    it 'parses a JSON array' do
      expect(described_class.safe_parse_json('[1,2,3]')).to eq([1, 2, 3])
    end
  end

  describe '.resolve_tx_hex' do
    let(:hex)    { '0100000000010203' }
    let(:binary) { [hex].pack('H*') }

    it 'passes a hex string through unchanged' do
      expect(described_class.resolve_tx_hex(hex)).to eq(hex)
    end

    it 'converts a binary string to hex' do
      expect(described_class.resolve_tx_hex(binary)).to eq(hex)
    end

    it 'raises ArgumentError for an empty string' do
      # Regression guard for #799: previously the regex was /\A[0-9a-fA-F]*\z/
      # (zero-or-more), so an empty string passed both checks and was returned
      # as-is — broadcasters then sent `rawTx: ''` to ARC/Arcade/TAALBinary.
      # Reject at this boundary so the protocol layer surfaces a clear error
      # instead of silently constructing an empty broadcast body.
      expect { described_class.resolve_tx_hex('') }.to raise_error(ArgumentError, /empty/)
    end

    it 'treats a non-hex string as binary and converts via unpack1' do
      # Odd-length or non-hex chars trip the regex/even-length check and fall
      # through to binary conversion.
      expect(described_class.resolve_tx_hex('xyz')).to eq('xyz'.unpack1('H*'))
    end

    it 'prefers EF hex when given a transaction object' do
      tx = instance_double(BSV::Transaction::Tx, to_ef_hex: 'ef-hex', to_hex: 'raw-hex')
      expect(described_class.resolve_tx_hex(tx)).to eq('ef-hex')
    end

    it 'falls back to raw hex when EF serialisation raises ArgumentError' do
      tx = instance_double(BSV::Transaction::Tx, to_hex: 'raw-hex')
      allow(tx).to receive(:to_ef_hex).and_raise(ArgumentError, 'missing source data')
      expect(described_class.resolve_tx_hex(tx)).to eq('raw-hex')
    end
  end

  describe '.resolve_ef_hex' do
    let(:ef_hex) { EfFixtures.ef_hex }

    it 'serialises a transaction object to Extended Format hex' do
      result = described_class.resolve_ef_hex(EfFixtures.ef_tx)
      expect(result).to eq(ef_hex)
      expect(result[8, 12]).to eq('0000000000ef')
    end

    it 'names Extended Format when the transaction lacks source data' do
      expect { described_class.resolve_ef_hex(EfFixtures.tx_without_source_data) }
        .to raise_error(ArgumentError, /\AExtended Format required: .*source/)
    end

    it 'passes Extended Format hex through' do
      expect(described_class.resolve_ef_hex(ef_hex)).to eq(ef_hex)
    end

    it 'accepts upper-case hex' do
      expect(described_class.resolve_ef_hex(ef_hex.upcase)).to eq(ef_hex.upcase)
    end

    it 'trims surrounding whitespace on hex' do
      expect(described_class.resolve_ef_hex("#{ef_hex}\n")).to eq(ef_hex)
    end

    it 'converts binary Extended Format to hex' do
      expect(described_class.resolve_ef_hex([ef_hex].pack('H*'))).to eq(ef_hex)
    end

    it 'converts binary Extended Format tagged UTF-8 (invalid as UTF-8) to hex' do
      binary = [ef_hex].pack('H*').force_encoding(Encoding::UTF_8)
      expect(described_class.resolve_ef_hex(binary)).to eq(ef_hex)
    end

    it 'does not trim binary strings' do
      binary = EfFixtures.ef_tx.to_ef + "\n".b
      expect(described_class.resolve_ef_hex(binary)).to eq("#{ef_hex}0a")
    end

    it 'rejects nil and objects that are not transactions with ArgumentError' do
      expect { described_class.resolve_ef_hex(nil) }.to raise_error(ArgumentError, /to_ef_hex.*NilClass/)
      expect { described_class.resolve_ef_hex(Object.new) }.to raise_error(ArgumentError, /Object/)
    end

    it 'rejects an empty string' do
      expect { described_class.resolve_ef_hex('') }.to raise_error(ArgumentError, /empty/)
    end

    it 'rejects plain transaction hex' do
      expect { described_class.resolve_ef_hex(EfFixtures.ef_tx.to_hex) }
        .to raise_error(ArgumentError, /Extended Format/)
    end

    it 'rejects BEEF hex' do
      expect { described_class.resolve_ef_hex("0100beef#{'00' * 40}") }
        .to raise_error(ArgumentError, /Extended Format/)
    end

    it 'rejects a 10-byte plain transaction that happens to carry the marker at offset 4' do
      expect { described_class.resolve_ef_hex('010000000000000000ef') }
        .to raise_error(ArgumentError, /Extended Format/)
    end
  end

  describe '.service_text' do
    it 'is nil for non-Strings' do
      expect(described_class.service_text(nil)).to be_nil
      expect(described_class.service_text(5)).to be_nil
      expect(described_class.service_text(['a'])).to be_nil
    end

    it 'is nil for blank strings' do
      expect(described_class.service_text(" \n\t ")).to be_nil
    end

    it 'replaces control characters and ANSI escapes with spaces' do
      expect(described_class.service_text("bad\e[31m red\x00\r\nline")).to eq('bad [31m red line')
    end

    {
      'U+202E bidi override' => "a\u202Eb",
      'U+200B zero-width space' => "a\u200Bb",
      'U+FEFF byte order mark' => "a\uFEFFb",
      'U+2028 line separator' => "a\u2028b",
      'U+2029 paragraph separator' => "a\u2029b"
    }.each do |label, input|
      it "replaces #{label} with a space" do
        expect(described_class.service_text(input)).to eq('a b')
      end
    end

    it 'keeps ordinary non-ASCII text' do
      expect(described_class.service_text("caf\u00E9 \u65E5\u672C")).to eq("caf\u00E9 \u65E5\u672C")
    end

    it 'handles inputs far larger than the limit' do
      expect(described_class.service_text('é' * 100_000).length).to eq(8000)
    end

    it 'truncates to the limit' do
      expect(described_class.service_text('a' * 20_000).length).to eq(8000)
    end

    it 'does not raise on invalid UTF-8' do
      expect(described_class.service_text("ok \xFF\xFE end".b)).to eq('ok end')
    end
  end
end
