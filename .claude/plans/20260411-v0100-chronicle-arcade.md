# Plan: bsv-sdk 0.10.0 — Chronicle + Arcade + Directory Restructure

**Previous release**: bsv-sdk 0.9.0 (cross-SDK compliance rollout)
**Plan**: `.claude/plans/20260408-v090-compliance-rollout.md`

## Context

The tenth minor release bundles three pillars into a cohesive milestone:

1. **Directory restructure** (cosmetic, already merged — PR #327)
2. **Chronicle opcode support** (big ticket — implementing BSV's restored opcodes)
3. **Arcade switch** (infrastructure — Chaintracks chain tracker, default broadcaster, batch broadcast)

0.9.0 shipped "raise first" fail-safes for 8 Chronicle opcodes (F7.1/F7.2). This release replaces those raises with correct implementations. The Arcade work adds a proper chain tracker for SPV verification — the missing link that makes `Beef#verify(chain_tracker)` actually useful out of the box.

---

## Pillar 1: Directory Restructure (DONE)

PR #327 merged. Files now live under `gem/bsv-sdk/`, `gem/bsv-wallet/`, `gem/bsv-attest/`. Part of the release narrative; no further work needed.

---

## Pillar 2: Chronicle Opcodes

### Opcodes to implement

| Opcode | Byte | Category | Semantics | Current state |
|--------|------|----------|-----------|---------------|
| OP_SUBSTR | 0xb3 | splice | Pop len, offset, buf → push `buf[offset, len]` | raises UnimplementedOpcode |
| OP_LEFT | 0xb4 | splice | Pop len, buf → push first len bytes | raises UnimplementedOpcode |
| OP_RIGHT | 0xb5 | splice | Pop len, buf → push last len bytes | raises UnimplementedOpcode |
| OP_LSHIFTNUM | 0xb6 | arithmetic | Pop bits, n → push `n << bits` (arithmetic) | raises UnimplementedOpcode |
| OP_RSHIFTNUM | 0xb7 | arithmetic | Pop bits, n → push `n >> bits` (sign-preserving) | raises UnimplementedOpcode |
| OP_VER | 0x62 | flow control | Push 4-byte LE tx version | raises UnimplementedOpcode |
| OP_VERIF | 0x65 | flow control | Pop expected version; match → conditional true | raises UnimplementedOpcode |
| OP_VERNOTIF | 0x66 | flow control | Pop expected version; no match → conditional true | raises UnimplementedOpcode |
| OP_2MUL | 0x8d | arithmetic | Pop n → push n×2 | raises DisabledOpcode |
| OP_2DIV | 0x8e | arithmetic | Pop n → push n÷2 (truncated toward zero) | raises DisabledOpcode |

### Reference implementations

- **Go SDK**: `go-sdk/script/interpreter/chronicle_opcodes_test.go` (~609 lines, ~50 test cases)
- **TS SDK**: `ts-sdk/src/script/Spend.ts` (implementations), `ts-sdk/src/script/__tests/ChronicleOpcodes.test.ts` (~650 lines, ~80 test cases)

### File changes

**`gem/bsv-sdk/lib/bsv/script/interpreter/error.rb`**
- Add `MISSING_TX_CONTEXT = :missing_tx_context` error code (for OP_VER without tx)

**`gem/bsv-sdk/lib/bsv/script/interpreter/operations/splice.rb`**
- Add `op_substr`: pop len (int), offset (int), data (bytes). Validate `offset >= 0 && offset < size && len >= 0 && len <= size - offset`. Push `data.byteslice(offset, len)`. Raise `INVALID_INPUT_LENGTH` on out-of-range.
- Add `op_left`: pop len (int), data (bytes). Validate `len >= 0 && len <= size`. Push `data.byteslice(0, len)`. Raise on out-of-range. (Matches TS/Go — does NOT clamp to size.)
- Add `op_right`: pop len (int), data (bytes). Validate `len >= 0 && len <= size`. Push `data.byteslice(size - len, len)`. Raise on out-of-range.

**`gem/bsv-sdk/lib/bsv/script/interpreter/operations/arithmetic.rb`**
- Add `op_2mul`: pop n (int), push `n * ScriptNumber.new(2)`. Replaces `op_disabled`.
- Add `op_2div`: pop n (int), push `n / ScriptNumber.new(2)`. Replaces `op_disabled`.
- Add `op_lshiftnum`: pop bits (int), pop value (int). Validate bits >= 0. Push `ScriptNumber.new(value.value << bits.to_i32)`. Stack memory cap catches oversized results.
- Add `op_rshiftnum`: pop bits (int), pop value (int). Validate bits >= 0. Push `ScriptNumber.new(value.value >> bits.to_i32)`. Ruby's `Integer#>>` is arithmetic (sign-preserving), which is correct.
- Remove `op_disabled` method (dead code after OP_2MUL/OP_2DIV restoration).

**`gem/bsv-sdk/lib/bsv/script/interpreter/operations/flow_control.rb`**
- Add `op_ver`: raise `MISSING_TX_CONTEXT` if `@tx.nil?`. Encode `@tx.version` as 4-byte LE (`[@tx.version].pack('V')`). Push bytes.
- Add `op_verif`: conditional opcode. In executing branch: pop bytes, compare raw 4-byte LE against `@tx.version`. Match → push `:true` to `@cond_stack`. Mismatch or wrong size → push `:false`. In non-executing branch: push `:false` (nesting tracking, no stack pop). Push `false` to `@else_stack`.
- Add `op_vernotif`: same as `op_verif` but inverted — match → `:false`, mismatch → `:true`.
- Add private helper `tx_version_bytes` returning `[@tx.version].pack('V')`.
- `op_unimplemented` becomes dead code — leave for safety but no dispatch routes to it.

**`gem/bsv-sdk/lib/bsv/script/interpreter/interpreter.rb`**
- Add `Opcodes::OP_VERIF, Opcodes::OP_VERNOTIF` to `CONDITIONAL_OPCODES` array (they must be dispatched in non-executing branches for nesting tracking).
- Replace the combined unimplemented `when` clause (lines 185-188) with individual dispatch:
  - `when Opcodes::OP_VER then op_ver`
  - `when Opcodes::OP_VERIF then op_verif`
  - `when Opcodes::OP_VERNOTIF then op_vernotif`
  - `when Opcodes::OP_SUBSTR then op_substr`
  - `when Opcodes::OP_LEFT then op_left`
  - `when Opcodes::OP_RIGHT then op_right`
  - `when Opcodes::OP_LSHIFTNUM then op_lshiftnum`
  - `when Opcodes::OP_RSHIFTNUM then op_rshiftnum`
- Replace `OP_2MUL, OP_2DIV → op_disabled` (line 229-230) with:
  - `when Opcodes::OP_2MUL then op_2mul`
  - `when Opcodes::OP_2DIV then op_2div`

### Test file

**`spec/bsv/script/interpreter/operations/chronicle_spec.rb`** (new)

~55 test cases ported from Go and TS reference tests, covering:

- **OP_SUBSTR**: "HelloWorld" extraction, single char, full string, out-of-range errors, negative offset/len, empty data
- **OP_LEFT/OP_RIGHT**: first/last N bytes, zero bytes → empty, full length → whole string, exceeds size → error
- **OP_LSHIFTNUM/OP_RSHIFTNUM**: 1<<2=4, identity (shift by 0), shift to zero, negative number sign preservation, large shifts
- **OP_2MUL/OP_2DIV**: basic multiplication/division, zero, negative, truncation
- **OP_VER**: pushes 4-byte LE version 1, version 2, SIZE check = 4, no tx context → MISSING_TX_CONTEXT
- **OP_VERIF**: matching version → true branch, non-matching → else branch, non-4-byte item → false, nested conditionals
- **OP_VERNOTIF**: inverse of OP_VERIF

Also update:
- `spec/bsv/script/interpreter/hardening_spec.rb` — remove or update the "raise UnimplementedOpcode" tests (they should now test correct execution instead)
- `spec/bsv/script/interpreter/operations/flow_control_spec.rb` — update OP_VER/VERIF/VERNOTIF tests
- `spec/bsv/script/interpreter/operations/arithmetic_spec.rb` — remove any `op_disabled` tests for OP_2MUL/OP_2DIV

---

## Pillar 3: Arcade Switch

### New: Chaintracks chain tracker

**`gem/bsv-sdk/lib/bsv/transaction/chain_trackers/chaintracks.rb`** (new, ~90 lines)

Follows `WhatsOnChain` pattern:

```ruby
class Chaintracks < ChainTracker
  MAINNET_URL = 'https://arcade.gorillapool.io'
  TESTNET_URL = 'https://testnet.arcade.gorillapool.io'

  def initialize(url: MAINNET_URL, api_key: nil, http_client: nil)
  def valid_root_for_height?(root, height)
    # GET /chaintracks/v2/header/height/{height}
    # Compare response body 'merkleRoot' with root (case-insensitive)
  end
  def current_height
    # GET /chaintracks/v2/tip
    # Return response body 'height'
  end
end
```

Uses Arcade's Chaintracks v2 API (not the legacy v1 or the /api/v1/chain/merkleroot/verify pattern from some reference SDKs). The v2 endpoints return full block headers with `merkleRoot` field — simpler and more direct.

**`gem/bsv-sdk/lib/bsv/transaction/chain_trackers.rb`** (modify)
- Add `autoload :Chaintracks, 'bsv/transaction/chain_trackers/chaintracks'`
- Add `self.default(testnet: false, api_key: nil)` factory returning a `Chaintracks` instance

### Modified: ARC broadcaster

**`gem/bsv-sdk/lib/bsv/network/arc.rb`** (modify)

Three additions:

1. **`self.default(testnet: false, **opts)`** — class method factory
   - Mainnet: `https://arc.gorillapool.io`
   - Testnet: `https://testnet.arc.gorillapool.io`
   - Matches TS/Go/Py default broadcaster pattern

2. **`broadcast_many(txs, wait_for: nil, skip_fee_validation: nil, skip_script_validation: nil)`** — batch broadcast
   - POST to `{@url}/v1/txs`
   - Body: JSON array of `{ rawTx: hex }` (each tx independently EF-fallback encoded)
   - Returns array of `BroadcastResponse`
   - Handles per-tx failure detection (same rejected-status logic as single broadcast)

3. **Skip-validation keyword args** on `broadcast` and `broadcast_many`:
   - `skip_fee_validation: true` → `X-SkipFeeValidation: true` header
   - `skip_script_validation: true` → `X-SkipScriptValidation: true` header
   - Extract header building into private `build_request_headers(wait_for:, skip_fee_validation:, skip_script_validation:)` to avoid duplication

### Test files

**`spec/bsv/transaction/chain_trackers/chaintracks_spec.rb`** (new, ~100 lines)
- `valid_root_for_height?` true on match, false on mismatch, false on 404, raises ChainProviderError on 5xx
- `current_height` returns height from tip, raises on failure
- API key authentication header
- URL construction for mainnet/testnet
- `.default` factory method

**`spec/bsv/network/arc_spec.rb`** (modify)
- `describe '.default'` — mainnet/testnet URL construction, option passthrough
- `describe '#broadcast_many'` — batch POST to `/v1/txs`, JSON body format, mixed success/failure, EF fallback
- `describe 'skip-validation headers'` — X-SkipFeeValidation and X-SkipScriptValidation set when requested

### LivePolicy verification

`LivePolicy` already defaults to `https://arc.gorillapool.io` and fetches `/v1/policy`. Arcade serves this endpoint for ARC compatibility. Verify during integration testing that the response shape parses correctly — the Arcade policy response has `miningFeeBytes` and `miningFeeSatoshis` at root level, while the existing `extract_rate` method looks for `policy.fees.miningFee.{satoshis,bytes}`. May need to add a fallback extraction path for the flat structure.

---

## Sequencing

```
Phase 0: Verify 0.9.0 is clean (all specs pass, master is stable)

Phase 1: Chronicle opcodes (Pillar 2)
  1a. Error code addition (error.rb)
  1b. Splice ops: op_substr, op_left, op_right (splice.rb)    ─┐
  1c. Arithmetic ops: op_2mul, op_2div, op_lshiftnum,          │ parallel
      op_rshiftnum (arithmetic.rb)                             ─┘
  1d. Version ops: op_ver, op_verif, op_vernotif (flow_control.rb)
  1e. Dispatch table rewiring + CONDITIONAL_OPCODES (interpreter.rb)
  1f. Chronicle test suite (chronicle_spec.rb) + update existing specs

Phase 2: Arcade switch (Pillar 3) — can run in parallel with Phase 1
  2a. Chaintracks chain tracker (chaintracks.rb + spec)
  2b. ARC default/broadcast_many/skip-validation (arc.rb + spec)
  2c. ChainTrackers.default factory + LivePolicy verification

Phase 3: Release
  3a. Update version.rb to 0.10.0
  3b. CHANGELOG.md with Chronicle and Arcade sections
  3c. Full test suite pass + RuboCop
```

Phases 1 and 2 are independent — no cross-dependencies.

---

## HLR structure

Two HLRs (Pillar 1 is already done):

- **HLR: Chronicle opcode implementation** — F7.1/F7.2 full semantics. Label `project:hlr`. Covers all 10 opcodes + test suite.
- **HLR: Arcade integration** — Chaintracks chain tracker, default broadcaster, batch broadcast. Label `project:hlr`.

---

## Release criteria

- [ ] All existing specs pass (zero regressions)
- [ ] All 10 Chronicle opcodes execute correctly (~55 new test cases)
- [ ] Chaintracks chain tracker works with mock HTTP client (~15 new test cases)
- [ ] ARC.default, broadcast_many, skip-validation work (~10 new test cases)
- [ ] No `op_unimplemented` calls remain in dispatch table
- [ ] No `op_disabled` calls remain in dispatch table
- [ ] `CONDITIONAL_OPCODES` includes OP_VERIF and OP_VERNOTIF
- [ ] RuboCop clean
- [ ] CHANGELOG updated
- [ ] Version = 0.10.0

---

## Key files

### Chronicle (modify)
- `gem/bsv-sdk/lib/bsv/script/interpreter/error.rb`
- `gem/bsv-sdk/lib/bsv/script/interpreter/interpreter.rb`
- `gem/bsv-sdk/lib/bsv/script/interpreter/operations/flow_control.rb`
- `gem/bsv-sdk/lib/bsv/script/interpreter/operations/splice.rb`
- `gem/bsv-sdk/lib/bsv/script/interpreter/operations/arithmetic.rb`

### Chronicle (new)
- `spec/bsv/script/interpreter/operations/chronicle_spec.rb`

### Arcade (modify)
- `gem/bsv-sdk/lib/bsv/network/arc.rb`
- `gem/bsv-sdk/lib/bsv/transaction/chain_trackers.rb`

### Arcade (new)
- `gem/bsv-sdk/lib/bsv/transaction/chain_trackers/chaintracks.rb`
- `spec/bsv/transaction/chain_trackers/chaintracks_spec.rb`

### Release
- `gem/bsv-sdk/lib/bsv/version.rb`
- `CHANGELOG.md`
