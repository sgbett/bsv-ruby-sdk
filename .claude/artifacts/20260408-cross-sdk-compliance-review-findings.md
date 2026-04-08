# Consolidated Findings — Ruby BSV SDK vs TS Reference (8-Phase Review)

This is a normalised digest of 137 findings from 8 phase coordinator reports comparing the Ruby BSV SDK at `/opt/ruby/bsv-ruby-sdk` against the TypeScript reference at `/opt/ruby/bsv-reference-sdks/ts-sdk`. Use this as the source of truth for the project-team quorum vote.

For each finding, vote AGREE / DISAGREE / NO_OPINION with a one-line reason.

---

## PHASE 1 — Foundation (Hashing + Encoding)

### F1.1 (HIGH) — Base58Check missing prefix parameter
`base58.rb:94-114`. TS/Go/Py all expose `prefix` as a first-class parameter; Ruby callers must pre-concatenate the prefix and re-slice on decode. Every call site (`public_key.rb:99`, `extended_key.rb:106,260`, `private_key.rb:75,118`, `bsm.rb:69`, `script.rb:583`) open-codes prefix concat.
**Action**: Add `Base58.check_encode(payload, prefix: nil)` and `check_decode(string, prefix_length: 1)` returning `[prefix, payload]`.

### F1.2 (MED) — Base58.decode("") returns "" silently; TS throws
`base58.rb:65-66`. `decode('')` returns empty bytes; TS rejects.
**Action**: Match TS (raise on empty) for cross-SDK interop.

### F1.3 (HIGH) — VarInt.encode accepts negative integers and silently mis-encodes
`var_int.rb:17-27`. `VarInt.encode(-1)` falls into `[value].pack('C')`, produces `0xFF` (the marker for a 9-byte encoding). Silent protocol corruption. No guard, no test coverage.
**Action**: `raise ArgumentError if value.negative?`. Add upper bound guard for >2^64-1.

### F1.4 (LOW) — VarInt has no read-bytes-only variant
`var_int.rb:34-55`. TS has `readVarIntNum/Bn/raw`; Ruby has only `decode`. Minor.
**Action**: Consider `VarInt.read_bytes` for serialisation helpers.

### F1.5 (MED) — No dedicated hex module
19 files use scattered `unpack1('H*')`/`pack('H*')`. Ruby silently drops non-hex chars and truncates odd-length input — TS left-pads. Cross-SDK hex interop silently disagrees.
**Action**: Add `BSV::Primitives::Hex` with `validate!`, `normalise`, `to_bytes`, `from_bytes`.

### F1.6 (LOW) — pbkdf2_hmac_sha512 has BIP-39 defaults baked in
`digest.rb:94-96`. Defaults `iterations: 2048`, `key_length: 64`. Mild layering violation.
**Action**: Move BIP-39 defaults into `Mnemonic`, validate inputs in PBKDF2 itself.

### F1.7 (LOW) — Missing hash256 alias
`digest.rb:37-65`. Ruby calls it `sha256d`; TS/Go/Py call it `hash256`. Naming friction.
**Action**: Add `hash256` as alias for `sha256d`.

### F1.8 (MED) — RIPEMD-160 portability fragility
`digest.rb:53-55`. OpenSSL 3.0 moved RIPEMD-160 to legacy provider; Ruby on stock Ubuntu 22.04 / Amazon Linux 2023 / macOS openssl@3 will break on first `Hash160` call. TS/Go/Py all ship their own RIPEMD-160.
**Action**: Ship pure-Ruby RIPEMD-160 (consistent with pure-Ruby secp256k1 decision).

---

## PHASE 2 — Keys and Signatures

### F2.1 (HIGH) — No constant-time scalar multiplication
`secp256k1.rb:275-321`, used by `ECDSA.sign_raw`, `PrivateKey#public_key`, both `derive_shared_secret` paths. Only path is windowed-NAF. TS gates these through `Point#mulCT` (Montgomery ladder, TOB-4 mitigation). Timing/cache sidechannels could leak nonces and private keys. Also `WNAF_TABLE_CACHE` grows unbounded.
**Action**: Implement Montgomery-ladder `scalar_multiply_ct`; route signing/derivation paths through it. Bound cache.

### F2.2 (MED) — ECDSA.sign always forces low-S; no opt-out
`ecdsa.rb:26-29,136-139`. TS makes it a flag (`forceLowS: false` for raw, `true` for `PrivateKey#sign`). Ruby has no escape hatch.
**Action**: Add `force_low_s:` keyword.

