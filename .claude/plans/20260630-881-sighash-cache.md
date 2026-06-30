# Plan: Issue #881 — Russian-doll sighash & wire cache

**Issue:** https://github.com/sgbett/bsv-ruby-sdk/issues/881
**Date:** 2026-06-30
**Author:** Simon Bettison

## 1. Statement of intent

Two first-class objectives:

- **Security.** Today's "recompute everything" is implicit safety — change the underlying data and the next sighash reflects it. Introducing a cache without explicit invalidation creates a sign-against-stale-state failure mode (silent invalid signatures, broadcast rejection in the benign case, semantic confusion in the malign). Invalidation is not ergonomic polish; it is the security control that makes caching correct.
- **Performance.** Eliminate the O(N × (N + M)) hashing work in `Tx#verify` (and `sign`). Asymptotic guarantee, not a partial mitigation.

None of the reference SDKs (TS, Go, Python) memoise across inputs of the same tx — TS caches inside a per-input `Spend`, Go and Python do not cache. This is a deliberate divergence, not a port.

## 2. Cache tree (five layers, Russian-doll)

```
L5 — sighash digest               Hash{[idx, type] => 32 bytes}
L4 — sighash preimage             Hash{[idx, type] => bytes}
L3 — component hashes             hash_prevouts: 32 B ivar
                                  hash_sequence: 32 B ivar
                                  hash_outputs_all: 32 B ivar
                                  hash_outputs_single: Hash{idx => 32 B}
L2 — Tx#to_binary, Tx#wtxid       String, 32 B
L1 — input.outpoint_binary        per-input ivar (outpoint is attr_reader,
                                  immutable — no invalidation needed)
     input.to_binary              per-input ivar (for L2)
     output.to_binary             per-output ivar
```

- L3's `ZERO_HASH` branches store nothing; the live cache is three ivars + one small Hash.
- L4/L5 are bypassed when `subscript:` is non-nil (override case, treat as one-off; never pollute the cache).
- L2 folds in the wtxid + `to_binary` work because its invalidation domain is a superset of L3's (anything that changes sighash components also changes the wire format; plus `unlocking_script=` which changes wire but not sighash).

## 3. Invalidation contract

Reviewer-facing table — this is the security control, not just an optimisation.

| Mutation | Invalidates |
|---|---|
| `Tx#add_input(input)` | all sighash + wire caches |
| `Tx#add_output(output)` | all sighash + wire caches |
| `TransactionInput#sequence=` | `hash_sequence`, all L4/L5, `to_binary`, `wtxid` |
| `TransactionInput#unlocking_script=` | `to_binary`, `wtxid` only (unlocking script does not enter the preimage) |
| `TransactionInput#source_satoshis=` | L4/L5 for that idx only |
| `TransactionInput#source_locking_script=` | L4/L5 for that idx only |
| `TransactionOutput#satoshis=` | `output.to_binary`, `hash_outputs_*`, all L4/L5, `to_binary`, `wtxid` |
| `TransactionOutput#locking_script=` | (same as above) |
| Direct `tx.inputs <<`, `tx.outputs.pop`, splice | **undefined** — documented on `attr_reader :inputs, :outputs` |
| `Tx#invalidate_sighash_cache!` | public escape hatch — clears the lot |

## 4. Owning-Tx backref — explicit design call

`TransactionInput` and `TransactionOutput` gain a private `@owning_tx` ivar, set when `Tx#add_input` / `Tx#add_output` runs. Per-struct setters call `@owning_tx&.invalidate_*` after writing the field. This is the only mechanism that makes per-field mutation safe without forcing every caller through opaque builder methods.

Reviewer notes (also reflected in YARD and the docs reference page):

