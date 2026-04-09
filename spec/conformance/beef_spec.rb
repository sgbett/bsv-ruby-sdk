# frozen_string_literal: true

require 'spec_helper'
require 'base64'

# Protocol conformance: BEEF serialisation (BRC-62/95/96)
#
# Cross-validates the Ruby SDK's BEEF implementation against canonical test
# vectors from go-sdk (constants `BRC62Hex`, `BEEF`, `BEEFSet` in
# `transaction/beef_test.go`). Vectors are loaded from
# `spec/conformance/vectors/beef.vectors.json` — see that file and
# `spec/conformance/vectors/README.md` for provenance.

BEEF_CONFORMANCE_VECTORS = ConformanceVectors.load('beef.vectors.json')['vectors']
                                             .to_h { |v| [v['label'], v['data']] }
                                             .freeze

RSpec.describe BSV::Transaction::Beef do
  let(:go_brc62_hex) { BEEF_CONFORMANCE_VECTORS.fetch('BRC62Hex') }

  let(:go_beef_set_hex) { BEEF_CONFORMANCE_VECTORS.fetch('BEEFSet') }

  let(:go_beef_base64) { BEEF_CONFORMANCE_VECTORS.fetch('BEEF') }

  # --- Format conformance ---

  describe 'BRC-62 (V1) conformance' do
    subject(:beef) { described_class.from_hex(go_brc62_hex) }

    it('version matches BEEF_V1') { expect(beef.version).to eq(0xEFBE0001) }
    it('contains 1 BUMP') { expect(beef.bumps.length).to eq(1) }
    it('contains 2 transactions') { expect(beef.transactions.length).to eq(2) }

    it 'wires source transactions during parse' do
      wired = beef.transactions.flat_map { |bt| bt.transaction.inputs.select(&:source_transaction) }
      expect(wired).not_to be_empty
    end

    it 'attaches merkle_path to the mined transaction' do
      mined = beef.transactions.select { |bt| bt.format == described_class::FORMAT_RAW_TX_AND_BUMP }
      expect(mined.length).to eq(1)
      expect(mined.first.transaction.merkle_path).to be_a(BSV::Transaction::MerklePath)
    end
  end

  describe 'BRC-96 (V2) conformance' do
    subject(:beef) { described_class.from_hex(go_beef_set_hex) }

    # Go SDK: require.Equal(t, uint32(4022206466), beef.Version)
    it('version matches BEEF_V2 (4022206466)') { expect(beef.version).to eq(4_022_206_466) }

    # Go SDK: require.Len(t, beef.BUMPs, 3)
    it('contains 3 BUMPs') { expect(beef.bumps.length).to eq(3) }

    # Go SDK: require.Len(t, beef.Transactions, 3)
    it('contains 3 transactions') { expect(beef.transactions.length).to eq(3) }

    # Go SDK: tx := beef.FindTransaction("b1fc0f44ba629dbdffab9e34fcc4faf9dbde3560a7365c55c26fe4daab052aac")
    it 'contains the expected transaction by txid (Go SDK reference)' do
      expected_hex = 'b1fc0f44ba629dbdffab9e34fcc4faf9dbde3560a7365c55c26fe4daab052aac'
      expected_txid = [expected_hex].pack('H*')
      tx = beef.find_transaction(expected_txid)
      expect(tx).not_to be_nil
      expect(tx.txid_hex).to eq(expected_hex)
    end

    it 'V2 round-trips through serialise/parse' do
      expect(beef.to_binary(version: described_class::BEEF_V2).unpack1('H*')).to eq(go_beef_set_hex)
    end
  end

  # --- Base64 V1 fixture (go-sdk `const BEEF`) ---
  # A distinct, larger V1 BEEF payload the go-sdk test suite carries as a
  # base64 string. Exercised here so the vendored fixture has executable
  # coverage rather than sitting unused in the vector file.

  describe 'V1 base64 fixture conformance' do
    subject(:beef) { described_class.from_binary(Base64.strict_decode64(go_beef_base64)) }

    it('version matches BEEF_V1') { expect(beef.version).to eq(0xEFBE0001) }
    it('contains 1 BUMP')         { expect(beef.bumps.length).to eq(1) }
    it('contains 9 transactions') { expect(beef.transactions.length).to eq(9) }
    it('is structurally valid')   { expect(beef.valid?).to be true }
  end

  # --- Atomic BEEF (BRC-95) conformance ---

  describe 'Atomic BEEF (BRC-95) conformance' do
    it 'wraps V2 with magic prefix and subject txid' do
      beef = described_class.from_hex(go_beef_set_hex)
      subject_tx = beef.transactions.last.transaction
      subject_txid = subject_tx.txid

      atomic = beef.to_atomic_binary(subject_txid)

      # BRC-95: first 4 bytes = 0x01010101
      expect(atomic.byteslice(0, 4).unpack1('V')).to eq(0x01010101)
      # BRC-95: next 32 bytes = subject txid in internal byte order (reversed)
      expect(atomic.byteslice(4, 32)).to eq(subject_txid.b.reverse)
      # BRC-95: remainder is V2 BEEF
      inner_version = atomic.byteslice(36, 4).unpack1('V')
      expect(inner_version).to eq(described_class::BEEF_V2)
    end

    it 'round-trips through atomic serialise/parse' do
      beef = described_class.from_hex(go_beef_set_hex)
      subject_txid = beef.transactions.last.txid

      atomic = beef.to_atomic_binary(subject_txid)
      parsed = described_class.from_binary(atomic)

      expect(parsed.subject_txid).to eq(subject_txid)
      expect(parsed.transactions.length).to eq(beef.transactions.length)
    end
  end

  # --- Empty BEEF conformance ---
  # Go SDK: require.Equal(t, "0100beef0000", hex.EncodeToString(beefBytes))
  #         require.Equal(t, "0200beef0000", hex.EncodeToString(beefBytes))

  describe 'empty BEEF conformance' do
    it 'V1 empty BEEF matches Go SDK expected hex' do
      beef = described_class.from_hex('0100beef0000')
      expect(beef.version).to eq(described_class::BEEF_V1)
      expect(beef.bumps).to be_empty
      expect(beef.transactions).to be_empty
    end

    it 'V2 empty BEEF matches Go SDK expected hex' do
      beef = described_class.from_hex('0200beef0000')
      expect(beef.version).to eq(described_class::BEEF_V2)
      expect(beef.bumps).to be_empty
      expect(beef.transactions).to be_empty
    end

    it 'serialises empty V1 BEEF to expected hex' do
      beef = described_class.new
      expect(beef.to_hex).to eq('0100beef0000')
    end

    it 'serialises empty V2 BEEF when requested' do
      beef = described_class.new
      expect(beef.to_binary(version: described_class::BEEF_V2).unpack1('H*')).to eq('0200beef0000')
    end
  end

  # --- V1 → V2 upgrade conformance ---

  describe 'V1 to V2 upgrade' do
    it 'parses V1 and serialises as V2 preserving all data' do
      v1 = described_class.from_hex(go_brc62_hex)
      v2_hex = v1.to_binary(version: described_class::BEEF_V2).unpack1('H*')

      # Should start with V2 magic
      expect(v2_hex[0..7]).to eq('0200beef')

      # Parse back and verify data preserved
      v2 = described_class.from_hex(v2_hex)
      expect(v2.bumps.length).to eq(v1.bumps.length)
      expect(v2.transactions.length).to eq(v1.transactions.length)

      # Transaction IDs preserved
      v1.transactions.each_with_index do |bt, i|
        expect(v2.transactions[i].txid).to eq(bt.txid)
      end
    end
  end

  # --- Merge conformance ---

  describe 'merge conformance' do
    it 'merging identical BEEFs deduplicates' do
      beef1 = described_class.from_hex(go_beef_set_hex)
      beef2 = described_class.from_hex(go_beef_set_hex)

      beef1.merge(beef2)
      expect(beef1.transactions.length).to eq(3)
      expect(beef1.bumps.length).to eq(3)
    end

    it 'merging different BEEFs combines all transactions' do
      beef1 = described_class.from_hex(go_brc62_hex)
      beef2 = described_class.from_hex(go_beef_set_hex)

      beef1.merge(beef2)
      expect(beef1.transactions.length).to eq(5) # 2 + 3
    end

    it 'merged BEEF validates as valid' do
      beef1 = described_class.from_hex(go_brc62_hex)
      beef2 = described_class.from_hex(go_beef_set_hex)

      beef1.merge(beef2)
      expect(beef1.valid?).to be true
    end
  end

  # --- Transaction convenience method conformance ---

  describe 'Transaction.from_beef / Transaction#to_beef' do
    it 'from_beef returns the subject (last) transaction' do
      tx = BSV::Transaction::Transaction.from_beef_hex(go_beef_set_hex)
      beef = described_class.from_hex(go_beef_set_hex)
      expect(tx.txid).to eq(beef.transactions.last.txid)
    end

    it 'to_beef produces valid BEEF that round-trips' do
      original = BSV::Transaction::Transaction.from_beef_hex(go_beef_set_hex)
      rebuilt_hex = original.to_beef_hex

      tx2 = BSV::Transaction::Transaction.from_beef_hex(rebuilt_hex)
      expect(tx2.txid).to eq(original.txid)
    end
  end

  # --- Validation conformance ---

  describe 'validation conformance' do
    it 'Go SDK V2 vector is structurally valid' do
      beef = described_class.from_hex(go_beef_set_hex)
      expect(beef.valid?).to be true
    end

    it 'Go SDK V1 vector is structurally valid' do
      beef = described_class.from_hex(go_brc62_hex)
      expect(beef.valid?).to be true
    end

    it 'invalid version magic is rejected' do
      # Go SDK: binary.LittleEndian.PutUint32(beefBytes[0:4], 0xdeadbeef) → error
      bad_hex = 'efbeadde0000'
      beef = described_class.from_hex(bad_hex)
      # Neither V1 nor V2, so transactions won't be parsed
      expect(beef.transactions).to be_empty
    end
  end
end