### F2.3 (MED) — Signature.from_der accepts non-canonical multi-byte length encodings
`signature.rb:41,47,59`. Length byte read verbatim with no high-bit check. TS throws.
**Action**: Reject `bytes[1] & 0x80 != 0`.

### F2.4 (MED) — WIF construct path allows uncompressed
`private_key.rb:74-91,114-119`. `to_wif(compressed: false)` lets you build uncompressed WIFs. Violates "construct only what's valid".
**Action**: Drop `compressed:` from `to_wif`.

### F2.5 (LOW) — recover_public_key skips cofactor check
`ecdsa.rb:67`. TS does `nR.isInfinity()`; secp256k1 has cofactor 1 so check is vestigial, but the omission is silent.
**Action**: Add comment explaining why omitted.

### F2.6 (LOW) — Bit-gymnastics typo in recovery-id parity check
`ecdsa.rb:64`. `(recovery_id & 1).odd?` is redundant.
**Action**: Rewrite as `recovery_id.odd?`.

### F2.7 (LOW) — from_der lacks zero-length-integer rejection for degenerate shapes
`signature.rb:49,61`. Matches TS (also lenient). Noted for completeness.
**Action**: None.

### F2.8 (LOW) — derive_child does not validate HMAC scalar < N
`private_key.rb:155-160`, `public_key.rb:129-136`. Probability ~2^-128. TS shares this bug.
**Action**: Optional; cross-SDK fix.

### F2.9 (LOW) — Dead-weight ec_key_from_public_bytes / weak DER parser
`curve.rb:99-112`, `openssl_ec_shim.rb:147-162`. No callers; lingering attack surface.
**Action**: Delete or harden.

---

## PHASE 3 — Script Layer

### F3.1 (HIGH) — Parser does not terminate at top-level OP_RETURN
`script.rb:675-735`. BSV protocol allows arbitrary bytes after OP_RETURN at conditional depth 0. Ruby parses every byte; data carriers either raise `ArgumentError "truncated script"` or silently drop content via `select(&:data?)`. TS/Py track conditional depth and absorb the remainder.
**Action**: Match TS — emit final chunk with all remaining bytes when OP_RETURN encountered at depth 0.

### F3.2 (MED) — Opcode table incomplete in 0xba..0xfc range
`opcodes.rb:132-138`. Ruby has nothing for `OP_NOP11..OP_NOP77`, no `OP_SMALLDATA/SMALLINTEGER/PUBKEYS`, no Chronicle aliases. `to_asm` emits decimal byte values for unknown opcodes; `from_asm` cannot round-trip them — silent corruption to a different opcode.
**Action**: Add `OP_NOP11..OP_NOP77` at minimum; consider Chronicle aliases.

### F3.3 (MED) — from_asm doesn't accept canonical "0" / "-1" tokens
`script.rb:56-69`. TS/Py emit `OP_0` as `"0"` and `OP_1NEGATE` as `"-1"`; Ruby doesn't parse those. `"0"` happens to work coincidentally via empty hex push; `"-1"` becomes OP_0 (wrong).
**Action**: Accept `"0"` → OP_0 and `"-1"` → OP_1NEGATE.

### F3.4 (LOW-MED) — from_asm doesn't recognise PUSHDATA1/2/4 explicit forms
TS accepts `OP_PUSHDATA1 5 68656c6c6f`; Ruby misinterprets the length token as hex.
**Action**: Add the 3-token form.

### F3.5 (MED) — from_asm silently accepts invalid hex / odd-length tokens
`pack('H*')` silently drops non-hex chars and truncates odd-length. TS/Py validate and left-pad.
**Action**: Validate hex chars, raise on invalid, left-pad odd-length.

### F3.6 (LOW) — to_asm emits inconsistent / non-interoperable output
Unknown opcodes rendered as decimal byte values, ambiguous with hex data. Empty data chunks lose content via round-trip.
**Action**: Emit unknown opcodes as `OP_UNKNOWN<byte>`, consider `0`/`-1` short forms.

### F3.7 (NONE) — script_hash returns nil for non-P2SH
Correct under "recognise everything, construct only what's valid". No issue.

### F3.8 (LOW) — p2pk? accepts hybrid pubkey prefixes
`script.rb:373-381`. Accepts 0x06/0x07. Matches Go. No issue.

### F3.9 (LOW) — multisig? doesn't validate M ≤ N
`script.rb:471-478`. Accepts unspendable patterns. Matches Go. Per "recognise everything" arguably correct.
**Action**: None.

### F3.10 (MED) — op_return_data inherits F3.1 bug AND drops bare opcodes via `select(&:data?)`
`script.rb:524-529`. Returns wrong content when payload starts with bytes that parse as opcodes.
**Action**: Fix after F3.1. Return single trailing data blob.