- **Cycle safety.** `input → tx → @inputs[i] → input` is a cycle. CRuby's mark-and-sweep GC handles cycles correctly; no `WeakRef` needed, no leak. JRuby and TruffleRuby behave identically. Documented on the new ivar.
- **One owner.** An input or output belongs to one `Tx` at a time. `add_input` / `add_output` raise `ArgumentError` if `@owning_tx` is already set to a different `Tx`. Sharing inputs across `Tx` instances is anti-idiomatic and gets a loud failure instead of silent cache corruption.
- **No public reader.** `owning_tx` is set internally only; consumers do not traverse upward. Avoids surface that downstream gems would lean on.
- **Field-targeted invalidation.** Setters bubble to the *specific* slice they dirty (e.g., `unlocking_script=` does not touch sighash caches because unlocking scripts don't enter the preimage). Coarser-grained "invalidate everything" obscures intent and discards reusable state.
- **Existing flows are safe.** During `Tx#verify`, lines 664–665 set `source_locking_script ||=` / `source_satoshis ||=` *before* `verify_input` reaches `sighash`. The cache populates after resolution, so we never cache then read a stale value.

## 5. What is not in scope, with rationale

Each entry states *why* it does not belong in this PR, not "out of scope" alone.

- **`Digest.sha256d` OpenSSL context reuse** — pure performance win, but orthogonal: stacks multiplicatively with #881 rather than enabling it. Promoted as **Sibling A** so it lands on its own merits, and either issue can ship first.
- **ECDSA verify result memoisation for repeated `(pubkey, msg, sig)` triples** — narrower applicability (multisig with shared pubkeys, duplicated ancestor sigs), and a wider security risk surface (a buggy verify-result cache silently approves invalid signatures). Deferred pending workload telemetry to size the prize. Not filed yet — needs evidence.
- **Verify-time ancestor dedup** — *already in the code*: `verified[wtxid]` Hash at `tx.rb:640`. No work needed.
- **`Tx#to_ef` memoisation** — Extended Format is broadcast-only and typically called once per Tx. Deferred; revisit if the broadcast path shows it as a hotspot.
- **`Ripemd160` reuse** — implementation is pure Ruby (`gem/bsv-sdk/lib/bsv/primitives/ripemd160.rb`), not OpenSSL-backed. Different optimisation (C extension port or OpenSSL legacy-provider integration). Out of scope for Sibling A as well; would be its own follow-up if hot in profiles.

## 6. Acceptance criteria

- L1: `outpoint_binary`, `input.to_binary`, `output.to_binary` memoised; output setters invalidate via backref.
- L2: `Tx#to_binary`, `Tx#wtxid` memoised; invalidated by `add_input`/`add_output`, `unlocking_script=`, `sequence=`, output mutations.
- L3: three component-hash methods compute exactly once per cache lifetime.
- L4: `sighash_preimage(idx, type)` memoised when `subscript:` is nil; bypassed otherwise.
- L5: `sighash(idx, type)` memoised when `subscript:` is nil; bypassed otherwise.
- Owning-Tx backref: set by `add_input`/`add_output`; raises on rebind.
- Public `Tx#invalidate_sighash_cache!` present and documented.
- All existing sighash, signing, verify, wtxid, and BEEF specs pass bit-equivalent (the correctness-as-security floor).
- Regression spec: instrument `Digest.sha256d`; for a 10-input/10-output `Tx#verify`, exactly 3 component-buffer hashes occur (down from 30 today).
- Invalidation specs covering each row of §3's contract table — mutate, recompute, assert the post-mutation value is returned.
- No new public API beyond `Tx#invalidate_sighash_cache!`; no behavioural changes to existing callers.

## 7. Implementation phases (one commit per phase, ships green each step)

Per the project's per-task commit convention.

**Phase A — Foundations (no behaviour change).**

- Add private `@owning_tx` ivar to `TransactionInput` and `TransactionOutput`.
- `Tx#add_input` / `add_output` set the backref; raise on rebind.
- Add no-op `Tx#invalidate_sighash_cache!`.
- Specs: backref set on add, rebind raises.

**Phase B — Layer 1 memos.**

- `TransactionInput#outpoint_binary` `||=` (immutable; no invalidation needed).
- `TransactionInput#to_binary` `||=` + invalidate on `unlocking_script=` / `sequence=`.
- `TransactionOutput#to_binary` `||=` + invalidate on `satoshis=` / `locking_script=`.
- Setters bubble to `@owning_tx&.invalidate_*` for the slice they dirty.
- Specs: memo populates, mutation invalidates.

**Phase C — Layer 3 component hashes (the issue's headline fix).**

- Three component methods become `||=` with branch on `anyone_can_pay` / `base_type`.
- `hash_outputs_single` keyed Hash for the SIGHASH_SINGLE branch.
- Tx-level invalidators implemented; called from setter bubbles and `add_input` / `add_output`.
- Specs: 10-input verify computes each component exactly once; invalidation specs cover each contract row.

**Phase D — Layer 4/5 preimage + digest memos.**

- `sighash_preimage(idx, type)` `||=` when `subscript:` nil; bypass otherwise.
- `sighash(idx, type)` `||=` when `subscript:` nil.
- Per-idx invalidation when `source_satoshis=` / `source_locking_script=` fire.
- Specs: cache hit for repeat `(idx, type)`; subscript bypasses cache.

**Phase E — Layer 2 wire memos (folds in wtxid).**

- `Tx#to_binary` `||=`.
- `Tx#wtxid` `||=`.
- Invalidation hooked into the existing invalidator family.
- Specs: wtxid changes after `unlocking_script=` (signing flow); `to_binary` memoises across repeated calls.

**Phase F — Docs and regression spec.**

- YARD on each memoised method describing the contract and invalidation surface.
- `docs/reference/sighash-cache.md`: Russian-doll diagram, invalidation table, escape hatch, "build then sign/verify" idiom. Half a page.
- Regression spec: `Digest.sha256d` call counter over a 10-input/10-output verify proves the linear-not-quadratic property structurally.

## 8. Risk register

| Risk | Mitigation |
|---|---|
| Backref creates retainer cycle | CRuby mark-and-sweep handles cycles; documented for reviewer comfort |
| Input/output shared across two Txs | `add_input` raises on rebind; spec coverage |
| Internal call site forgets to use cache → silent perf regression | Phase F counter spec catches it |
| Subscript-passing caller hits the cache | L4/L5 bypass when `subscript:` is non-nil; spec covers |
| Concurrent verify on same Tx instance | `Tx` is not declared thread-safe today (existing setters mutate); no regression; noted for future |
| Memo string aliased and externally mutated | Cached binaries returned `.freeze`d at memo time to make aliasing safe |
| Pre-1.0 contract shift surprises downstream | The pre-1.0 "no shims" policy applies (`feedback_no_compat_shims`); breaking change is documented but accepted |

## 9. Why no benchmark acceptance criterion

The asymptotic argument is arithmetic, not empirical: N × (N + M) → N + M is provable by code inspection. There is no "is there a win?" doubt that a benchmark could resolve. The regression spec (counter on `Digest.sha256d`) is the right artifact — it asserts the structural property that creates the win, and it will fail on future code paths that accidentally bypass the cache. A wall-clock benchmark would be flakier and tells us strictly less.

## 10. Files anticipated

- `gem/bsv-sdk/lib/bsv/transaction/tx.rb` — invalidation hooks, L2–L5 memos, the three rewritten component methods, public `Tx#invalidate_sighash_cache!`.
- `gem/bsv-sdk/lib/bsv/transaction/transaction_input.rb` — `@owning_tx`, L1 memos, setter overrides.
- `gem/bsv-sdk/lib/bsv/transaction/transaction_output.rb` — `@owning_tx`, L1 memos, setter overrides.
- `gem/bsv-sdk/spec/bsv/transaction/tx_cache_spec.rb` — new file: memoisation + invalidation + regression specs.
- `gem/bsv-sdk/spec/bsv/transaction/tx_spec.rb` — extended where mutation-then-recompute coverage is missing.
- `docs/reference/sighash-cache.md` — new docs reference page.
- YARD on each cached method and `Tx#invalidate_sighash_cache!`.

## 11. Companion deliverables

- **Sibling A** — OpenSSL digest context reuse (`Digest.sha256d` and friends). Filed alongside this plan.

## 12. Open questions

None outstanding. Design calls in §2, §3, §4, §5 confirmed in conversation 2026-06-30.
