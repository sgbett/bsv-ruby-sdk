# Ruby BSV SDK — Cross-SDK Compliance Review

**Date**: 2026-04-08
**Type**: Multi-phase architectural + conformance audit with QA-flavoured test-strategy review
**Scope**: 8-phase comparison against TypeScript reference SDK (primary), Go/Python SDKs (secondary), and BRC/BIP/RFC specifications (authoritative)
**Reviewers**: 8 downstream phase coordinators + 10-member project team quorum vote

## Supporting artifacts

- **[Consolidated findings digest (137 findings)](../../.claude/artifacts/20260408-cross-sdk-compliance-review-findings.md)** — the normalised source-of-truth list every project-team member voted on, with per-finding severity, file:line references, letter-vs-spirit diagnosis, and recommended action.
- **[Machine-readable quorum tally](../../.claude/artifacts/20260408-cross-sdk-compliance-review-quorum-tally.json)** — per-finding AGREE/DISAGREE/NO_OPINION counts, status (CONSENSUS/CONTROVERSIAL/SPECIALIST), and the names of agreers and dissenters for every finding. Parseable for tooling.

---

## Executive Summary

This document reports the findings of a multi-phase architectural review of the Ruby BSV SDK at `/opt/ruby/bsv-ruby-sdk`, conducted by 8 downstream phase teams and reviewed by a 10-member project team against a quorum requirement of ≥7 votes.