### F3.11 (NONE) — Builder push_data correctly emits minimal length-prefix without small-int collapse
Matches TS. No issue.

### F3.12 (HIGH) — pushdrop? only supports 'after' lock position; TS default is 'before'
`script.rb:192-207,389-419`. Ruby cannot decode TS-default PushDrop tokens. Direct interop break.
**Action**: Support both lock positions; default to 'before'.

### F3.13 (LOW) — pushdrop? accepts any non-empty trailing chunk as lock script
Acceptable under "recognise broadly". No issue.

### F3.14/F3.21 (LOW, spec-level) — encode_minimally collapses single-byte [0x00] to OP_0
OP_0 pushes empty vector, NOT a length-1 zero-byte vector. **Ruby and TS share this bug**.
**Action**: Raise upstream with TS team; fix in Ruby.

### F3.15 (NONE) — rpuzzle? requires exact 12 or 13 chunks
Matches TS exactly. No issue.

### F3.16 (MED) — chunks raises on truncated scripts but byte-level predicates don't
Inconsistent: `p2pkh?`/`p2sh?`/`op_return?` return false for truncated scripts but `script.type` calls `chunks` which raises. TS uses `Math.min` to clamp.
**Action**: Make `parse_chunks` lenient/clamping or add `safe_chunks` for classification.

### F3.17 (NONE) — Non-minimal pushes preserved round-trip via Chunk#to_binary
Critical for sighash. Matches TS. No issue.

### F3.18 (LOW) — p2pkh_lock doesn't accept address strings
TS accepts address with base58check decoding. Ruby only takes 20-byte raw hash. Feature gap.
**Action**: Optional convenience addition.

### F3.19 (LOW) — Builder push_op uses const_get
Works for aliases. Affected by F3.2 (would raise on undefined `OP_NOP11+`).

### F3.20 (NONE) — Parser correctly emits 0x00 as bare OP_0 opcode
Matches TS. No issue.

### F3.22 (POSITIVE) — Ruby's whitespace handling in from_asm is more lenient than TS
Ruby uses `split` (collapses whitespace); TS uses `split(' ')` and breaks on consecutive spaces. **Ruby is better here.**

---

## PHASE 4 — Transactions

### F4.1 (HIGH) — Change distribution drops outputs when `available <= n` instead of `change <= 0`
`transaction.rb:789-791`. With 2 change outputs and 2 sat available, TS produces two 1-sat outputs; Ruby deletes both and silently donates 2 sat to miners.
**Action**: Match TS condition (`change <= 0`) on the `:equal` path.

### F4.2 (HIGH) — `estimated_fee` uses 500 sat/kB, `SatoshisPerKilobyte` defaults to 100 sat/kB
`transaction.rb:594-597` vs `fee_models/satoshis_per_kilobyte.rb:19`. **5x discrepancy within one SDK.**
**Action**: Remove `estimated_fee` or make it delegate to `SatoshisPerKilobyte`.

### F4.3 (MED) — `estimated_size` silently falls back to 148-byte P2PKH
`transaction.rb:608-617`. For inputs lacking both unlocking script and template. TS/Go raise. Non-P2PKH txs get silently wrong fees.
**Action**: Raise `ArgumentError` matching TS/Go.

### F4.4 (MED) — `total_input_satoshis` requires populated `source_satoshis`
`transaction.rb:576-581`. TS walks `input.sourceTransaction.outputs[index].satoshis` as fallback. BEEF-loaded txs raise unhelpful errors.
**Action**: Fall through to `source_transaction.outputs[index].satoshis`.

### F4.5 (MED) — `Transaction#verify` only validates fee on root tx
`transaction.rb:550`. TS validates every non-proven ancestor. Underpaid ancestors silently pass.
**Action**: Match TS or document divergence.

### F4.6 (LOW) — Fixed numeric fee gets `.ceil`'d
`transaction.rb:774-775`. `1000.4` becomes `1001` silently.
**Action**: Document or remove.

### F4.7 (LOW) — Sighash type validation only checks FORKID bit
`transaction.rb:397`. TS additionally validates high nibble + coverage bits.
**Action**: Tighten validation.

### F4.8 (LOW) — `hash_outputs` `case … else` routes garbage to ALL
`transaction.rb:699-711`. Only exploitable if F4.7 not fixed.

### F4.9 (LOW) — `Transaction#sign` doesn't validate outputs have satoshis
`transaction.rb:458-489`. Sign-then-fee ordering mistake silently invalidates signature.
**Action**: Add guard; raise if any output has nil satoshis.

