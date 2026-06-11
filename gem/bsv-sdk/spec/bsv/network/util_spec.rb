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
end
