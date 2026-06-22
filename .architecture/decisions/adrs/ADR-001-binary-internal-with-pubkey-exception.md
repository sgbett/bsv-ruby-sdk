# ADR-001: Binary-internal by default; public keys are the documented exception

## Status

Accepted

## Context

The SDK handles many byte-shaped values: transaction IDs, hashes, scripts, signatures, raw transactions, BEEF payloads, public keys. Each of these has a natural binary form (the bytes a hash function or wire protocol produces) and a hex form (the printable encoding JSON APIs and humans use). A consistent rule for which form is canonical internally avoids representation-mismatch bugs and the wasted conversions that drove the original `wtxid` / `dtxid` convention.

The `wtxid` / `dtxid` rule for transaction IDs has been settled in the SDK since 2026-05 (`docs/reference/wtxid-dtxid.md`): wire-order binary internally, display-order hex only at JSON or human boundaries, with runtime validation at every entry point. It eliminated a recurring class of bugs and has held up well.

Two questions remained open and were surfaced by the HLR #797 codebase audit:

1. Does the wire-order-by-default rule generalise to other binary/hex pairs (hashes, scripts, raw tx, BEEF)? Yes, and it already does in practice.
2. Does it generalise to **public keys**? The audit suggested yes, drawing parity with txids. The right answer turns out to be **no** — pubkeys are a deliberate exception, with prior decisions (HLRs #8 / #28 and PR #18 in bsv-wallet) standing behind that. The reasoning was lost in subsequent reviews; the HLR #797 fallout (and sgbett/bsv-wallet#300) recovered it.

This ADR captures both: the generalised rule and the pubkey carve-out, so future audits and reviews can land on a written decision rather than re-archaeology.

## Decision Drivers

* Eliminate the recurring class of representation-mismatch bugs (the `txid` ambiguity, generalised). The `wtxid` / `dtxid` rule has already paid off here; extending it removes the same risk for hashes, scripts, raw tx, BEEF.
* Avoid wasted conversions on internal hops (binary → hex → binary that crosses no real boundary). C1 in bsv-wallet#300 is the canonical example.
* Preserve the prior pubkey decision (hex throughout) where the reasoning is sound: pubkeys are curve-point material wrapped in a `PublicKey` object, not binary content with structural meaning; they're protocol identifiers crossing BRC boundaries far more often than txids.
* Make the rule and the exception both written and reviewable. The pubkey carve-out has caused review confusion twice (HLR #797 → reframed in the wrong direction once already) because it wasn't documented.
* Align the SDK and the wallet so a single rule covers both gems.

## Decision

**Default rule: binary internal.** Wherever a value has a natural binary form and a hex display form, the SDK keeps the binary form internally and converts to hex only at JSON or human boundaries. This generalises the existing `wtxid` / `dtxid` convention.

Covered types:

| Value | Internal form | Boundary conversion |
|------|----------------|--------------------|
| Transaction IDs | `wtxid` (32-byte wire-order binary) | `dtxid_hex` (display-order hex) |
| SHA-256 / RIPEMD-160 hashes | binary bytes | hex at JSON / log emit |
| Scripts (locking, unlocking) | binary bytes | `Script#to_hex` at emit |
| Signatures (DER) | binary bytes | hex at JSON emit |
| Raw transactions, BEEF | binary throughout | hex at JSON / display |

**Exception: public keys are hex internally.** Compressed secp256k1 public keys (33 bytes) are held as 66-character hex strings throughout the SDK and the wallet — in `KeyDeriver`, in BRC-100 method returns, in storage, in `Auth` / `Overlay` / `Identity` / `Registry` plumbing.

The reasoning behind the pubkey exception:

1. The canonical internal form for a pubkey isn't bytes — it's a `BSV::Primitives::PublicKey` object (curve point). Hex and binary are both serialisations of that single underlying value.
2. Pubkeys are protocol identifiers, not binary content. Unlike txids, they don't get hashed by the SDK, recomputed from raw tx, or indexed by structural bytes. They flow through as identity tokens.
3. Pubkeys cross BRC boundaries far more often than any other type. Every BRC-100 method has a pubkey somewhere; BRC-29 and BRC-43 also specify hex. Hex storage moves conversion off the boundary-heavy path.
4. The binary-internal rule already carves out spec-mandated hex. Pubkey BRC fields meet that test directly.

**Architectural Components Affected:**

* `BSV::Primitives` — `PublicKey` (canonical Ruby form is the object; both `to_hex` and `compressed` are valid serialisations). `Digest`, `Signature` follow the default rule (binary internal).
* `BSV::Script` — binary internal; `to_hex` at emit.
* `BSV::Transaction` — `Tx`, `Beef`, `MerklePath`, `Sighash`, `wtxid` / `dtxid` — already aligned.
* `BSV::Wallet` — `ProtoWallet`, `WalletWireTransceiver`, `WalletWireProcessor`, `Interface::BRC100`, serialisers. Every BRC-100 implementation returns pubkey fields as 66-char hex.
* `BSV::Auth`, `BSV::Overlay`, `BSV::Identity`, `BSV::Registry` — internal Ruby code consuming `wallet.get_public_key(...)[:public_key]` works in hex.
* Downstream consumers (bsv-wallet, bsv-attest, third-party apps) follow the same rule; conversions live at their JSON / HTTP emit boundary, not inside the SDK.

**Interface Changes:**

* `Interface::BRC100` — every implementation returns pubkey fields as 66-character hex strings (BRC-100 `PubKeyHex`). Wire bytes are still 33-byte compressed binary by the protocol; the conversion happens in the wire deserialiser.
* No new methods on existing classes. The rule formalises existing practice for most layers; the only behavioural fix needed is the wire transceiver's pubkey deserialisation (tracked under #798).

## Consequences

### Positive

* One coherent rule across the SDK with one explicit exception, making audit and review decisions deterministic.
* Eliminates the representation-mismatch bug class for all default-rule types.
* No wasted hex → binary → hex round-trips on internal hops for default-rule types.
* The pubkey exception is now written down — future audits and reviews can land on it directly instead of re-archaeology (which has already cost two review cycles).
* Aligns SDK and wallet under a single rule.

### Negative

* Two rules to remember (default + exception) is slightly heavier than one rule. Mitigated by writing both down in the same doc (`docs/reference/wtxid-dtxid.md`) and grouping the discussion together.
* BRC-100 specifies hex (`PubKeyHex`), which makes hex the *spec* canonical form for pubkeys but binary the *internal* form for txids — readers skimming spec text need to understand the txid carve-out is in the opposite direction. The wtxid/dtxid guide explains this explicitly.

### Neutral

* Most of the rule is already followed in practice. This ADR documents existing convention rather than introducing new behaviour.

## Implementation Strategy

### Blast Radius

**Impact Scope**: Largely descriptive. The default rule is already in place for txids, hashes, scripts, raw tx, BEEF. The pubkey exception is already in place in `ProtoWallet`, in bsv-wallet's `KeyDeriver`, and across `Auth` / `Overlay` / `Identity` / `Registry`. The single behavioural mismatch is `WalletWireTransceiver`'s reveal-linkage and get-public-key serialisers, which return binary today; the fix is in scope of #798.

**Affected Components**:

* Wire serialisers (`gem/bsv-sdk/lib/bsv/wallet/serializer/get_public_key.rb`, `reveal_counterparty_key_linkage.rb`, `reveal_specific_key_linkage.rb`) — convert binary → hex in `Result.deserialize`. #798.
* Loopback integration spec (`gem/bsv-sdk/spec/bsv/wallet/loopback_integration_spec.rb`) — assert hex parity with ProtoWallet, not 33-byte binary. #804.
* Documentation (`docs/reference/wtxid-dtxid.md`) — add the "principle generalises (with one exception)" section. #814 (this ADR is the other deliverable of #814).

**User Impact**: None for end users. SDK consumers writing HTTP / JSON code apply the same conversions they already do (`unpack1('H*')` for binary types at JSON emit; hex stays hex through pubkey fields).

**Risk Mitigation**: Runtime validation at boundaries for default-rule types (already in place for `wtxid` / `dtxid`; can be extended to hashes / scripts later if a recurring issue emerges). The pubkey exception is enforced by the loopback parity spec landing under #804.

### Reversibility

**Reversibility Level**: High in principle, low in practice.

The default rule documents existing practice. Reversing it would mean flipping the SDK to hex-internal across `wtxid`, scripts, raw tx, BEEF — extremely unlikely. The pubkey carve-out is also stable: it has been in place since HLRs #8 / #28, and the recovered reasoning shows why flipping it would re-introduce wasted conversion on the hot path.

## Alternatives Considered

### Alternative 1: Generalise binary-internal to pubkeys too

Apply the wtxid-style rule uniformly: pubkeys 33-byte binary internally, hex only at JSON emit. This was the first attempt at HLR #797 follow-up (ADR-001 in the original PR #813, since reverted).

* **Pro**: Single uniform rule, no exception to remember.
* **Con**: Inverts the existing pubkey-hex contract that has been stable since HLRs #8 / #28 across the wallet, certificates, the SDK's auth / overlay / identity / registry layers, and BRC-100 method returns. Requires a multi-layer refactor (132 spec failures from the proof-of-concept attempt on the `WalletWireTransceiver`-only patch).
* **Con**: Reintroduces hex ↔ binary round-trips on every BRC method call. Pubkeys cross BRC boundaries far more often than txids; the conversion lives on the hot path.
* **Con**: Discards the reasoning that motivated the original pubkey-hex choice (pubkeys are curve-point material, not binary content). The reasoning is sound; the audit didn't credit it.
* **Rejected** — the right move is to write down the exception, not eliminate it.

### Alternative 2: Hex internal for everything

Keep all cryptographic values as hex strings throughout, converting to binary only at primitive crypto operations.

* **Pro**: Easy to print and log; matches BRC text directly.
* **Con**: Every hash, comparison, storage operation, and crypto primitive call would convert hex → binary → hex. This was the state the `wtxid` / `dtxid` rule was introduced to fix; generalising the wrong way would re-create the original problem class.
* **Con**: Diverges from the wallet's `bytea` storage model.
* **Rejected** — opposite of the established direction.

### Alternative 3: Per-method representation choice (no SDK-wide rule)

Let each method decide; document case-by-case.

* **Pro**: Maximum flexibility per call site.
* **Con**: Reintroduces the original `txid` ambiguity that motivated the convention; reviewers cannot apply a single rule.
* **Con**: The HLR #797 fallout — and the false-start ADR-001 — demonstrate exactly what happens without an explicit written rule.
* **Rejected** — the value of one explicit rule (plus one explicit exception) outweighs per-method flexibility.

### Alternative 4: Match TS SDK (binary on wire, no SDK-wide hex contract)

Follow TypeScript SDK's pattern more literally; let representation be a substrate concern.

* **Pro**: Surface alignment with a reference SDK.
* **Con**: Diverges from the Ruby SDK's existing `wtxid` / `dtxid` rule and the wallet's storage model.
* **Con**: The Ruby SDK has its own audited model; TS SDK internals aren't binding on Ruby (mirrors the same call we made on `wtxid` / `dtxid`).
* **Rejected** — same logic as the `wtxid` / `dtxid` decision: walk our own path.

## Validation

* The default rule is already followed across `BSV::Primitives` (binary throughout for hashes, signatures), `BSV::Script` (binary), `BSV::Transaction` (`wtxid` enforced; `Beef`, `MerklePath` binary).
* The pubkey exception is followed by `BSV::Primitives::PublicKey` (object form with `to_hex` as canonical string), `ProtoWallet` BRC-100 methods (hex returns), bsv-wallet's `KeyDeriver` (hex), and the broader `BSV::Auth` / `BSV::Overlay` / `BSV::Identity` / `BSV::Registry` layers (consume hex from wallet).
* Outstanding gap: `WalletWireTransceiver` returns binary for the three pubkey-bearing BRC-100 methods. Tracked as #798; locked in by #804.
* The wallet-side mirror at sgbett/bsv-wallet#300 (Option B — accepted) keeps the rule consistent across both gems.

## References

* `docs/reference/wtxid-dtxid.md` — primary developer-facing guide; extended with the "principle generalises" section as part of this work.
* sgbett/bsv-wallet#300 — wallet-side decision (Option B accepted: "Pubkeys stay hex"). Recovered the original reasoning behind the pubkey carve-out.
* HLR #797 — codebase audit that surfaced both questions and prompted this ADR.
* #798 — wire transceiver returns binary; should be hex (the one outstanding code-level consequence of this ADR).
* #804 — loopback parity assertion locking the hex contract.
* #814 — documentation work (this ADR plus the wtxid-dtxid guide extension).
* HLRs #8 / #28 and PR #18 in bsv-wallet — original pubkey-hex decisions, recovered during HLR #797 fallout.

## Note on history

A previous attempt at this ADR (PR #813, since reset out of master) reached the opposite conclusion — that the binary-internal rule should generalise to pubkeys too. That ADR and its accompanying docs are gone from history. The reasoning that produced the wrong direction is preserved in this ADR's "Alternative 1" section so the next reviewer doesn't have to re-archaeology the same mistake.