### F4.10 (LOW) — `TransactionInput#sequence` is read-only
Bites BIP-68 / nLockTime workflows. TS allows mutation.
**Action**: Change to `attr_accessor`.

### F4.11 (LOW) — TransactionOutput API asymmetry
`satoshis` writable, `locking_script` read-only. Surprising.
**Action**: Make symmetric.

---

## PHASE 5 — Network + BEEF

### F5.1 (HIGH) — BeefTx TXID_ONLY byte-order inconsistency
`beef.rb:529` (read), `:648` (write), `:410-415` (`make_txid_only`), `:58-77`. Read stores wire bytes (internal hash order); `make_txid_only` stores display order. Round-trip tests pass *because both bugs cancel*. Same letter-vs-spirit pattern as #302. Cross-SDK interop silently broken.
**Action**: Pick a convention (TS uses display-hex internally, wire-internal-order on the wire). Document and enforce.

### F5.2 (HIGH) — `MerklePath#compute_root` fails for single-level compound paths
`merkle_path.rb:230-257`. Loop iterates `@path.length` times; for a single-level compound (all txids flat at level 0) computes wrong root. TS computes effective tree height from `maxOffset`. Ruby's own `extract` produces multi-level so self-built compounds work, but third-party compounds will compute wrong roots.
**Action**: Compute `tree_height = max(@path.length, max_offset.bit_length)` and synthesise missing siblings.

### F5.3 (HIGH) — Beef has no `verify(chain_tracker)` API
`beef.rb:428-454`. Only has `valid?`. TS canonical SPV validation entry point missing.
**Action**: Add `Beef#verify(chain_tracker, allow_txid_only:)` returning `{valid:, roots:}`.

### F5.4 (HIGH) — `Beef#valid?` doesn't verify bump↔tx linkage or computed-root agreement
`beef.rb:428-454`. TS `verifyValid` checks (a) every txid leaf in every bump computes the same root for that block and (b) every tx with bump_index has its txid at level 0 of the referenced bump. Ruby silently accepts mismatched links.
**Action**: Add the cross-checks.

### F5.5 (HIGH) — `sort_transactions!` silently drops cycles
`beef.rb:462-499`. Kahn exits with `sorted.length < @transactions.length` and `@transactions = sorted` discards cyclic txs. Also: TXID_ONLY entries get interleaved instead of bucketed. `to_binary` never calls `sort_transactions!`, so out-of-order BEEFs can be emitted.
**Action**: Track unsortable txs; preserve them in a `txsNotValid` bucket; call sort before serialise.

### F5.6 (HIGH) — `Beef#merge_bump` doesn't retroactively link existing transactions
`beef.rb:286-299`. TS scans `@transactions` for any txid matching a level-0 leaf in the merged bump and updates `bump_index`. Ruby does not. Workflow: merge raw tx then merge proof later → TS upgrades to proven; Ruby leaves orphaned.
**Action**: Add the retroactive link scan.

### F5.7 (HIGH) — `merge_transaction` / `merge_raw_tx` don't upgrade weaker entries
`beef.rb:309-330,337-355`. Both short-circuit `return existing if existing`. TS `removeExistingTxid` and re-pushes, allowing TXID_ONLY → RAW_TX → RAW_TX_AND_BUMP upgrades.
**Action**: Implement upgrade semantics.

### F5.8 (MED) — `Beef#find_bump` only looks inside transaction-table entries
`beef.rb:236-241`. Requires `entry.format == FORMAT_RAW_TX_AND_BUMP` and uses `bump_index`. TS scans `this.bumps` directly for any path[0] hash match. Same #302 anti-pattern.
**Action**: Match TS.

### F5.9 (MED) — `Beef#merge` mutates the source BEEF's transactions
`beef.rb:391`. Reaches into `other.transactions` and rewrites `merkle_path`. TS doesn't mutate the source.
**Action**: Construct new BeefTx instances.

### F5.10 (MED) — `MerklePath` constructor performs no invariant validation
TS validates non-empty level 0, unique offsets, legal sibling positions, root agreement. Ruby accepts any structure.
**Action**: Add construction-time validation.

### F5.11 (MED) — `MerklePath#verify` missing coinbase 100-block maturity check
`merkle_path.rb:278-281`. TS rejects coinbase txs in blocks with <100 confirmations.
**Action**: Add maturity check or document divergence.

### F5.12 (MED) — `Beef.from_binary` silently accepts unknown versions
`beef.rb:112-149`. Returns empty Beef for unknown magic; TS raises explicitly.
**Action**: Raise on unknown version.

