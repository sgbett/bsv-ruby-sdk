# frozen_string_literal: true

require 'spec_helper'

# Protocol conformance: Bitcoin Core script_tests vectors
#
# Vector file: `spec/conformance/vectors/script_tests.json`
# Source: go-sdk `script/interpreter/data/script_tests.json` (vendored
# byte-identical; see `spec/conformance/vectors/README.md` for provenance).
#
# Row format (for rows with length > 1):
#   [[wit..., amount]?, scriptSig, scriptPubKey, flags, expected_scripterror, ...comments]
#
# Single-element rows are copyright/format comments and are filtered out.
#
# These vectors are vendored here to serve two downstream consumers:
#
#   - **A5 (parser correctness)** — structural assertions on
#     `scriptSig`/`scriptPubKey` strings: parsing, round-trip, type
#     detection. Blocked on several A5 findings, most notably:
#       * F3.3 — accept `"0"` / `"-1"` as canonical ASM tokens
#       * F3.4 — recognise `OP_PUSHDATA1/2/4 <len> <hex>` token sequences
#       * plus the Bitcoin Core ASM dialect itself (no `OP_` prefix on
#         opcode names, literal `'string'` pushes, `0x02 0x0100` raw hex
#         push syntax) which `Script.from_asm` does not currently parse.
#
#   - **A6 (interpreter hardening)** — behavioural assertions that evaluate
#     each script against its expected `expected_scripterror` result under
#     the listed flags. Requires the interpreter work in A6.
#
# Executing these vectors is explicitly out of scope for C1. This spec
# exists only to establish that the file is vendored, loadable, and has
# the expected shape.

RSpec.describe 'Bitcoin Core script_tests vectors' do
  it 'vectors are vendored and loadable' do
    rows = ConformanceVectors.load_rows('script_tests.json')
    expect(rows).not_to be_empty
    # Every real test row has at least the 4 required columns:
    #   scriptSig, scriptPubKey, flags, expected_scripterror
    expect(rows).to all(satisfy { |r| r.length >= 4 })
  end

  it 'contains a substantial number of test vectors' do
    rows = ConformanceVectors.load_rows('script_tests.json')
    # The full Bitcoin Core corpus is ~1,400 rows. We want to fail loudly
    # if a future sync accidentally truncates the file.
    expect(rows.length).to be > 1000
  end

  skip 'parser execution deferred to A5; interpreter execution deferred to A6'
end