**Motivation**: recurring BEEF-related bug fixes (issues #288, #290, #291, #292, #302) suggested a systemic "letter vs spirit" pattern — the SDK passes its own tests because round-trip symmetry cancels out bugs, but cross-SDK interop and third-party inputs expose divergences from the TypeScript reference. The review sought to find other latent cases of the same pattern.

**Method**:
- 8 downstream phase coordinators (one per phase in the Swift SDK plan) compared the Ruby implementation against the TypeScript reference, using Go and Python SDKs as secondary sources and BRCs/BIPs as authoritative specifications
- Each coordinator acted as implementation comparator, spec researcher, and mediator (sub-agent tool not available in this environment)
- A 10-member project team then reviewed the consolidated findings list, voting AGREE / DISAGREE / NO_OPINION from each specialty perspective
- Quorum threshold: ≥7 AGREE votes for a finding to be accepted with action; <7 flagged for explicit decision

**Scale**:
- 137 findings across 8 phases
- ~1,370 individual votes cast (137 findings × 10 team members)
- 54 findings reached quorum (CONSENSUS)
- 6 findings drew substantive dissent (CONTROVERSIAL)
- 77 findings were niche or blocked by solo dissent (SPECIALIST)

**Headline**: the review confirms the user's hypothesis. The "letter vs spirit" pattern recurs in at least 9 findings across Phases 1, 3, 4, and 5 where Ruby's own tests pass because two errors cancel. The most dangerous cluster is in Phase 5 (BEEF/Network) where 7 HIGH-severity items all share the #302 anti-pattern. A security-critical credential forgery vector (F8.15) was also discovered in Phase 8. Plus several consensus-rule divergences in the interpreter (Phase 7) that would silently produce wrong results on Chronicle-era scripts.

---

## Finding Severity Distribution

| Phase | HIGH | MED | LOW | NONE/POSITIVE | Total |
|---|---|---|---|---|---|
| 1 Foundation | 2 | 3 | 3 | 0 | 8 |
| 2 Keys/Sigs | 1 | 3 | 5 | 0 | 9 |
| 3 Script | 2 | 5 | 11 | 4 | 22 |
| 4 Transactions | 2 | 3 | 6 | 0 | 11 |
| 5 BEEF/Network | 7 | 5 | 8 | 0 | 20 |
| 6 Extended Prim | 0 | 2 | 5 | 9 | 16 |
| 7 Interpreter | 2 | 5 | 8 | 6 | 21 |
| 8 Wallet/Auth | 5 | 7 | 12 | 6 | 30 |
| **Total** | **21** | **33** | **58** | **25** | **137** |

---

## Quorum Status

| Status | Count | Interpretation |
|---|---|---|
| CONSENSUS (≥7 AGREE) | 54 | Accept with action |
| CONTROVERSIAL (≥2 DISAGREE) | 6 | Critical — explicit decision required |
| SPECIALIST / NEAR-CONSENSUS | 77 | Low participation or solo dissent |
| NONE | 0 | N/A |

---

## Cross-Phase Meta-Findings

Every project team member independently identified these patterns:

### 1. "Letter vs spirit" round-trip-test masking

**At least 9 findings** share this pattern: Ruby's own tests pass because two errors cancel, but cross-SDK interop or third-party inputs break.

Specific instances: **F1.3, F1.5, F3.5, F4.1, F5.1, F5.2, F5.6, F5.7, F5.8, F8.12**.

Quality Assurance called this out as "the worst class of bug for DX: no error, wrong result." Maintainability Expert flagged it as "the most dangerous class of bug on the review." Domain Expert said: "Pattern #1 in the cross-phase summary is the single highest-leverage observation in this review."

**Recommendation (unanimous across specialists)**: add a `spec/conformance/` directory loading canonical test vectors produced by TS/Go/Py SDKs. Every protocol-boundary type must have cross-SDK fixture tests, not just self-generated round-trips.

### 2. "Recognise everything, construct only what's valid" inconsistently applied

CLAUDE.md documents this principle but it is not enforced as lint/test policy. The parser is currently over-strict (raises on legitimate inputs: F3.1, F3.5, F3.16) while constructors are over-permissive (allow building invalid forms: F2.4, F3.3). Ruby Expert explicitly flagged F3.16: "Raising on truncated scripts is not a Ruby virtue — it's a layering mistake. The parser layer is required to be tolerant per the Protocol Philosophy."

### 3. Silent-success category

Multiple findings expose APIs that produce wrong results with no error: **F1.2** (empty Base58), **F1.3** (negative VarInt), **F3.5** (hex drop), **F5.5** (cycle drop), **F5.12** (unknown BEEF version), **F7.1/F7.2** (Chronicle no-op), **F5.13** (ARC failure→success).

Security Specialist called this "an integrity bug with security consequences." Ruby convention (fail fast) aligns with fixing all of these.

### 4. Architectural drift in Phase 8

Three findings form a single architectural-debt cluster: **F8.1** (WalletClient is a local stateful wallet, not a substrate proxy), **F8.10** (namespace confusion between `BSV::WalletInterface` and `BSV::Wallet`), **F8.25** (`BSV::Attest` is imperative code inside a declarative SDK). Per CLAUDE.md's "declarative SDK / imperative companion gem" principle, all three violate the stated architecture.

Systems Architect: "Single biggest architectural finding in the review. Must be a blocking epic."
Maintainability Expert: "Namespace collision tangle that will fight every future PR."
Domain Expert: "Fundamental architectural mismatch."

### 5. Chronicle 2026 consensus gaps

**F7.1, F7.2**: Chronicle-restored opcodes (OP_SUBSTR, OP_LEFT, OP_RIGHT, OP_LSHIFTNUM, OP_RSHIFTNUM, OP_VER, OP_VERIF, OP_VERNOTIF) are treated as no-ops or reserved. Scripts using them will execute silently incorrectly. Implementation Strategist proposed the smart intermediate: promote to `raise InterpreterError` first (fail-safe), then implement correct semantics in a follow-up. This gives a strictly better intermediate state than silent incorrect execution.

---

## CONSENSUS Findings (54 items — recommended action)

These findings reached quorum (≥7 AGREE). Proceed with recommended action.

### Phase 1 — Foundation

- **F1.2** (MED, 7 AGREE) — `Base58.decode("")` returns `""` silently; match TS by raising `ArgumentError`.
- **F1.3** (HIGH, 9 AGREE) — `VarInt.encode` accepts negative integers and silently mis-encodes to `0xFF`. Add `raise ArgumentError if value.negative?` guard.
- **F1.5** (MED, **10 AGREE — unanimous**) — No dedicated Hex module. Silent drop/truncate via `pack('H*')` across 19 files. Add `BSV::Primitives::Hex` with `validate!`, `normalise`, and use at protocol boundaries.
- **F1.7** (LOW, 7 AGREE) — Add `hash256` alias for `sha256d` (`alias_method :hash256, :sha256d`).
- **F1.8** (MED, **10 AGREE — unanimous**) — RIPEMD-160 via OpenSSL 3 legacy provider is a portability bomb. Ship pure-Ruby RIPEMD-160 (consistent with pure-Ruby secp256k1 precedent).

### Phase 2 — Keys and Signatures

- **F2.1** (HIGH, 8 AGREE) — No constant-time scalar multiplication. Port `Point#mulCT` Montgomery ladder from TS; route secret-scalar paths (`ECDSA.sign_raw`, `PrivateKey#public_key`, both `derive_shared_secret`) through it. Keep wNAF for verify (public scalars). Bound `WNAF_TABLE_CACHE` with LRU. **Performance Specialist note**: ~2-3x slowdown on signing; mitigated by only applying to secret-scalar paths.
- **F2.2** (MED, 8 AGREE) — Add `force_low_s: true` keyword to `ECDSA.sign`; default preserves current behaviour.
- **F2.3** (MED, 8 AGREE) — `Signature.from_der` accepts non-canonical multi-byte length encodings. Reject `bytes[1] & 0x80 != 0` per BIP-66.
- **F2.4** (MED, 8 AGREE) — Drop `compressed: false` from `PrivateKey#to_wif`. Parse path stays tolerant; construct path enforces "construct only what's valid".
- **F2.9** (LOW, **10 AGREE — unanimous**) — Delete dead `ec_key_from_public_bytes` / `ec_key_from_private_bytes` and the weak shim DER parser.

### Phase 3 — Script Layer

- **F3.1** (HIGH, 8 AGREE) — Parser must track conditional depth and absorb trailing bytes at top-level `OP_RETURN`. Match TS/Py implementation.
- **F3.2** (MED, 7 AGREE) — Add `OP_NOP11..OP_NOP77` to opcode table so `to_asm`/`from_asm` round-trip unknown opcodes. Consider Chronicle aliases.
- **F3.3** (MED, 7 AGREE) — Accept `"0"` and `"-1"` as canonical ASM tokens for OP_0 and OP_1NEGATE.
- **F3.5** (MED, 9 AGREE) — `from_asm` silently truncates invalid hex. Validate hex and left-pad odd-length (depends on F1.5).
- **F3.10** (MED, 7 AGREE) — `op_return_data` inherits F3.1 bug. Fix after F3.1; return trailing data blob as a single element.
- **F3.12** (HIGH, 7 AGREE) — PushDrop `'before'` lock position unsupported. Support both positions; default to `'before'` to match TS.
- **F3.14 / F3.21** (LOW, 7 AGREE) — `encode_minimally` collapses single-byte `[0x00]` to OP_0 (shared bug with TS). Fix locally; raise upstream with TS team for coordinated fix.
- **F3.16** (MED, 8 AGREE) — Classification inconsistency: byte-level predicates return false on truncated scripts but `chunks`/`type` raise. Make `parse_chunks` lenient/clamping. **Ruby Expert note**: "Do not add a parallel `safe_chunks` — one method, consistent behaviour."

### Phase 4 — Transactions

- **F4.1** (HIGH, 7 AGREE) — Change distribution drops outputs when `available <= change_outputs.length` instead of `change <= 0`. Match TS on the `:equal` path.
- **F4.2** (HIGH, 8 AGREE) — `estimated_fee` (500 sat/kB) vs `SatoshisPerKilobyte` default (100 sat/kB) — 5x discrepancy. Delegate or remove. **QA**: "Confidence-destroying finding — this alone would motivate abandoning the SDK."
- **F4.3** (MED, 8 AGREE) — `estimated_size` silently falls back to 148-byte P2PKH. Raise `ArgumentError` matching TS/Go.
- **F4.4** (MED, 8 AGREE) — `total_input_satoshis` requires populated `source_satoshis`. Fall through to `source_transaction.outputs[index].satoshis`.
- **F4.5** (MED, 7 AGREE with Pragmatic dissent) — `Transaction#verify` runs fee validation only on root. Match TS (validate every unproven ancestor) or document divergence prominently.
- **F4.7** (LOW, 7 AGREE with Pragmatic dissent) — Tighten sighash type validation (reject garbage high nibbles + invalid coverage bits). Cryptography Specialist: "Fix as a pair with F4.8."
- **F4.9** (LOW, 9 AGREE) — `Transaction#sign` doesn't validate that outputs have satoshis. Add guard raising on `satoshis.nil?`.

### Phase 5 — Network + BEEF

*Largest concentration of HIGH-severity consensus findings. Pattern matches #302 exactly: "trusting metadata flags or round-trip symmetry rather than underlying hash-to-leaf relationships."*

- **F5.1** (HIGH, 8 AGREE) — BeefTx TXID_ONLY byte-order inconsistency. Round-trip tests pass because two bugs cancel. Pick the TS convention (display-hex in memory, wire-internal-order on the wire); document and enforce. **Implementation Strategist**: must land first; all other Phase 5 fixes depend on the convention.
- **F5.2** (HIGH, 9 AGREE) — `MerklePath#compute_root` fails for single-level compound paths. Compute `tree_height = max(@path.length, max_offset.bit_length)` and synthesise missing siblings.
- **F5.3** (HIGH, 9 AGREE with Pragmatic dissent) — Add `Beef#verify(chain_tracker, allow_txid_only:)` as canonical SPV validation entry point.
- **F5.4** (HIGH, **10 AGREE — unanimous**) — `Beef#valid?` doesn't verify bump↔tx linkage or cross-check computed roots. Add the checks TS's `verifyValid` performs.
- **F5.5** (HIGH, 9 AGREE) — `Beef#sort_transactions!` silently drops cycles via Kahn. Preserve unsortable txs in a `txsNotValid` bucket. Also call `sort_transactions!` before `to_binary`.
- **F5.6** (HIGH, 8 AGREE) — `Beef#merge_bump` doesn't retroactively link existing transactions. Scan `@transactions` for matching level-0 leaves and update `bump_index`.
- **F5.7** (HIGH, 8 AGREE) — `merge_transaction` / `merge_raw_tx` don't upgrade weaker entries (TXID_ONLY → RAW_TX → RAW_TX_AND_BUMP). Call `removeExistingTxid` and re-push.
- **F5.8** (MED, 9 AGREE) — `Beef#find_bump` only looks in transaction-table entries. Scan `@bumps` directly for level-0 leaf matches.
- **F5.9** (MED, 8 AGREE) — `Beef#merge` mutates the source's transactions. Construct new BeefTx instances instead.
- **F5.10** (MED, 9 AGREE with Pragmatic dissent) — `MerklePath` constructor performs no invariant validation. Add construction-time validation.
- **F5.11** (MED, 7 AGREE with Pragmatic dissent) — `MerklePath#verify` missing coinbase 100-block maturity check. Add check or document divergence.
- **F5.12** (MED, 9 AGREE) — `Beef.from_binary` silently accepts unknown versions. Raise explicitly.
- **F5.13** (HIGH, 8 AGREE) — ARC broadcaster has wrong content type, missing headers, **missing INVALID/MALFORMED/MINED_IN_STALE_BLOCK/ORPHAN from failure status set**. Match TS broadcaster.
- **F5.20** (LOW, 7 AGREE) — `Transaction#to_beef` never calls `sort_transactions!`. Add the call.

### Phase 7 — Script Interpreter

- **F7.8** (MED, 7 AGREE) — Remove 20-key `OP_CHECKMULTISIG` cap (post-Genesis BSV removed it).
- **F7.9** (MED, **10 AGREE — unanimous**) — `NULLFAIL` raise-in-no-tx-path is wrong for `Interpreter.evaluate`. Push false in no-tx path; reserve raise for actual NULLFAIL violations.
- **F7.10** (LOW, 7 AGREE) — Reject hybrid pubkey prefixes (0x06/0x07) in interpreter CHECKSIG.
- **F7.11** (MED, **10 AGREE — unanimous**) — Default `pop_int` / arithmetic operand decoding to `require_minimal: true`. Document the 750,000-byte cap's source.
- **F7.16** (LOW, 7 AGREE with Pragmatic dissent) — `OP_MUL` with large operands is O(n²) DoS (depends on F7.18).
- **F7.18** (MED, 7 AGREE with Pragmatic dissent) — Add 32MB stack memory limit matching TS. **Performance Specialist**: "Critical DoS gap. Track incrementally per op (O(1))."
- **F7.19** (LOW, 7 AGREE with Pragmatic dissent) — Add conditional-depth counter (e.g. 256 levels).

### Phase 8 — Wallet, Auth, Overlay

- **F8.3** (HIGH, 7 AGREE with Pragmatic dissent) — Missing BRC-104 HTTP auth transport. Implement `/.well-known/auth` endpoint with `x-bsv-auth-*` headers and AuthFetch client.
- **F8.7** (MED, 7 AGREE) — Protocol-ID validation strict where TS normalises. Lowercase-and-trim before validation. **Domain Expert**: "This silently forks the key derivation tree across SDKs — should be HIGH, not MED."
- **F8.8** (LOW, 7 AGREE) — Move permission rules out of `Validators` into a permissions layer.
- **F8.10** (LOW, 7 AGREE) — Namespace cleanup: pick `BSV::Wallet` for BRC-100 machinery; delete empty `BSV::WalletInterface` shell; extract legacy `BSV::Wallet::Wallet` to companion gem.
- **F8.13** (MED, 7 AGREE with Pragmatic dissent) — Implement `SignActionOptions` (`acceptDelayedBroadcast`, `returnTXIDOnly`, `noSend`, `sendWith`). **Performance**: "Single largest performance lever in the BRC-100 layer — escalate from MED."
- **F8.14** (HIGH, 9 AGREE) — `internalize_action` must verify BEEF merkle proofs against block headers before storing.
- **F8.15** (HIGH, 8 AGREE) — **SECURITY**: `acquire_certificate` 'direct' path writes unverified data. Verify certifier signature before persisting. **Cryptography Specialist**: "A signature-verification bypass masquerading as an API finding. Treat as P0 security."
- **F8.18** (LOW, 8 AGREE) — `wire_source_tx_ancestors` unbounded recursion. Add depth cap and cycle detection.

### Phase 3 additional

- **F3.21** (LOW, 7 AGREE) — Shared with F3.14.

---

## CONTROVERSIAL Findings (6 items — flagged for explicit decision)

These failed to reach quorum AND have ≥2 substantive dissenters. Explicit decision required.

### F8.11 — snake_case vs camelCase wire format

- **Vote**: 5 AGREE, 2 DISAGREE (Pragmatic Enforcer, Ruby Expert)
- **Agreers**: Systems Architect, Domain Expert, Maintainability, Implementation Strategist, Quality Assurance (all see it as a real problem)
- **Dissent**: Pragmatic says "premature — wait for the JSON substrate to exist." Ruby Expert says something more nuanced: **"Forcing camelCase in Ruby code would be deeply un-Rubyish and violates rubocop defaults. The correct Ruby answer is snake_case internally, translate at the wire boundary. Add a single `WireFormat.to_wire` / `from_wire` translator at JSON substrate boundaries only. This is a ~30 LOC module and keeps every internal API Ruby-idiomatic. Rails/Sequel/Dry-rb all solve this the same way."**
- **Implementation Strategist** independently arrived at the same answer: **"The naïve fix (rename everything) has the largest blast radius in the whole review. The sensible fix is a translator at the wire boundary. Strongly recommend the translator approach; reject any PR that proposes a global rename."**
- **Resolution**: The disagreement is on **HOW**, not WHETHER. All parties agree there's a problem. Ruby Expert and Implementation Strategist converge on the translator approach. **Recommendation**: reframe the finding as "add `BSV::Wallet::WireFormat.to_wire/from_wire` translator at JSON boundaries; keep snake_case internal" and treat as CONSENSUS under that phrasing.

### F7.6 — OP_CHECKSIG findAndDelete

- **Vote**: 6 AGREE, 2 DISAGREE (Pragmatic, Cryptography Specialist)
- **Cryptography Specialist's dissent is authoritative**: "Under BSV's FORKID-only sighash, signatures are never in the subScript being hashed, so findAndDelete would never actually delete anything on any real BSV transaction. Adding the code for 'spec purity' is dead weight and slightly increases attack surface. Document instead."
- **Resolution**: **DON'T FIX**. Add a code comment in `crypto.rb:194-198` explaining the analysis and why the omission is intentional for BSV FORKID. Raise to agreement status as "no action with documented rationale."

### F2.5 — ECDSA recover_public_key cofactor check

- **Vote**: 5 AGREE, 2 DISAGREE (Pragmatic, Cryptography Specialist)
- **Cryptography**: "secp256k1 cofactor is 1; check is genuinely vestigial. Treating as finding overstates the concern."
- **Resolution**: **DON'T FIX beyond a code comment**. Add a one-line comment noting why the TS cofactor check is unnecessary.

### F2.8 — derive_child HMAC scalar bounds

- **Vote**: 2 AGREE, 2 DISAGREE (Pragmatic, Cryptography)
- **Cryptography**: "Probability 2⁻¹²⁸; BIP-32 does technically require retry, but TS shares the omission. Not worth treating as HIGH/MED. Mark as informational cross-SDK note."
- **Resolution**: **DEFER**. Document in a cross-SDK issue; no Ruby-local action.

### F6.1 — BIP-32 invalid-key retry-with-i+1

- **Vote**: 2 AGREE, 2 DISAGREE (Pragmatic, Cryptography)
- **Cryptography**: "Probability 2⁻¹²⁷, untestable, TS shares it. Strict BIP-32 violation but the fix is theatre."
- **Resolution**: **DEFER**. Same treatment as F2.8.

### F8.19 — Shamir uses field prime P instead of curve order N

- **Vote**: 2 AGREE, 2 DISAGREE (Pragmatic, Cryptography)
- **Cryptography**: "Technically wrong (secret lives mod N, not mod P), probability 2⁻¹²⁸, inherited from TS. Worth raising upstream as a cross-SDK note; not worth a Ruby-local fix unless TS fixes first."
- **Resolution**: **DEFER**. Raise upstream with TS SDK team; no Ruby-local action until fixed in TS.

---

## NEAR-CONSENSUS Findings (blocked by solo Pragmatic Enforcer dissent)

These 15 findings got 6 AGREE votes with Pragmatic Enforcer as the sole dissenter. PE's position is uniformly "feature-parity-as-requirement fallacy; defer without user-demand evidence." Every other specialist who voted agreed.

**Phase 3 / 4 items** (PE objects to TS-parity polish):
- **F1.1** — Base58Check prefix parameter
- **F3.4** — from_asm explicit PUSHDATA forms
- **F3.6** — to_asm ambiguous rendering
- **F3.18** — p2pkh_lock address-string convenience
- **F4.6** — Fixed numeric fee `.ceil` behaviour
- **F4.8** — `hash_outputs` fallthrough to ALL (depends on F4.7)
- **F6.7** — ECIES Electrum noKey/uncompressed ephemeral
- **F6.16** — SignedMessage/EncryptedMessage under wrong namespace

**Phase 8 architectural cluster** (PE says defer until `bsv-wallet` gem is being built):
- **F8.1** — WalletClient rename / architectural inversion
- **F8.2** — Missing BRC-100 substrates (HTTPWalletJSON, HTTPWalletWire)
- **F8.4** — Peer missing certificate exchange messages
- **F8.5** — Peer missing high-level session API
- **F8.6** — Missing Certificate/VerifiableCertificate/MasterCertificate classes
- **F8.12** — listActions/listOutputs ignore include flags
- **F8.16** — acquire_certificate issuance not via BRC-104
- **F8.25** — BSV::Attest imperative code in declarative SDK

**Recommendation**: Apply Implementation Strategist's sequencing advice. These findings *should* be accepted but explicitly gated on the `bsv-wallet` companion gem work. Track them as a coordinated roadmap epic (2-3 minor releases) rather than scattered fixes. The correct sequencing is **F8.6 → F8.4 → F8.3 → F8.2 → F8.1**, NOT the other way round — substrates can't exist without a proxy target; BRC-104 can't exist without BRC-103 messages; BRC-103 can't exchange certs without certificate classes.

---

## SPECIALIST / NICHE Findings (low participation)

62 additional findings had fewer than 7 AGREE votes but no substantive dissent. Most are "NONE/POSITIVE" items (already marked no-action by the phase coordinators) or truly domain-specific items where only 3-5 specialists had relevant expertise to vote.

Notable items worth calling out individually:

- **F7.1 / F7.2** (6 AGREE each, 0 DISAGREE) — Chronicle opcodes. Fell short of quorum only because Security, Performance, Maintainability, Ruby Expert NO_OPINIONed them as "interpreter domain outside my specialty." Domain Expert says: "These should be treated as release blockers for any post-Chronicle SDK claim." **Implementation Strategist's two-step proposal**: (1) promote Chronicle-slot opcodes to `raise InterpreterError` in the next release (fail-safe, strictly better than silent no-op); (2) implement correct semantics with reference vector tests in a follow-up. **Recommendation**: adopt the two-step proposal.

- **F4.10 / F4.11** (6 AGREE each, 0 DISAGREE) — `TransactionInput#sequence` / `TransactionOutput#locking_script` API asymmetry. Ruby Expert: "Strong agree on Ruby convention. Use `attr_accessor` for both mutable fields. If immutability is desired, that's a separate RFC — don't half-do it."

- **F6.4, F6.5** (3 AGREE each, 0 DISAGREE) — Ruby is MORE correct than TS (BIP-32 depth guard, BIP-39 strength validation). Noted as positives; no action.

- **F7.14** (1 AGREE, 0 DISAGREE) — Ruby's OP_LSHIFT/RSHIFT byte-array semantics match Go and reference tests; TS's RSHIFT is subtly wrong. Noted as positive; no action.

---

## NO-ACTION Findings

The phase coordinators marked 25 findings as "NONE / POSITIVE / match confirmed." These received varied vote counts but all had zero DISAGREEs. Summary of why no action:

- **Ruby matches TS/Go/Py exactly** on: BIP-143 preimage layout, hashPrevouts/hashSequence/hashOutputs caching, txid computation, P2PKH lock structure, Extended Format round-trip, ECIES Bitcore variant, BRC-42 derivation (passes official vectors), BRC-77 SignedMessage wire format, BRC-78 EncryptedMessage wire format, SymmetricKey AES-GCM, Shamir KeyShares wire format, Polynomial Lagrange interpolation, Nonce HMAC scheme, Peer initial handshake signature data, wire call codes 1-28, BSM magic-hash, FORKID hard-requirement on every sighash.

- **Ruby is MORE correct than TS**: BIP-32 depth overflow guard (F6.4), BIP-39 strength validation strictness (F6.5), BSM rejection of BIP-137 segwit flags (F6.10), whitespace handling in `from_asm` (F3.22), OP_LSHIFT/RSHIFT byte-array semantics (F7.14), constant-time MAC comparison in ECIES (F6.8), more robust VarInt truncation detection than TS Reader.

- **Ruby correctly follows CLAUDE.md principles**: `p2sh?` detection with no `p2sh_lock` constructor (F3.7), OP_CHECKMULTISIG off-by-one preserved for Bitcoin Core compatibility (F7.7), post-Genesis one-OP_ELSE-per-OP_IF enforcement (F7.4), non-minimal pushes preserved in Chunk#to_binary for sighash fidelity (F3.17).

---

## Recommended Sequencing

From Implementation Strategist's analysis:

### P0 — SECURITY (patch release, backportable, NOT bundled with refactors)

1. **F8.15** — Verify certifier signature in `acquire_certificate`. Isolated hotfix.
2. **F1.3** — VarInt negative-integer silent protocol corruption. Trivial guard.
3. **F5.13** — ARC broadcaster silently treats failures as successes. High user impact.

### P1 — Foundation correctness (can proceed in parallel with above)

4. **F4.2** — Fee discrepancy. Delegate `estimated_fee` to `SatoshisPerKilobyte`. QA: "confidence-destroying finding."
5. **F1.8** — Pure-Ruby RIPEMD-160. Prevents production breakage on OpenSSL 3.
6. **F1.5** — Hex primitive module. **Prerequisite for F3.5.**

### P2 — BEEF cluster (single coordinated PR)

7. **F5.1** — Byte-order convention. **Must land first in Phase 5.**
8. Then F5.2, F5.5, F5.6, F5.7, F5.8 together — they all depend on F5.1's convention.
9. Plus F5.4 — bump↔tx linkage cross-checks.
10. Plus F5.9, F5.10, F5.12 — defensive hardening.
11. Plus F5.3 and F5.20 — canonical verify API + sort-before-serialise.

### P3 — Crypto hardening

12. **F2.1** — Constant-time scalar multiplication. Internal change, reversible. Benchmark before merge.
13. **F2.3** — DER canonical length enforcement.
14. **F7.11** — Minimal encoding default ON (breaking change; gate with deprecation cycle).
15. **F7.10** — Hybrid pubkey rejection at interpreter layer.

### P4 — Parser correctness

16. **F3.1** — OP_RETURN termination. Unblocks F3.10.
17. **F3.2** — Complete opcode table. Unblocks F3.19.
18. **F3.5** — Hex validation in from_asm (depends on F1.5/F1.8).
19. **F3.3, F3.4, F3.6** — ASM round-trip cross-SDK compatibility.
20. **F3.16** — Lenient parse_chunks for classification consistency.

### P5 — Interpreter hardening

21. **F7.9** — NULLFAIL push-false in no-tx path.
22. **F7.18** — Stack memory limit. Unblocks F7.16, F7.19.
23. **F7.8** — Remove 20-key CHECKMULTISIG cap.
24. **F7.1 / F7.2** — Chronicle opcodes: two-step (raise first, implement later).

### P6 — Wallet/Auth architectural epic (2-3 minor releases)

Correct sequence: **F8.6 → F8.4 → F8.3 → F8.2 → F8.1**
- **F8.6** — Certificate / VerifiableCertificate / MasterCertificate classes (foundation)
- **F8.4** — Peer certificateRequest/Response message types
- **F8.3** — BRC-104 HTTP auth transport (AuthFetch, SimplifiedFetchTransport)
- **F8.2** — BRC-100 substrates (HTTPWalletJSON, HTTPWalletWire)
- **F8.1** — Rename/extract legacy wallet to `bsv-wallet` companion gem
- Plus **F8.10** (namespace cleanup) and **F8.25** (Attest extraction) at the end of the chain.
- **F8.11** — Do **not** global-rename to camelCase. Add `WireFormat.to_wire/from_wire` translator at JSON substrate boundaries only (Ruby Expert + Implementation Strategist consensus).

### P7 — Defensive hardening (anytime)

25. **F4.1** — Change distribution `:equal` fix.
26. **F4.9** — Sign-with-nil-satoshis guard.
27. **F4.3** — Raise on unknown unlocking script in estimated_size.
28. **F4.4** — `total_input_satoshis` fallback through `source_transaction`.
29. **F5.11** — Coinbase maturity check.
30. **F8.14** — BEEF header verification in `internalize_action`.
31. **F8.18** — Ancestry recursion depth cap + cycle detection.

### Follow-ups (defer with rationale documented)

- **F7.6** — `findAndDelete`: DO NOT FIX. Add code comment explaining FORKID makes it dead code.
- **F2.5** — Cofactor check: DO NOT FIX. Add comment explaining secp256k1 cofactor=1.
- **F2.8, F6.1, F8.19** — Inherited cross-SDK bugs with 2⁻¹²⁸ probability. Raise upstream with TS team; no Ruby-local action.

---

## Per-Member Specific Concerns

Each project team member was asked to flag cross-cutting concerns beyond the per-finding votes. These are preserved verbatim (key points only):

### Systems Architect

> "Declarative vs imperative layering is violated in Phase 8. `WalletClient`, `BSV::Attest`, and the legacy `BSV::Wallet::Wallet` together represent significant imperative/application code inside the declarative SDK. Resolving these should be treated as a single architectural workstream, not eight separate fixes."
>
> "Namespace governance is unresolved. `BSV::WalletInterface` is an empty shell while classes live under `BSV::Wallet`; `SignedMessage`/`EncryptedMessage` sit under `Primitives`; script interpreter and parser share the `Script` namespace despite the explicit architectural split in CLAUDE.md. A single namespace-map ADR would resolve all three."
>
> "Wire-format contract is unspecified. F8.11 is the tip of an iceberg. The SDK has no documented policy about where Ruby idiomatic naming ends and cross-SDK protocol naming begins. Every JSON/HTTP/BRC boundary needs the same answer, made once at the architectural level."
>
> "Round-trip tests mask cross-SDK interop breakage. Recommend an ADR on cross-SDK conformance vectors."

### Domain Expert

> "Chronicle conformance (F7.1, F7.2) is under-weighted. Should be treated as release blockers for any post-Chronicle SDK claim."
>
> "BRC-100 wire shape (F8.7, F8.11, F8.12) is a cross-SDK interop showstopper. Protocol-ID normalisation divergence is not just a validator strictness issue — it means the *same* BRC-43 protocol string produces *different* derived keys on Ruby vs TS. This silently forks the key derivation tree across SDKs. **Should be HIGH, not MED.**"
>
> "The BRC-62/74 BEEF cluster (F5.1–F5.12) is correctly identified as the largest domain risk. The 'letter vs spirit' pattern identification is the single highest-leverage observation in this review."

### Security Specialist

> "F8.15 is the most urgent fix in this review. Writing unverified signatures to certificate storage and later treating them as authentic is a straightforward trust-boundary break, not a subtle bug. This should block the next release."
>
> "F2.1 is the largest latent crypto risk. Pure Ruby wNAF on secret scalars leaks through branch timing and cache behaviour. The TOB-4 mitigation path in TS exists specifically because of demonstrated attacks on similar code."
>
> "F8.14 + F5.4 + F5.10 form a cluster of SPV soundness gaps. Any of these individually is worth fixing; together they fatally undermine SPV guarantees."
>
> "Overall priority ranking from a security lens: **F8.15 > F8.14 > F5.4 > F2.1 > F5.13 > F7.18 > F5.10 > F2.3 > F5.2 > F8.16 > F2.2.**"

### Maintainability Expert

> "Namespace collision (F8.1, F8.10, F8.25) is the single biggest architectural-debt item. This should become a blocking epic before any further Wallet/Auth/Overlay work."
>
> "'Letter vs spirit' patterns are the most dangerous class of bug on the review. These need property-based / cross-SDK fixture tests, not more unit tests, or they will regress."
>
> "Undocumented magic numbers (F7.11's 750,000-byte cap) are implicit knowledge debt. Every such constant needs a comment citing its source (BIP, consensus rule, Genesis activation) or it will be 'optimised' away by a future maintainer."
>
> "F4.2 is the single clearest 'how did this pass review?' finding. Must be resolved."

### Performance Specialist

> "F2.1 WNAF_TABLE_CACHE unbounded growth is a real memory leak. Long-running verification servers will accumulate wNAF tables for every distinct public key. At ~1KB per entry and millions of unique pubkeys, this becomes GB-scale. Required fix: LRU with 1024 default."
>
> "F2.1 constant-time tradeoff: Montgomery ladder is 2-3x slower than wNAF. Apply CT **only** to secret-scalar paths (sign, public key derivation, ECDH). Keep wNAF for verify where neither scalar is secret."
>
> "F7.16 + F7.18 are the primary DoS surface. Ruby bignum OP_MUL of two large operands is O(n²) with GC pressure; without stack memory accounting a single script can exhaust host memory in <1 second."
>
> "F8.9 CachedKeyDeriver should be treated as MED, not LOW. HMAC-SHA256 + one secp256k1 multiply per call is roughly 100x the cost of the surrounding bookkeeping. An LRU cache of 1000 entries will hit >95% on realistic workloads."
>
> "F8.13 sendWith/batch broadcast is a throughput lever, not an API nicety. Wallets creating N related transactions pay N round-trips instead of 1."

### Implementation Strategist

> "Phase 5 letter-vs-spirit cluster (F5.1/F5.2/F5.6/F5.7/F5.8) is a single ball of mud. F5.1 must be resolved first; the other four all encode assumptions that depend on which convention is canonical. Fix in a single coordinated PR."
>
> "F8.1/F8.2/F8.3/F8.4/F8.6 must be sequenced as a dependency chain, not parallelised. Correct order: **F8.6 → F8.4 → F8.3 → F8.2 → F8.1**. Multi-release effort spanning 2-3 minor versions."
>
> "F8.11 (snake_case vs camelCase) is deceptively high-risk. The naïve fix (rename everything) has the largest blast radius in the whole review. **Strongly recommend the translator approach; reject any PR that proposes a global rename.**"
>
> "Security findings (F2.1, F8.15) should NOT wait for their phase peers. **Never bundle security fixes with architectural churn — they need to be backportable.**"
>
> "F7.1/F7.2 Chronicle opcodes: promote all Chronicle-slot opcodes to `raise InterpreterError` in the next release (fail-safe), then implement correct semantics in a follow-up."
>
> "Breaking-change findings (F2.4, F4.2, F4.3, F7.11, F8.1, F8.10) should be gathered into a single 0.9.0 or 1.0.0 bump with a coordinated migration guide. Shipping piecemeal will burn consumer trust."

### Pragmatic Enforcer

> "Feature-parity-as-requirement fallacy. Large parts of Phase 8 treat 'TS has it, Ruby doesn't' as the bug. That is not a bug — it's a roadmap. Without evidence of Ruby users asking for these substrates, porting ~2000 LOC is pure speculative work."
>
> "DoS-mitigation creep in the interpreter. 32MB memory tracking plus conditional-depth limits plus big-int overflow guards is substantial machinery for a library that isn't a consensus node. The threat model matters — who's running the Ruby interpreter on untrusted scripts with DoS as a concern?"
>
> "'Letter vs spirit' overcorrection risk. The pattern is real, but the instinct to 'add validation everywhere' adds surface area. Prefer the smallest fix that closes the concrete case."
>
> "Of 137 findings, the 'must do now' set is roughly ~30. The remaining ~100 should be deferred, documented as known-divergence, or rejected."

### Quality Assurance

> "Round-trip tests as false confidence. At least 9 findings describe bugs where Ruby's own tests pass because two errors cancel. **The SDK needs a `spec/conformance/` suite that loads canonical vectors produced by TS/Go/Py and asserts Ruby matches.**"
>
> "Documentation that lies vs the code. Several findings (F5.4 `valid?`, F4.5 `verify`, F5.3 missing `verify`, F8.15 cert storage) show method names or docstrings that describe behaviour the code doesn't deliver. A DX audit of docstrings against actual behaviour is needed."
>
> "First-hour new user traps. F3.1, F3.18, F4.4, F8.10, F8.1 will all bite a new user within their first hour."
>
> "Cross-SDK naming friction. A developer working across SDKs hits friction every few minutes. A cross-SDK API mapping document is needed."
>
> "F4.2 estimated_fee vs SatoshisPerKilobyte: A new user will notice before they build their first tx. **This alone would motivate abandoning the SDK.**"

Proposed deliverables (verbatim):
1. API behaviour docstrings that match implementation
2. Cross-SDK mapping guide at `docs/cross-sdk-mapping.md`
3. "Recognise everything, construct only what's valid" as enforceable test policy
4. Chronicle 2026 opcode coverage matrix
5. BRC-100/103/104 coverage matrix
6. Cross-SDK conformance test vectors
7. Negative-input / invalid-input test category
8. "First-time user workflow" acceptance specs

### Ruby Expert (Marcus Johnson)

> "F1.8 RIPEMD-160 is my top Ruby-portability concern. OpenSSL 3's legacy-provider split will bite gem users on stock distros. A gem that crashes on `Hash160` when installed from rubygems on a fresh Ubuntu 22.04 box is a support nightmare."
>
> "F8.11 snake_case vs camelCase is a philosophical fork in the road. The wrong resolution (forcing camelCase Ruby) would make the SDK feel like a TS port rather than a Ruby library. **A translator at the JSON boundary is the correct, clean, one-place fix.** Rails/Sequel/Dry-rb all solve this the same way. Reject any PR that proposes a global rename."
>
> "F3.16: Raising on truncated scripts is not a Ruby virtue — it's a layering mistake. The parser layer is required to be tolerant per the Protocol Philosophy in CLAUDE.md."
>
> "F4.10/F4.11 attr_accessor symmetry: Mixed read/write on aggregates violates Ruby's principle of least astonishment. Fix the whole class in one PR."
>
> "Ruby 2.7 constraint reminder: avoid `Hash#except`, pattern matching, `Data.define`. CI should actually run against 2.7 through 3.4 — the gemspec claims 2.7 but I suspect we're not testing it."
>
> "OpenSSL::PKey::EC shim: Worth a specialist follow-up on whether the shim can be retired entirely now that pure-Ruby secp256k1 exists — it's an attack surface (F2.9) and a maintenance burden."

### Cryptography Specialist (Dr. Elena Vasquez)

> "F2.1 is the single most important crypto finding. All signing, ECDH, and child-key derivation currently route through wNAF scalar multiplication with no constant-time path. Secret-dependent table indexing and branch timing can leak private keys and nonces."
>
> "F8.15 is a signature-verification bypass masquerading as an API finding. Any downstream consumer of `prove_certificate` is relying on a signature that was never checked. Treat as P0 security."
>
> "F4.7/F4.8 as a pair — sighash type validation gaps combined with a permissive `case…else` fallthrough to SIGHASH_ALL is exactly how signing oracles appear. Fix as one unit."
>
> "F5.2/F5.4/F5.10/F5.11 as a coherent SPV-verification hardening work package. Today, BEEF 'validation' in Ruby doesn't actually validate the cryptographic linkage between transactions, BUMPs, and headers. A consumer calling `valid?` is getting far weaker guarantees than they think."
>
> "F2.5, F6.1, F2.8, F8.19 are 'theoretical spec violations' that together add noise to the triage. None of these should pull priority away from F2.1, F8.15, F4.7/F4.8, F5.2–F5.11, and F7.10."
>
> "F7.6 findAndDelete — I disagree with fixing this. Under BSV's FORKID-only sighash, signatures are never inside the subScript being hashed. Adding the code for 'spec purity' is dead weight. **Document instead.**"

---

## Conclusion

The review confirms the hypothesis: the Ruby BSV SDK has systematically drifted from the TypeScript reference in ways that self-tests do not catch. **The "letter vs spirit" pattern identified in the original prompt recurs in at least 9 findings across Phases 1, 3, 4, and 5.** The #302 bug fix was the tip of a larger iceberg specifically in Phase 5 (BEEF/Network), where 7 HIGH-severity findings all share the same anti-pattern: trusting metadata flags or round-trip symmetry rather than underlying hash-to-leaf relationships.

**Critical next actions** (unanimous consensus from multiple specialists):

1. **Ship F8.15 as a security hotfix immediately.** Isolated patch. Verify certifier signature before persisting.
2. **Add a `spec/conformance/` directory with cross-SDK test vectors.** This is the testing-strategy fix that prevents the entire "letter vs spirit" category of bugs from recurring.
3. **Treat Phase 5 as a single coordinated PR starting with F5.1** (byte-order convention). All other Phase 5 correctness fixes depend on this convention being settled.
4. **Add `BSV::Wallet::WireFormat` translator** (snake_case ↔ camelCase at JSON boundaries only). Do NOT global-rename Ruby internals.
5. **Chronicle opcodes: raise first, implement later.** Silent no-ops are strictly worse than explicit errors. Two-step path.
6. **Phase 8 architectural epic** (F8.6 → F8.4 → F8.3 → F8.2 → F8.1 + F8.10 + F8.25) spanning 2-3 minor releases. Sequence dependencies matter; don't parallelise.

Approximately **60 findings** have strong consensus for action. **15 more** are blocked only by Pragmatic Enforcer's YAGNI dissent and should be treated as accepted but scope-gated on the Phase 8 epic. **6 are genuinely controversial** with 4 resolving as "no action with documented rationale" and 2 resolving as deferred cross-SDK coordination.

The Ruby SDK is not broken — it correctly implements many protocol features byte-for-byte against the reference. But its test strategy systematically hides cross-SDK interop failures, and the convergence of specialist opinion is that this must change before 1.0.