### F5.13 (HIGH) — ARC broadcaster has wrong content type, missing headers, missing failure statuses
`network/arc.rb:35-45,74-100`. Uses `application/octet-stream` instead of `application/json`+EF; missing `XDeployment-ID`/`X-CallbackUrl`/`X-CallbackToken`; **missing INVALID, MALFORMED, MINED_IN_STALE_BLOCK, ORPHAN from failure status set** → silently treats failures as successes.
**Action**: Match TS broadcaster.

### F5.14 (LOW/MED) — `BeefParty` entirely missing
TS's primary vehicle for long-running wallets exchanging minimal BEEFs. Ruby has no equivalent of `BeefParty` / `trimKnownTxids` / `addComputedLeaves` / `clone` / `mergeBeefTx` / `toLogString`.
**Action**: Port if Ruby is target for wallet apps.

### F5.15 (LOW) — `make_txid_only` doesn't move-to-end
`beef.rb:410-415`. Replaces in place; TS splices and re-appends to preserve dependency order.
**Action**: Match TS or call `sort_transactions!` after.

### F5.16 (LOW) — `MerklePath` missing `from_coinbase_txid_and_height` helper
TS has it; Ruby's `from_tsc` with empty nodes is equivalent. Just an API gap.

### F5.17 (LOW) — Parser accepts undefined flag combination 0x03
`merkle_path.rb:92-104`. Both duplicate AND txid bits set. Round-trips identically; minor edge case.

### F5.18 (LOW) — WhatsOnChain.current_height uses different endpoint than TS
`/chain/info` vs `/block/headers`. Both work; rate limits differ.

### F5.19 (LOW) — `BlockHeadersService` chain tracker missing
TS has `chaintrackers/BlockHeadersService.ts` for self-hosted headers. Recommended SPV deployment model.
**Action**: Port if SPV is a target.

### F5.20 (LOW) — `Transaction#to_beef` never calls `sort_transactions!`
Belt-and-braces. Combined with F5.5, worth adding.

---

## PHASE 6 — Extended Primitives

### F6.1 (LOW) — BIP-32 invalid-key retry-with-i+1 missing
Both Ruby and TS throw rather than retry. Probability ~2^-127, untestable.
**Action**: Optional cross-SDK fix.

### F6.2 (INFO) — BIP-32 path parser accepts H/h hardened markers
Ruby is more permissive than TS (which only accepts `'`). Not a violation; SLIP-0010 also accepts H/h.

### F6.3 (INFO) — BIP-32 testnet version support: Ruby has it, TS doesn't
Ruby is a strict superset.

### F6.4 (POSITIVE) — Ruby guards BIP-32 depth at 255; TS overflows uint8
**Ruby is more correct.**

### F6.5 (POSITIVE) — Ruby BIP-39 strength validation strict to {128,160,192,224,256}; TS accepts any %32≥128
**Ruby matches BIP-39 spec; TS is over-permissive.**

### F6.6 (LOW) — Mnemonic normalisation timing differs
Ruby normalises at parse time; TS at seed-derivation time. Not a spec violation.

### F6.7 (MED) — ECIES Electrum decrypt can't handle noKey or uncompressed ephemeral
`ecies.rb:69-78`. Hardcodes `data[4, 33]`. TS branches on byte 4. Real interop gap for edge cases (mainstream compressed-and-present still works).
**Action**: Add optional `sender_public_key:` parameter to decrypt; parse byte 4.

### F6.8 (NONE) — ECIES Bitcore variant matches TS exactly
No issue.

### F6.9 (MED) — BSM verify API divergence (Ruby by address, TS by pubkey)
Both correct in different senses. Ruby is more faithful to original BSM intent. TS requires out-of-band pubkey.
**Action**: Keep Ruby's; add `verify_with_public_key` for parity.

### F6.10 (POSITIVE) — Ruby BSM rejects BIP-137 segwit flags
**Correct for BSV.**

### F6.11 (NONE) — SymmetricKey 32-byte IV nonstandard but matches TS
Cross-SDK consistent. No issue.

### F6.12 (NONE) — BRC-42 derivation matches spec and official vectors
No issue.

### F6.13 (NONE) — BRC-77 SignedMessage wire format and signing hash match TS
No issue.

### F6.14 (NONE) — BRC-78 EncryptedMessage wire format and KDF match TS
No issue.

### F6.15 (NONE) — BSM on empty message handled identically
No issue.

### F6.16 (LOW) — SignedMessage/EncryptedMessage placed under Primitives
TS puts them under `messages/`. Mild architectural drift.
**Action**: Optional move to `BSV::Messages`.

