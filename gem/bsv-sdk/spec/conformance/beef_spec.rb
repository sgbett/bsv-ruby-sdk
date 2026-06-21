# frozen_string_literal: true

require 'spec_helper'
require 'base64'

# Protocol conformance: BEEF serialisation (BRC-62/95/96)
#
# Canonical vectors sourced from the ts-stack conformance corpus:
#   sdk/transactions/serialization.json (tag: "beef" vectors: tx-003, tx-006)
#   regressions/beef-isvalid-hydration.json
#   regressions/beef-v2-txid-panic.json
#
# Ruby-local fixtures (BEEF_V2_SET_HEX, BEEF_V1_B64, BEEF_ISSUE96_HEX) live in
# spec/support/beef_local_fixtures.rb so they auto-load regardless of which
# spec file RSpec hits first. Upstream coverage suggestion: issue #849.

RSpec.describe 'BEEF serialisation conformance (BRC-62/95/96)' do
  # Helper: find a specific vector from the serialization canonical file
  def find_serialization_vector(vector_id)
    result = nil
    ConformanceVectors.each_canonical_vector('sdk.transactions.serialization') do |_envelope, vector|
      result = vector if vector['id'] == vector_id
    end
    raise "Vector #{vector_id} not found in sdk.transactions.serialization" if result.nil?

    result
  end

  # --- Canonical vectors: tx-003 (BEEF V1, 1 BUMP, 2 transactions) ---

  describe 'canonical tx-003 (BEEF_V1, 1 BUMP, 2 transactions)' do
    subject(:beef) { BSV::Transaction::Beef.from_hex(vector.dig('input', 'beef_hex')) }

    let(:vector) { find_serialization_vector('tx-003') }

    it 'version matches BEEF_V1 (0xEFBE0001)' do
      expect(beef.version).to eq(0xEFBE0001)
    end

    it 'contains 1 BUMP' do
      expect(beef.bumps.length).to eq(1)
    end

    it 'contains 2 transactions' do
      expect(beef.transactions.length).to eq(2)
    end

    it 'wires source transactions during parse' do
      wired = beef.transactions
                  .grep_v(BSV::Transaction::Beef::TxidOnlyEntry)
                  .flat_map { |bt| bt.transaction.inputs.select(&:source_transaction) }
      expect(wired).not_to be_empty
    end

    it 'attaches merkle_path to the proven transaction' do
      proven = beef.transactions.grep(BSV::Transaction::Beef::ProvenTxEntry)
      expect(proven.length).to eq(1)
      expect(proven.first.transaction.merkle_path).to be_a(BSV::Transaction::MerklePath)
    end

    it 'computes the expected merkle root from the canonical vector' do
      expected_root = vector.dig('expected', 'merkle_root')
      proven = beef.transactions.grep(BSV::Transaction::Beef::ProvenTxEntry).first
      actual_root = proven.transaction.merkle_path.compute_root_hex(proven.transaction.txid_hex)
      expect(actual_root).to eq(expected_root)
    end

    it 'round-trips through V1 serialise/parse' do
      expect(beef.to_hex).to eq(vector.dig('input', 'beef_hex'))
    end
  end

  # --- Canonical vector: tx-006 (non-atomic BEEF does not carry an atomic subject) ---
  #
  # The TS SDK has a dedicated fromAtomicBEEF method that rejects non-atomic BEEF.
  # The Ruby SDK unifies parsing in from_binary; atomic detection is via the 0x01010101
  # version magic. A V1 BEEF parsed via from_hex has subject_wtxid == nil (no atomic prefix).

  describe 'canonical tx-006 (non-atomic BEEF lacks an atomic subject txid)' do
    let(:vector) { find_serialization_vector('tx-006') }

    it 'parsing a V1 BEEF produces no atomic subject (subject_wtxid is nil)' do
      beef = BSV::Transaction::Beef.from_hex(vector.dig('input', 'beef_hex'))
      expect(beef.subject_wtxid).to be_nil
    end
  end

  # --- Canonical regressions: beef-isvalid-hydration (go-sdk#167) ---
  #
  # KNOWN DISCREPANCY (see issue #844 comment):
  # The regression BEEF has a BUMP where level-0 leaves have flags=0x00 (no txid flag).
  # MerklePath#initialize requires at least one txid-flagged leaf at level 0, causing
  # ArgumentError: "level 0 of path must contain at least one txid-flagged element".
  # The go-sdk accepts this BUMP structure. The Ruby SDK is over-strict.
  # Vectors are pending until MerklePath is relaxed to match cross-SDK behaviour.

  describe 'regression: beef-isvalid-hydration (go-sdk#167)' do
    let(:envelope) { ConformanceVectors.canonical_regression('beef-isvalid-hydration') }

    it 'BEEF_V1 with parent + child tx parses without error (0001)' do
      pending 'MerklePath over-strict: level-0 leaf with flags=0x00 raises ArgumentError (see issue #844)'
      vector = envelope['vectors'].find { |v| v['id'] == 'regression.beef.isvalid-hydration.0001' }
      expect { BSV::Transaction::Beef.from_hex(vector.dig('input', 'beef_hex')) }.not_to raise_error
    end

    it 'BEEF_V1 with parent + child tx is structurally valid (0001)' do
      pending 'MerklePath over-strict: level-0 leaf with flags=0x00 raises ArgumentError (see issue #844)'
      vector = envelope['vectors'].find { |v| v['id'] == 'regression.beef.isvalid-hydration.0001' }
      beef = BSV::Transaction::Beef.from_hex(vector.dig('input', 'beef_hex'))
      expect(beef.valid?).to be true
    end

    it 'BEEF_V1 with parent + child tx exposes a non-nil txid for the newest tx (0002)' do
      pending 'MerklePath over-strict: level-0 leaf with flags=0x00 raises ArgumentError (see issue #844)'
      vector = envelope['vectors'].find { |v| v['id'] == 'regression.beef.isvalid-hydration.0002' }
      beef = BSV::Transaction::Beef.from_hex(vector.dig('input', 'beef_hex'))
      expect(beef.transactions.last.dtxid).not_to be_nil
    end
  end

  # --- Canonical regressions: beef-v2-txid-panic (go-sdk#306) ---
  #
  # The Ruby SDK must not recapitulate the go-sdk#306 bug (nil transaction on BEEF_V2 parse).

  describe 'regression: beef-v2-txid-panic (go-sdk#306)' do
    let(:envelope) { ConformanceVectors.canonical_regression('beef-v2-txid-panic') }

    it 'minimal BEEF_V2 (0 txs) parses without error (0001)' do
      vector = envelope['vectors'].find { |v| v['id'] == 'regression.beef.v2-txid-panic.0001' }
      expect { BSV::Transaction::Beef.from_hex(vector.dig('input', 'beef_hex')) }.not_to raise_error
    end

    it 'minimal BEEF_V2 with no transactions has an empty transactions list (0001)' do
      vector = envelope['vectors'].find { |v| v['id'] == 'regression.beef.v2-txid-panic.0001' }
      beef = BSV::Transaction::Beef.from_hex(vector.dig('input', 'beef_hex'))
      # expected.txid_non_null is false — no transactions means no subject tx
      expect(beef.transactions).to be_empty
    end
  end

  # --- Ruby-local fixtures (no canonical upstream equivalent) ---
  # See https://github.com/sgbett/bsv-ruby-sdk/issues/849 for upstream coverage suggestion.

  describe 'Ruby-local BEEFSet (V2, 3 BUMPs, 3 transactions)' do
    subject(:beef) { BSV::Transaction::Beef.from_hex(BEEF_V2_SET_HEX) }

    it 'version matches BEEF_V2 (4022206466)' do
      expect(beef.version).to eq(4_022_206_466)
    end

    it 'contains 3 BUMPs' do
      expect(beef.bumps.length).to eq(3)
    end

    it 'contains 3 transactions' do
      expect(beef.transactions.length).to eq(3)
    end

    it 'contains the expected transaction by display-order txid' do
      expected_hex = 'b1fc0f44ba629dbdffab9e34fcc4faf9dbde3560a7365c55c26fe4daab052aac'
      expected_wtxid = [expected_hex].pack('H*').reverse
      tx = beef.find_transaction(expected_wtxid)
      expect(tx).not_to be_nil
      expect(tx.txid_hex).to eq(expected_hex)
    end

    it 'round-trips through V2 serialise/parse' do
      expect(beef.to_binary(version: BSV::Transaction::Beef::BEEF_V2).unpack1('H*')).to eq(BEEF_V2_SET_HEX)
    end

    it 'is structurally valid' do
      expect(beef.valid?).to be true
    end
  end

  describe 'Ruby-local base64 BEEF (V1, 1 BUMP, 9 transactions)' do
    subject(:beef) { BSV::Transaction::Beef.from_binary(Base64.strict_decode64(BEEF_V1_B64)) }

    it 'version matches BEEF_V1' do
      expect(beef.version).to eq(0xEFBE0001)
    end

    it 'contains 1 BUMP' do
      expect(beef.bumps.length).to eq(1)
    end

    it 'contains 9 transactions' do
      expect(beef.transactions.length).to eq(9)
    end

    it 'is structurally valid' do
      expect(beef.valid?).to be true
    end
  end

  describe 'Ruby-local Issue96BeefHex (V1, 5 BUMPs, 14 transactions, go-sdk#96)' do
    subject(:beef) { BSV::Transaction::Beef.from_hex(BEEF_ISSUE96_HEX) }

    it 'version matches BEEF_V1' do
      expect(beef.version).to eq(0xEFBE0001)
    end

    it 'contains 5 BUMPs' do
      expect(beef.bumps.length).to eq(5)
    end

    it 'contains 14 transactions' do
      expect(beef.transactions.length).to eq(14)
    end

    it 'is structurally valid' do
      expect(beef.valid?).to be true
    end
  end

  # --- Structural behaviour tests (no canonical upstream equivalent) ---

  describe 'TXID_ONLY byte-order consistency (F5.1)' do
    let(:brc62_beef) do
      BSV::Transaction::Beef.from_hex(find_serialization_vector('tx-003').dig('input', 'beef_hex'))
    end

    it 'make_txid_only preserves wtxid' do
      beef = brc62_beef
      bt = beef.transactions.first
      original_wtxid = bt.wtxid

      beef.make_txid_only(bt.wtxid)
      txid_only_entry = beef.transactions.find { |e| e.is_a?(BSV::Transaction::Beef::TxidOnlyEntry) }
      expect(txid_only_entry).not_to be_nil
      expect(txid_only_entry.wtxid).to eq(original_wtxid)
    end

    it 'TXID_ONLY round-trips through V2 serialise/parse' do
      beef = brc62_beef
      first_bt = beef.transactions.first
      original_wtxid = first_bt.wtxid

      beef.make_txid_only(first_bt.wtxid)
      v2_bytes = beef.to_binary(version: BSV::Transaction::Beef::BEEF_V2)
      parsed = BSV::Transaction::Beef.from_binary(v2_bytes)

      txid_entry = parsed.transactions.find { |e| e.is_a?(BSV::Transaction::Beef::TxidOnlyEntry) }
      expect(txid_entry).not_to be_nil
      expect(txid_entry.wtxid).to eq(original_wtxid)
    end

    it 'TXID_ONLY entries are included in known txids set' do
      beef = BSV::Transaction::Beef.from_hex(BEEF_V2_SET_HEX)
      first_bt = beef.transactions.first

      beef.make_txid_only(first_bt.wtxid)
      expect(beef.valid?(allow_txid_only: true)).to be true
    end
  end

  describe 'Atomic BEEF (BRC-95) conformance' do
    let(:v2_beef) { BSV::Transaction::Beef.from_hex(BEEF_V2_SET_HEX) }

    it 'wraps V2 BEEF with BRC-95 magic prefix and subject txid' do
      last_bt = v2_beef.transactions.last
      atomic = v2_beef.to_atomic_binary(last_bt.wtxid)

      expect(atomic.byteslice(0, 4).unpack1('V')).to eq(0x01010101)
      expect(atomic.byteslice(4, 32)).to eq(last_bt.wtxid)
      expect(atomic.byteslice(36, 4).unpack1('V')).to eq(BSV::Transaction::Beef::BEEF_V2)
    end

    it 'round-trips through atomic serialise/parse' do
      last_bt = v2_beef.transactions.last
      atomic = v2_beef.to_atomic_binary(last_bt.wtxid)
      parsed = BSV::Transaction::Beef.from_binary(atomic)

      expect(parsed.subject_wtxid).to eq(last_bt.wtxid)
      expect(parsed.transactions.length).to eq(v2_beef.transactions.length)
    end
  end

  describe 'empty BEEF conformance' do
    it 'V1 empty BEEF parses correctly' do
      beef = BSV::Transaction::Beef.from_hex('0100beef0000')
      expect(beef.version).to eq(BSV::Transaction::Beef::BEEF_V1)
      expect(beef.bumps).to be_empty
      expect(beef.transactions).to be_empty
    end

    it 'V2 empty BEEF parses correctly' do
      beef = BSV::Transaction::Beef.from_hex('0200beef0000')
      expect(beef.version).to eq(BSV::Transaction::Beef::BEEF_V2)
      expect(beef.bumps).to be_empty
      expect(beef.transactions).to be_empty
    end

    it 'serialises empty V1 BEEF to expected hex' do
      expect(BSV::Transaction::Beef.new.to_hex).to eq('0100beef0000')
    end

    it 'serialises empty V2 BEEF when requested' do
      expect(BSV::Transaction::Beef.new.to_binary(version: BSV::Transaction::Beef::BEEF_V2).unpack1('H*'))
        .to eq('0200beef0000')
    end
  end

  describe 'V1 to V2 upgrade' do
    it 'parses V1 and serialises as V2 preserving all data' do
      v1 = BSV::Transaction::Beef.from_hex(find_serialization_vector('tx-003').dig('input', 'beef_hex'))
      v2_hex = v1.to_binary(version: BSV::Transaction::Beef::BEEF_V2).unpack1('H*')
      expect(v2_hex[0..7]).to eq('0200beef')

      v2 = BSV::Transaction::Beef.from_hex(v2_hex)
      expect(v2.bumps.length).to eq(v1.bumps.length)
      expect(v2.transactions.length).to eq(v1.transactions.length)
      v1.transactions.each_with_index do |bt, i|
        expect(v2.transactions[i].wtxid).to eq(bt.wtxid)
      end
    end
  end

  describe 'merge conformance' do
    it 'merging identical BEEFs deduplicates' do
      beef1 = BSV::Transaction::Beef.from_hex(BEEF_V2_SET_HEX)
      beef2 = BSV::Transaction::Beef.from_hex(BEEF_V2_SET_HEX)
      beef1.merge(beef2)
      expect(beef1.transactions.length).to eq(3)
      expect(beef1.bumps.length).to eq(3)
    end

    it 'merging different BEEFs combines all transactions' do
      v1_hex = find_serialization_vector('tx-003').dig('input', 'beef_hex')
      beef1 = BSV::Transaction::Beef.from_hex(v1_hex)
      beef2 = BSV::Transaction::Beef.from_hex(BEEF_V2_SET_HEX)
      beef1.merge(beef2)
      expect(beef1.transactions.length).to eq(5) # 2 + 3
    end

    it 'merged BEEF validates as valid' do
      v1_hex = find_serialization_vector('tx-003').dig('input', 'beef_hex')
      beef1 = BSV::Transaction::Beef.from_hex(v1_hex)
      beef2 = BSV::Transaction::Beef.from_hex(BEEF_V2_SET_HEX)
      beef1.merge(beef2)
      expect(beef1.valid?).to be true
    end
  end

  describe 'Tx.from_beef_hex / Tx#to_beef_hex' do
    it 'from_beef_hex returns the subject (last) transaction' do
      tx = BSV::Transaction::Tx.from_beef_hex(BEEF_V2_SET_HEX)
      beef = BSV::Transaction::Beef.from_hex(BEEF_V2_SET_HEX)
      expect(tx.wtxid).to eq(beef.transactions.last.wtxid)
    end

    it 'to_beef_hex produces valid BEEF that round-trips' do
      original = BSV::Transaction::Tx.from_beef_hex(BEEF_V2_SET_HEX)
      rebuilt_hex = original.to_beef_hex
      tx2 = BSV::Transaction::Tx.from_beef_hex(rebuilt_hex)
      expect(tx2.wtxid).to eq(original.wtxid)
    end
  end

  describe 'validation conformance' do
    it 'V2 local fixture (BEEFSet) is structurally valid' do
      expect(BSV::Transaction::Beef.from_hex(BEEF_V2_SET_HEX).valid?).to be true
    end

    it 'invalid version magic is rejected' do
      expect { BSV::Transaction::Beef.from_hex('efbeadde0000') }
        .to raise_error(ArgumentError, /unknown BEEF version/)
    end
  end
end
