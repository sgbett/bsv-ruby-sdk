# frozen_string_literal: true

require 'spec_helper'

# Protocol conformance: BIP-143 sighash vectors
#
# Vector file: `spec/conformance/vectors/sighash_bip143.json`
# Source: go-sdk `script/interpreter/data/sighash_bip143.json` (vendored
# byte-identical; see `spec/conformance/vectors/README.md` for provenance).
#
# Each row is `[raw_tx_hex, subscript_hex, input_index, hashType, expected_sighash_hex]`
# where `expected_sighash_hex` is the sighash in reversed (display) byte order.
#
# These vectors are skipped against the current master:
#
#   1. The vectors are Bitcoin Core BIP-143 vectors; their hashType values
#      are 32-bit signed integers that only sometimes include the FORKID bit
#      (0x40). `BSV::Transaction::Tx#sighash_preimage` correctly
#      raises `ArgumentError` for non-FORKID hashTypes, matching BSV
#      consensus (all BSV sighashes must set FORKID post-UAHF).
#
#   2. Each vector also requires setting `source_satoshis = 0` and a bespoke
#      subscript on the input being signed — neither reachable through the
#      public Transaction/Input API without constructing a synthetic source
#      transaction first.
#
#   3. ts-sdk bypasses both constraints via `TransactionSignature.format(...,
#      ignoreChronicle: true)` (see `ts-sdk/src/transaction/__tests/Transaction.test.ts`
#      around line 988), which is a test-only code path.
#
# Executing these vectors against the Ruby SDK would require either:
#   (a) Adding an equivalent test-only sighash preimage entry point that
#       accepts non-FORKID hashTypes and arbitrary (subscript, satoshis)
#       overrides, OR
#   (b) Re-generating the vector file from ts-sdk/go-sdk using FORKID
#       hashTypes throughout, producing a BSV-native sighash fixture set.
#
# Follow-up: tracked as part of the A2 (foundation correctness) cluster in
# `.claude/plans/20260408-v090-compliance-rollout.md`. The vectors remain
# vendored here so that whichever path is chosen has the canonical data to
# compare against.

RSpec.describe 'BIP-143 sighash vectors' do
  it 'vectors are vendored and loadable' do
    rows = ConformanceVectors.load_rows('sighash_bip143.json')
    expect(rows).not_to be_empty
    expect(rows.first.length).to eq(5)
  end

  skip 'execution deferred to A2 — see file header for details'
end