---

## PHASE 7 — Script Interpreter

### F7.1 (HIGH) — Chronicle-restored string opcodes unimplemented
`OP_SUBSTR` (0xb3), `OP_LEFT` (0xb4), `OP_RIGHT` (0xb5), `OP_LSHIFTNUM` (0xb6), `OP_RSHIFTNUM` (0xb7). Treated as no-ops; Ruby still has them slotted as `OP_NOP4..OP_NOP8`. TS and Go dispatch as real operations. Scripts using Chronicle string opcodes execute silently and incorrectly.
**Action**: Implement post-Chronicle semantics.

### F7.2 (HIGH) — Chronicle version-related opcodes incorrect
`OP_VER` should push 4-byte LE tx version; `OP_VERIF`/`OP_VERNOTIF` should compare to version and branch. Ruby treats all as reserved/illegal.
**Action**: Implement post-Chronicle semantics.

### F7.3 (INFO) — OP_IF/OP_ELSE cond-stack model differs from Go reference but matches TS
Ruby's two-value `:true`/`:false` stack + `else_stack` is functionally equivalent to TS but fragile under future changes.

### F7.4 (NONE) — One-OP_ELSE-per-OP_IF post-Genesis enforcement matches Go
TS is the outlier. Ruby is correct per CLAUDE.md.

### F7.5 (INFO/LOW) — OP_RETURN semantics diverge subtly from TS
Ruby is stricter (requires balanced conditionals after OP_RETURN); TS clears ifStack and exits.
**Action**: Specialist call needed on canonical BSV semantics.

### F7.6 (LOW) — OP_CHECKSIG doesn't strip signature from subScript
`crypto.rb:194-198`. TS/Go call `findAndDelete`. Under FORKID this is functionally harmless because sigs live in the unlocking script.
**Action**: Add for spec-compliance regardless.

### F7.7 (NONE) — CHECKMULTISIG off-by-one preserved correctly
Matches Bitcoin Core. No issue.

### F7.8 (MED) — CHECKMULTISIG capped at 20 keys
`crypto.rb:70-73`. BSV post-Genesis removed this limit; TS allows up to 2^31-1. Valid BSV multisig with 21+ keys rejected.
**Action**: Remove cap.

### F7.9 (MED) — NULLFAIL semantics divergence
`crypto.rb:43-58`. Ruby raises on any non-empty failed sig; TS pushes false. In `Interpreter.evaluate` (no-tx) any non-empty sig raises with misleading `SIG_NULLFAIL`.
**Action**: Push false in no-tx path; reserve raise for actual NULLFAIL violations.

### F7.10 (LOW) — Pubkey encoding doesn't reject hybrid prefixes
`crypto.rb:187-192`. Accepts 0x06/0x07. TS rejects.
**Action**: Verify against Phase 2 review.

### F7.11 (MED) — ScriptNumber 4-byte arithmetic limit not enforced + minimal-encoding off
`script_number.rb:18`, `stack.rb:41-43`. Single 750,000-byte cap is undocumented; `pop_int` defaults to `require_minimal: false`. Non-minimally-encoded operands silently succeed.
**Action**: Document the cap source; default minimal encoding ON for arithmetic.

### F7.12 (NONE) — OP_SPLIT boundary semantics correct
No issue.

### F7.13 (NONE) — OP_NUM2BIN sign-bit handling correct
Matches TS. No issue.

### F7.14 (POSITIVE) — OP_LSHIFT/RSHIFT byte-array semantics match Go and ref tests
TS's RSHIFT is subtly wrong; Ruby is correct.

### F7.15 (NONE) — `byte_shift_right` carry direction correct after re-read
No bug. Recommend cross-testing against `chronicle_opcodes_test.go`.

### F7.16 (LOW) — OP_MUL/DIV/MOD overflow checks missing
`arithmetic.rb:63-81`. Ruby uses bignums (no overflow per se) but no stack-memory limiter (see F7.18). DoS vector via OP_MUL with large operands.
**Action**: Add stack memory accounting.

### F7.17 (MED) — Missing clean-stack rule
`interpreter.rb:280-286`. Only checks top is truthy; TS additionally requires exactly one stack element.
**Action**: Specialist decision: consensus or policy?

### F7.18 (MED) — No stack memory limit
`stack.rb` entirely. TS has 32MB default limit tracked in real time.
**Action**: Add configurable memory limit matching TS.

### F7.19 (LOW) — Conditional-depth counter not enforced
Bounded only by available memory; combined with F7.18 → DoS vector.

