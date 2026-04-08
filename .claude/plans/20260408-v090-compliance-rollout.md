# Plan: 0.9.0 Compliance Review Rollout

**Review**: [`.architecture/reviews/20260408-cross-sdk-compliance-review.md`](../../.architecture/reviews/20260408-cross-sdk-compliance-review.md)
**Target release**: 0.9.0 (major correctness release)
**Previous release**: 0.8.2 (A1 security hotfixes, HLR sgbett/bsv-ruby-sdk#305)
**Next release**: 0.10.0 (Chronicle implementation — separate plan)

## Context

The 2026-04-08 cross-SDK compliance review surfaced 137 findings across 8 phases. After the 10-member project team quorum vote, 54 reached CONSENSUS and 15 more were near-consensus (blocked only by Pragmatic Enforcer's solo YAGNI dissent on Phase 8 architectural items).

**Three-release strategy** agreed by user and Implementation Strategist:

- **0.8.2** — A1 security hotfixes (HLR sgbett/bsv-ruby-sdk#305). Backportable patch. Ships first, not bundled with refactors.
- **0.9.0** — This plan. Everything else from Tier A (non-Chronicle correctness) plus the cross-SDK conformance test suite (C1).
- **0.10.0** — Chronicle implementation (F7.1/F7.2 full semantics with reference vectors). Separate plan.
- **1.0.0 / future** — Tier B Phase 8 wallet/auth architectural epic, pending `bsv-wallet` boundary ADR.

The goal of 0.9.0 is to convert the letter-vs-spirit cluster into letter-matches-spirit. The meta-fix (C1 conformance suite) enables confident execution of the rest by providing authoritative cross-SDK vectors as the regression net.

## Chronicle decision (confirmed)

**Option 1** from the user's release-strategy discussion: **"raise first" slots into 0.9's A6 (interpreter hardening)**. 0.10 remains the release where Chronicle scripts actually execute correctly. 0.9 narrative: "we now fail-safe on opcodes we haven't implemented" — a correctness/safety improvement, not a Chronicle feature. 0.10 narrative: "Chronicle restored opcodes now execute with correct semantics."

Impact on 0.9: 5 trivial changes (promote `OP_SUBSTR`/`OP_LEFT`/`OP_RIGHT`/`OP_LSHIFTNUM`/`OP_RSHIFTNUM` + `OP_VER`/`OP_VERIF`/`OP_VERNOTIF` from silent no-op → `raise InterpreterError::UnimplementedOpcode`). Documented in CHANGELOG with migration note pointing at 0.10.

## Cluster overview (HLRs to create)

0.9.0 contains **eight separate HLRs**, sequenced for dependency safety. Each HLR maps to one cluster from the review's Tier A plus C1:

| HLR | Cluster | Scope | Blocks | Blocked by |
|---|---|---|---|---|
| TBD — C1 | Conformance suite | Cross-SDK vector loader + fixture infrastructure | A3, A5, A6 regression tests | — |
| TBD — A2 | Foundation correctness | F4.2, F1.8, F1.5 | A5 (hex), possibly A3 | — |
| TBD — A3 | BEEF cluster (single PR) | F5.1 → F5.2/F5.4/F5.5/F5.6/F5.7/F5.8/F5.9/F5.10/F5.12/F5.3/F5.20 | — | C1, A2 (for hex module if touched) |
| TBD — A4 | Crypto hardening | F2.1, F2.3, F2.2, F2.4, F2.9 | — | — (parallel with A3) |
| TBD — A5 | Parser correctness | F3.1, F3.2, F3.3, F3.4, F3.5, F3.6, F3.10, F3.12, F3.14/F3.21, F3.16 | — | A2 (F1.5 hex module blocks F3.5) |
| TBD — A6 | Interpreter hardening + Chronicle fail-safe | F7.8, F7.9, F7.10, F7.11, F7.16, F7.18, F7.19, F7.1/F7.2 (raise first) | — | — (parallel with A3/A5) |
| TBD — A7 | Defensive bits (catch-all) | F4.1, F4.3, F4.4, F4.9, F8.7, F8.8, F8.10, F8.14, F8.18 | — | — |

HLR numbers will be assigned as they are created. This plan updates as each is opened.

## Sequencing within 0.9.0

Dependencies inside the cluster graph:

```
C1 ────┬─────────────────────────────────────────┐
       │ provides conformance vectors             │
       ▼                                          ▼
      A2 ─── F1.5 hex module ─────► A5 parser    (used by all regression testing)
      │                              │
      └──────► A7 (can ride along anywhere)
      │
      ▼
      A3 BEEF (single PR, F5.1 first)
      │
      ▼
      A4 crypto hardening (parallel with A3)
      │
      ▼
      A6 interpreter hardening (parallel with A3/A4/A5)
```

**Recommended landing order:**

1. **C1 (conformance suite)** — first, because it becomes the regression net for everything else. Until C1 lands, every other fix has to ship with hand-rolled test vectors.
2. **A2 (foundation correctness)** — F1.5 hex module is a prerequisite for A5. F1.8 (RIPEMD-160) and F4.2 (fee discrepancy) are isolated and can land any time but naturally slot here.
3. **A3 (BEEF cluster)** — largest single chunk. F5.1 byte-order convention must be the first commit in this PR; everything else in A3 depends on the convention being settled. Must use conformance vectors from C1 to verify against TS/Go output.
4. **A4 (crypto hardening)** — can land in parallel with A3; no cross-dependency. F2.1 constant-time scalar mul is the largest item; F2.3/F2.2/F2.4/F2.9 are small.
5. **A5 (parser correctness)** — depends on F1.5 from A2. Can land after A2 in parallel with A3/A4.
6. **A6 (interpreter hardening)** — parallel with A3/A4/A5. Includes the Chronicle "raise first" fail-safe.
7. **A7 (defensive bits)** — opportunistic; individual fixes can ride along with the above HLRs when they touch adjacent code, or land as a catch-all PR at the end.

Total parallelism: after C1 and A2 land, A3 + A4 + A5 + A6 can all proceed concurrently. A7 fills gaps.

## Finding → HLR mapping

Every Tier A finding from the review is assigned to a 0.9.0 HLR below. Findings not appearing here are either in 0.8.2 (A1), deferred to 0.10 (Chronicle full), deferred to Tier B (Phase 8 epic), or in the backlog with no-action resolution.

### C1 — Cross-SDK conformance test suite

Not a review finding per se — a meta-fix unanimously called for by QA, Systems Architect, Maintainability Expert, and Domain Expert. Delivers:

- `spec/conformance/vectors/` directory populated from `go-sdk/primitives/ec/testdata/`, `go-sdk/script/interpreter/data/`, and `ts-sdk/src/**/__tests/` fixture files
- Loader infrastructure for JSON vector files with type-aware parsers
- Initial vector families:
  - `BRC42.private.vectors.json`, `BRC42.public.vectors.json` (key derivation)
  - `SymmetricKey.vectors.json`
  - `sighash_bip143.json`, `sighash_legacy.json`
  - `script_tests.json` (for A5 parser + eventual A6 interpreter use)
  - BEEF round-trip fixtures (new — needed for A3; probably generated from ts-sdk round-trip output)
  - BUMP round-trip fixtures (new — same)
- CI hook to run conformance specs as part of default `rake` target
- Documentation at `docs/testing/conformance-vectors.md` explaining how to add and sync vectors

### A2 — Foundation correctness

| Finding | Severity | Location | Summary |
|---|---|---|---|
| F4.2 | HIGH | `transaction.rb:594-597` + `fee_models/satoshis_per_kilobyte.rb:19` | 5x fee discrepancy: `estimated_fee` 500 sat/kB vs `SatoshisPerKilobyte` default 100 sat/kB. Delegate or deprecate `estimated_fee`. |
| F1.8 | MED | `digest.rb:53-55` | RIPEMD-160 via OpenSSL 3 legacy provider is a portability bomb. Ship pure-Ruby RIPEMD-160 (consistent with pure-Ruby secp256k1 precedent). |
| F1.5 | MED | 19 files scattered | No dedicated hex module; `pack('H*')` silently drops non-hex chars and truncates odd-length. Add `BSV::Primitives::Hex` with `validate!`, `normalise`. **Prerequisite for A5 F3.5.** |

### A3 — BEEF cluster (single coordinated PR)

All findings in this cluster land as ONE pull request. F5.1 must be the first commit in the PR (the byte-order convention that everything else depends on). Verified against C1 conformance vectors from TS/Go.

| Finding | Severity | Location | Summary |
|---|---|---|---|
| **F5.1** | HIGH | `beef.rb:529,648,410-415,58-77` | BeefTx TXID_ONLY byte-order inconsistency — round-trip tests pass because two bugs cancel. Pick TS convention; document and enforce. **Must land first.** |
| F5.2 | HIGH | `merkle_path.rb:230-257` | `compute_root` fails for single-level compound paths; compute `tree_height = max(@path.length, max_offset.bit_length)`. |
| F5.3 | HIGH | `beef.rb` (missing method) | Add `Beef#verify(chain_tracker, allow_txid_only:)` as canonical SPV validation entry point. |
| F5.4 | HIGH | `beef.rb:428-454` | `Beef#valid?` doesn't verify bump↔tx linkage or cross-check computed roots. Add the cross-checks TS's `verifyValid` performs. |
| F5.5 | HIGH | `beef.rb:462-499` | `sort_transactions!` silently drops cycles via Kahn; preserve in `txs_not_valid` bucket. Also call sort before `to_binary`. |
| F5.6 | HIGH | `beef.rb:286-299` | `merge_bump` doesn't retroactively link existing transactions; scan `@transactions` for matching level-0 leaves. |
| F5.7 | HIGH | `beef.rb:309-330,337-355` | `merge_transaction`/`merge_raw_tx` don't upgrade weaker entries (TXID_ONLY → RAW_TX → RAW_TX_AND_BUMP). |
| F5.8 | MED | `beef.rb:236-241` | `find_bump` only looks in transaction-table entries; scan `@bumps` directly. |
| F5.9 | MED | `beef.rb:391` | `Beef#merge` mutates the source BEEF's transactions; construct new BeefTx instances. |
| F5.10 | MED | `merkle_path.rb:50-53,75-111` | `MerklePath` constructor performs no invariant validation; add construction-time checks. |
| F5.12 | MED | `beef.rb:112-149` | `Beef.from_binary` silently accepts unknown versions; raise explicitly. |
| F5.20 | LOW | `transaction.rb:317-337` | `Transaction#to_beef` never calls `sort_transactions!`; add the call. |

**Deferred from A3 (will appear in A7 or later):**
- F5.11 (coinbase maturity check) — LOW, consensus-rule adjacent, not BEEF-structural
- F5.13 — already shipping in A1 (0.8.2)
- F5.14 (`BeefParty`), F5.15–F5.19 — feature parity, deferred to Tier B

### A4 — Crypto hardening

| Finding | Severity | Location | Summary |
|---|---|---|---|
| F2.1 | HIGH | `secp256k1.rb:275-321` + call sites | No constant-time scalar multiplication. Port `Point#mulCT` Montgomery ladder; route secret-scalar paths (`ECDSA.sign_raw`, `PrivateKey#public_key`, both `derive_shared_secret`) through it. Keep wNAF for verify. Bound `WNAF_TABLE_CACHE` with LRU. **Benchmark before merge** — expect 2-3x slowdown on signing but confined to secret-scalar paths. |
| F2.3 | MED | `signature.rb:41,47,59` | `Signature.from_der` accepts non-canonical multi-byte length encodings; reject `bytes[1] & 0x80 != 0` per BIP-66. |
| F2.2 | MED | `ecdsa.rb:26-29,136-139` | Add `force_low_s: true` keyword to `ECDSA.sign` (default preserves current behaviour). |
| F2.4 | MED | `private_key.rb:74-91,114-119` | Drop `compressed: false` from `PrivateKey#to_wif` ("construct only what's valid"). Parse path stays tolerant. |
| F2.9 | LOW | `curve.rb:99-112`, `openssl_ec_shim.rb:147-162` | Delete dead `ec_key_from_public_bytes` / `ec_key_from_private_bytes` and the weak shim DER parser. |

### A5 — Parser correctness

Depends on A2 F1.5 (hex module). Parser-centric cluster, all in `lib/bsv/script/`.

| Finding | Severity | Location | Summary |
|---|---|---|---|
| F3.1 | HIGH | `script.rb:675-735` | Parser doesn't terminate at top-level `OP_RETURN`. Track conditional depth; absorb trailing bytes. |
| F3.12 | HIGH | `script.rb:192-207,389-419` | PushDrop `'before'` lock position unsupported; support both positions, default to `'before'` to match TS. |
| F3.2 | MED | `opcodes.rb:132-138` | Add `OP_NOP11..OP_NOP77` (0xba..0xfc) so `to_asm`/`from_asm` round-trip unknown opcodes. |
| F3.3 | MED | `script.rb:56-69,643-649` | Accept `"0"` and `"-1"` as canonical ASM tokens for OP_0 and OP_1NEGATE. |
| F3.4 | LOW-MED | `script.rb:56-69` | `from_asm` doesn't recognise explicit `OP_PUSHDATA1/2/4 <len> <hex>` token sequences. |
| F3.5 | MED | `script.rb:56-69` | Silent hex truncation via `pack('H*')`. **Depends on F1.5 hex module.** |
| F3.6 | LOW | `chunk.rb:58-64` | `to_asm` emits decimal byte values for unknown opcodes; use `OP_UNKNOWN<n>` sentinel. |
| F3.10 | MED | `script.rb:524-529` | `op_return_data` inherits F3.1 bug plus bare-opcode drop via `select(&:data?)`. Fix after F3.1. |
| F3.14/F3.21 | LOW | `script.rb:623-641` | `encode_minimally` collapses single-byte `[0x00]` to OP_0 (shared bug with TS). Fix locally; raise upstream. |
| F3.16 | MED | `script.rb:675-735` | Classification inconsistency: `chunks`/`type` raise on truncated scripts but byte-level predicates return false. Make `parse_chunks` lenient/clamping. |

### A6 — Interpreter hardening + Chronicle fail-safe

| Finding | Severity | Location | Summary |
|---|---|---|---|
| F7.18 | MED | `stack.rb` (missing) | Add 32MB stack memory limit matching TS. Track incrementally per op (O(1)). **Prerequisite for F7.16, F7.19.** |
| F7.11 | MED | `script_number.rb:18`, `stack.rb:41-43` | Default `pop_int` / arithmetic operand decoding to `require_minimal: true`. Document the 750,000-byte cap's source. |
| F7.9 | MED | `operations/crypto.rb:43-58` | `NULLFAIL` raise-in-no-tx-path. Push false in no-tx path; reserve raise for actual NULLFAIL violations. |
| F7.8 | MED | `operations/crypto.rb:70-73` | Remove 20-key `OP_CHECKMULTISIG` cap (post-Genesis BSV). |
| F7.10 | LOW | `operations/crypto.rb:187-192` | Reject hybrid pubkey prefixes (0x06/0x07) in interpreter CHECKSIG. |
| F7.16 | LOW | `operations/arithmetic.rb:63-81` | `OP_MUL` with large operands is O(n²) DoS. Depends on F7.18. |
| F7.19 | LOW | `interpreter.rb:271-273` | Conditional-depth counter (e.g. 256 levels). Depends on F7.18. |
| **F7.1/F7.2 raise-first** | HIGH | `interpreter.rb:168-172,179-182`, `operations/flow_control.rb:76-92` | Promote Chronicle-slot opcodes (`OP_SUBSTR`, `OP_LEFT`, `OP_RIGHT`, `OP_LSHIFTNUM`, `OP_RSHIFTNUM`, `OP_VER`, `OP_VERIF`, `OP_VERNOTIF`) from silent no-op/reserved → `raise InterpreterError::UnimplementedOpcode`. Full semantics deferred to 0.10. CHANGELOG note pointing at 0.10 for full support. |

### A7 — Defensive bits (catch-all)

Small individually, none block anything. Can land as a single catch-all PR or ride along with adjacent HLRs.

| Finding | Severity | Location | Summary |
|---|---|---|---|
| F4.1 | HIGH | `transaction.rb:789-791` | Change distribution drops outputs on `available <= n` instead of `change <= 0`; match TS. |
| F4.3 | MED | `transaction.rb:608-617` | `estimated_size` silent fallback to 148-byte P2PKH; raise matching TS/Go. |
| F4.4 | MED | `transaction.rb:576-581` | `total_input_satoshis` fallback through `source_transaction.outputs[index].satoshis`. |
| F4.9 | LOW | `transaction.rb:458-489` | `Transaction#sign` doesn't validate outputs have satoshis. Guard raising on nil. |
| F8.7 | MED | `wallet_interface/validators.rb:29` | Lowercase-and-trim protocol ID before validation (silent key-derivation fork). |
| F8.8 | LOW | `wallet_interface/validators.rb:32-33,71-73` | Move permission rules out of `Validators`. |
| F8.10 | LOW | `lib/bsv/wallet_interface.rb` | Namespace cleanup: delete empty `BSV::WalletInterface` shell. Legacy `BSV::Wallet::Wallet` extraction deferred to Tier B. |
| F8.14 | HIGH | `wallet_interface/wallet_client.rb:711-729` | `internalize_action` must verify BEEF merkle proofs against block headers before storing. |
| F8.18 | LOW | `wallet_interface/wallet_client.rb:545-559` | `wire_source_tx_ancestors` unbounded recursion. Add depth cap and cycle detection. |

## Explicitly deferred from 0.9.0

### To 0.10.0 (Chronicle release)

- **F7.1 full semantics** — `OP_SUBSTR`, `OP_LEFT`, `OP_RIGHT`, `OP_LSHIFTNUM`, `OP_RSHIFTNUM` correct execution against `go-sdk/script/interpreter/chronicle_opcodes_test.go` vectors
- **F7.2 full semantics** — `OP_VER`, `OP_VERIF`, `OP_VERNOTIF` correct execution (push 4-byte tx version; version-gated branching)

Note: 0.9.0 ships the "raise first" fail-safe for all eight opcodes via A6. 0.10.0 replaces the raises with correct implementations.

### To Tier B (1.0.0 / future — needs bsv-wallet boundary ADR first)

- **F8.1** — WalletClient rename/extraction
- **F8.2** — BRC-100 substrates (HTTPWalletJSON, HTTPWalletWire, WalletWireTransceiver)
- **F8.3** — BRC-104 HTTP auth transport (`/.well-known/auth`, AuthFetch, SimplifiedFetchTransport)
- **F8.4** — Peer certificate exchange messages (`certificateRequest`, `certificateResponse`)
- **F8.5** — Peer high-level session orchestration API
- **F8.6** — Certificate / VerifiableCertificate / MasterCertificate classes
- **F8.11** — WireFormat translator (snake↔camel at JSON boundaries)
- **F8.12** — `listActions` / `listOutputs` include-flag honouring
- **F8.13** — `sendWith` / `noSend` / batch broadcast model
- **F8.16** — `acquire_certificate` issuance via BRC-104 AuthFetch
- **F8.25** — `BSV::Attest` extraction to `bsv-attest` companion gem

### Backlog (no action, documented in review)

- All 62 specialist/niche findings that didn't clear quorum
- The 4 controversial findings resolved as "defer" (F2.5, F2.8, F6.1, F8.19 — all cross-SDK coordination items)
- The 1 controversial finding resolved as "don't fix" (F7.6 — `findAndDelete` is dead code under FORKID-only sighash per Cryptography Specialist)

## Release criteria for 0.9.0

- [ ] C1, A2, A3, A4, A5, A6, A7 HLRs all closed
- [ ] Full test suite green on Ruby 2.7, 3.0, 3.1, 3.2, 3.3, 3.4
- [ ] Conformance vector suite green (cross-SDK BEEF/sighash/BRC-42 vectors)
- [ ] RuboCop clean
- [ ] CHANGELOG entry under `sdk-0.9.0` covering every finding ID addressed
- [ ] CHANGELOG migration notes for:
  - F4.2 (fee rate change — if `estimated_fee` is delegated, document new default)
  - F2.4 (WIF `compressed: false` dropped — breaking change for any caller using it)
  - F3.12 (PushDrop default lock position change — breaking change for any caller producing PushDrop tokens)
  - F7.11 (minimal encoding default flipped — breaking change for any caller decoding non-minimal script numbers)
  - F7.1/F7.2 raise-first — breaking change for any caller running Chronicle opcodes through the interpreter; advertise 0.10 as the implementation target
- [ ] Release notes prominently reference the 2026-04-08 compliance review document

## Open questions to resolve as HLRs are written

1. **C1 vector sync strategy**: vendor vectors in-repo (static snapshot) vs git-submodule reference SDKs (live sync)? Recommend static snapshot with documented sync procedure — submodules complicate CI and aren't worth it for a regression test suite.
2. **F5.1 byte-order convention**: pick TS's (display-hex in memory, wire-internal-order on the wire) or a different convention? Recommend TS's. Document in `BeefTx` class doc.
3. **F2.1 constant-time implementation**: pure-Ruby Montgomery ladder (matches secp256k1 precedent) or extract to a C extension? Recommend pure-Ruby for consistency — benchmark will reveal if it's unacceptable.
4. **A7 PR strategy**: one big catch-all PR or scatter fixes into the other HLRs' PRs as they touch adjacent code? Recommend scatter — most A7 findings naturally belong next to an A3/A4/A5/A6 fix.
5. **F8.14 BEEF header verification**: should this live in `internalize_action` or in `Beef#verify` (from F5.3 in A3)? Probably `Beef#verify` with `internalize_action` calling it. Clarify in the A3 HLR.

## Status

| Step | Status | Notes |
|---|---|---|
| Plan written | ✅ | this document |
| C1 HLR | pending | open next |
| A2 HLR | pending | after C1 |
| A3 HLR | pending | after A2 F1.5 |
| A4 HLR | pending | parallel with A3 |
| A5 HLR | pending | after A2 F1.5 |
| A6 HLR | pending | parallel with A3/A4/A5 |
| A7 HLR | pending | opportunistic |

HLR numbers populated in the **Cluster overview** table at the top of this document as each is opened.