### F7.20 (LOW) — OP_TOALTSTACK / OP_FROMALTSTACK altstack clearing differs from TS
Ruby clears between unlock/lock; TS persists. Bitcoin Core canonical behaviour needs verification.

### F7.21 (NONE) — FORKID hard-required on every sighash type
Correct for BSV. No issue.

---

## PHASE 8 — Wallet, Auth, Overlay

### F8.1 (HIGH) — `WalletClient` is a local stateful wallet, not a substrate proxy
`wallet_interface/wallet_client.rb:28`. 876 LOC of stateful wallet vs TS's 504 LOC substrate dispatcher. Same name, opposite role. Per CLAUDE.md belongs in `bsv-wallet` companion gem.
**Action**: Rename Ruby class; build a thin proxy that dispatches over substrates.

### F8.2 (HIGH) — Missing BRC-100 substrates entirely
Zero of TS's 5 substrates (`HTTPWalletJSON`, `HTTPWalletWire`, `WalletWireTransceiver`, etc.). Ruby has the wire serialiser but no HTTP transport on top.
**Action**: Port `HTTPWalletJSON` and `HTTPWalletWire`.

### F8.3 (HIGH) — Missing BRC-104 HTTP auth transport
No `/.well-known/auth`, no `x-bsv-auth-*` headers, no AuthFetch, no SimplifiedFetchTransport. Ruby has only an abstract `BSV::Auth::Transport`.
**Action**: Implement BRC-104 transport.

### F8.4 (HIGH) — Peer missing certificate exchange messages
`auth/peer.rb:110-116`. Handles 3 of BRC-103's 5 message types — missing `certificateRequest` and `certificateResponse`. Ruby cannot participate in dynamic-cert flows.
**Action**: Implement the missing message types.

### F8.5 (MED) — Peer missing high-level session orchestration API
TS has `toPeer`, `getAuthenticatedSession`, callback registration, `lastInteractedWithPeer`, multi-session-per-peer. Ruby has only manual turn-by-turn handshake.
**Action**: Add high-level API.

### F8.6 (HIGH) — Missing Certificate / VerifiableCertificate / MasterCertificate classes
TS has 796 LOC across these. Ruby stores certificates as plain hashes with no BRC-52 structural validation.
**Action**: Implement the certificate classes.

### F8.7 (MED) — Protocol-ID validation strict where TS normalises
`validators.rb:29`. TS lowercases-and-trims; Ruby rejects uppercase. Same code behaves differently across SDKs.
**Action**: Lowercase-and-trim before validation.

### F8.8 (LOW) — Validator includes permission rules BRC-43 doesn't require
`validators.rb:32-33,71-73`. Rejects 'admin', 'p ', 'default', '*basket' — none of these are in TS's `KeyDeriver`. Belongs in permissions layer.
**Action**: Move to permissions layer or remove.

### F8.9 (LOW) — Missing CachedKeyDeriver
TS provides 287 LOC of memoised key derivation. Ruby has no caching.
**Action**: Optional optimisation.

### F8.10 (LOW) — Namespace confusion: `BSV::WalletInterface` is empty shell; classes under `BSV::Wallet`
Legacy `BSV::Wallet::Wallet` collides with BRC-100 namespace.
**Action**: Pick one namespace; rename legacy class.

### F8.11 (HIGH) — snake_case wire-format API conflicts with BRC-100 camelCase
BRC-100 specifies camelCase. Ruby uses snake_case throughout. Future JSON substrate needs translator at every boundary.
**Action**: Either accept and add a translator, or use camelCase strings at wire boundaries.

### F8.12 (MED) — `listActions` / `listOutputs` ignore BRC-100 include flags
`wallet_client.rb:125-149`. `includeLabels`, `includeInputs`, etc. silently dropped. Result hash omits top-level `BEEF` field.
**Action**: Honour the include flags.

### F8.13 (MED) — `sign_action` doesn't implement SignActionOptions or `sendWith`
`wallet_client.rb:91-100`. No `acceptDelayedBroadcast`, `returnTXIDOnly`, `sendWith`, `sendWithResults`, no `ReviewActionResult`.
**Action**: Implement delayed-broadcast / batch model.

### F8.14 (MED) — `internalize_action` doesn't verify BEEF merkle proofs against headers
`wallet_client.rb:711-729`. Stores BUMPs without verifying root against block headers.
**Action**: Add header verification or expose hook for it.

### F8.15 (HIGH, SECURITY) — `acquire_certificate` 'direct' path writes unverified data
`wallet_client.rb:805-816`. User can pass arbitrary `signature:` and it persists as authentic. `prove_certificate` later treats it as valid.
**Action**: Verify certifier signature before storing.

### F8.16 (MED) — `acquire_certificate` issuance flow ad-hoc, not BRC-104
`wallet_client.rb:818-848`. POST to `certifier_url`, no AuthFetch, no signature verification on response.
**Action**: Use BRC-104 AuthFetch with BRC-103 signing.

### F8.17 (LOW) — `prove_certificate` is half the flow; no Ruby verifier API
`wallet_client.rb:314-345`. Encrypts keyring entries correctly but no `VerifiableCertificate` class on the verifier side.

### F8.18 (LOW) — `wire_source_tx_ancestors` recursion is unbounded
`wallet_client.rb:545-559`. Deep chains could blow stack; no cycle guard.
**Action**: Add depth cap and cycle detection.

### F8.19 (LOW, inherited) — Shamir uses field prime P instead of curve order N
Both Ruby and TS use P. Probability ~2^-128. Not a Ruby bug.

### F8.20 (LOW) — Polynomial random points may have minor RNG bias
Re-checked: Ruby's `OpenSSL::BN.rand(256)` with default top=-1 is fine. **No action.**

### F8.21 (LOW) — Overlay `HTTPSOverlayBroadcastFacilitator` missing offChainValues support
TS supports `taggedBEEF.offChainValues` with special header + framing. Ruby doesn't.
**Action**: Add offChainValues support.

### F8.22 (LOW) — Overlay TaggedBEEF / STEAK structure may be missing
Worth a follow-up pass on `overlay/types.rb`.

### F8.23 (LOW) — Overlay Historian and withDoubleSpendRetry missing
TS has both helpers; Ruby doesn't.

### F8.24 (NONE) — Overlay admin token uses Ruby-lowercase derivation but produces correct invoice strings
SHIP/SLAP tokens cross-SDK interoperable. Symptom of F8.7, not a bug.

### F8.25 (LOW) — `BSV::Attest` is imperative code inside the declarative SDK
`lib/bsv/attest/`. Per CLAUDE.md should be a `bsv-attest` companion gem. Currently coupled to legacy wallet.
**Action**: Extract to companion gem; use BRC-100 interface.

### F8.26 (LOW-MED) — Missing modules: kvstore, totp, identity client, contacts
Imperative / application-layer; absence aligns with declarative principle but blocks parity for several real apps.

### F8.27 (NONE) — Message types parity confirmed
EncryptedMessage and SignedMessage present in Ruby.

### F8.28 (LOW) — SessionManager multi-session-per-peer behaviour unverified
Worth a follow-up.

### F8.29 (LOW) — Nonce.create supports counterparty but not originator
TS passes `originator` to `wallet.createHmac`. Ruby drops it. Low severity (nonces self-verify).

### F8.30 (NONE) — Reveal linkage `proof_type: 0` is degenerate proof matching TS
Both SDKs return `proofType: 0` for specific linkage. Not a Ruby bug.

---

## SUMMARY TALLY

| Phase | HIGH | MED | LOW | NONE/POSITIVE | Total |
|---|---|---|---|---|---|
| 1 | 2 | 3 | 3 | 0 | 8 |
| 2 | 1 | 3 | 5 | 0 | 9 |
| 3 | 2 | 5 | 11 | 4 | 22 |
| 4 | 2 | 3 | 6 | 0 | 11 |
| 5 | 7 | 5 | 8 | 0 | 20 |
| 6 | 0 | 2 | 5 | 9 | 16 |
| 7 | 2 | 5 | 8 | 6 | 21 |
| 8 | 5 | 7 | 12 | 6 | 30 |
| **TOTAL** | **21** | **33** | **58** | **25** | **137** |

Cross-phase patterns:
1. **"Letter vs spirit" / round-trip-test masking** — F1.3, F1.5, F3.5, F4.1, F5.1, F5.2, F5.6, F5.7, F5.8 — code passes its own round-trip tests because two errors cancel, but cross-SDK interop or third-party inputs break.
2. **"Recognise everything, construct only what's valid" violations** — F2.4, F3.1, F3.2, F3.3, F3.5, F3.16 — parser is over-strict (raises on legitimate inputs) AND constructor is over-permissive (allows building invalid forms).
3. **Chronicle 2026 gaps** — F7.1, F7.2 — restored opcodes treated as no-ops or reserved.
4. **Security ergonomics** — F2.1 (no constant-time), F8.15 (no cert verification), F8.14 (no BEEF header verification).
5. **Architectural drift** — F8.1, F8.10, F8.25 — imperative code in declarative SDK; namespace confusion; wrong layer for class.
