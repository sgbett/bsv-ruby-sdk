# ADR-001: Binary-internal representation; hex at boundaries

## Status

Accepted

## Context

Cryptographic values in the SDK — transaction IDs, public keys, hashes, scripts, signatures — have two natural representations:

- A **binary** form: the raw bytes as produced by hash functions, serialised by the wire protocol, and consumed by primitive operations.
- A **hex** form: the printable encoding used in JSON APIs, logs, CLI output, and any context a human reads.

Bitcoin's wire and display orders for transaction IDs (a 15-year-old artefact of Satoshi's RPC layer reversing bytes for readability) made this concrete. A variable named `txid` could hold either; mismatches caused an extraordinary number of bugs across Bitcoin implementations. The SDK already addressed this for transaction IDs by introducing the `wtxid` / `dtxid` naming convention (`docs/guides/wtxid-dtxid.md`): wire-order binary internally, display-order hex only at JSON and human boundaries, with runtime validation rejecting the wrong format at every entry point.

The same ambiguity exists for every other binary/hex value pair — most prominently public keys (33 binary bytes vs 66 hex chars; BRC-100 names this `PubKeyHex`). It was applied implicitly across most of the SDK but had never been articulated as a general principle.

This came to a head during the HLR #797 codebase audit. An auditor flagged `WalletWireTransceiver` returning binary pubkey fields as a HIGH-priority bug ("wire roundtrip not shape-preserving"; ts-sdk converts to hex). The reframing during review surfaced two things:

1. The auditor had treated `Interface::BRC100` as if it were a JSON contract. It isn't — it's a Ruby method-shape contract (semantic key names and signatures). The BRC-100 *specification* describes a JSON wire format with hex-typed fields; the Ruby module describes the method signatures that produce values destined for that JSON form. Representation of those values inside the Ruby return hash is not the interface's concern.
2. The same wire-order-by-default rule that applies to txids applies here. The wire transceiver returning binary is correct; converting to hex inside the SDK would be wasted work for any consumer not crossing a JSON boundary.

This was reinforced by the parallel wallet-side decision (sgbett/bsv-wallet#300 Option A: binary-internal end-to-end, `bytea` columns, hex only at JSON emit), giving the SDK + wallet a single coherent rule.

## Decision Drivers

* Eliminate a recurring class of representation-mismatch bugs (the `txid` ambiguity, generalised)
* Avoid wasted conversions on every internal hop (binary → hex → binary patterns crossing no real boundary)
* Match the wallet's binary-internal storage and processing model so SDK + wallet agree end-to-end
* Preserve the SDK's declarative character — ship interfaces and primitives, let consumers own the imperative layer
* Make audit and review decisions deterministic — a recurring "is this a bug?" question gains a clear answer

## Decision

The SDK keeps cryptographic and protocol values in their **binary** form internally and converts to **hex** only at JSON or human boundaries.

This is a generalisation of the existing wtxid/dtxid rule. The wire-order-by-default convention applies to every binary/hex value pair, not only transaction IDs.

**Specifically:**

- **Transaction IDs** — `wtxid` (32-byte wire-order binary) internally; `dtxid` / `dtxid_hex` (display-order hex) only at JSON or human boundaries. Already established.
- **Public keys** — 33-byte compressed binary internally (`PublicKey#compressed`, the wire layer's serialised form, between-SDK-class parameters and returns, storage); hex (via `.unpack1('H*')` or `PublicKey#to_hex`) only at JSON or human boundaries.
- **Hashes (SHA-256, RIPEMD-160, HMAC outputs)** — binary throughout; hex only at boundaries.
- **Scripts and signatures** — binary throughout; hex only at boundaries.
- **`Interface::BRC100` methods** — return hashes contain values in their binary form. The interface is a Ruby method-shape contract: semantic keys and signatures, not a JSON shape. Consumers building HTTP / JSON layers convert at their emit boundary, exactly as they would convert `wtxid` → `dtxid_hex` for a JSON response.

**Architectural Components Affected:**

* `BSV::Primitives` — `PublicKey`, `PrivateKey`, `Signature`, `Digest`, `Hex` — primary producers/consumers of the binary forms
* `BSV::Script` — script bytes, opcode payloads
* `BSV::Transaction` — `Tx`, `Beef`, `MerklePath`, sighash, `wtxid`/`dtxid` (already aligned)
* `BSV::Wallet` — `ProtoWallet`, `WalletWireTransceiver`, `WalletWireProcessor`, `Interface::BRC100`, serialisers
* Downstream consumers (bsv-wallet, bsv-attest, third-party apps) build the JSON/HTTP emit layer

**Interface Changes:**

* No new types or method signatures. The principle is a representation rule, applied to existing values.
* `Interface::BRC100` documented as a Ruby method-shape contract, not a JSON contract.
* `WalletWireTransceiver`'s 33-byte binary pubkey returns are correct and locked in (see #804).
* `ProtoWallet`'s current hex returns at BRC-100 method boundaries become an alignment item (see #812).

## Consequences

### Positive

* One coherent rule across the SDK; auditor decisions become deterministic ("is this a bug?" → "is it crossing a JSON or human boundary?").
* Eliminates a category of representation-mismatch bugs that have plagued Bitcoin tooling for 15+ years.
* No wasted conversions on internal hops — binary stays binary all the way from wire to crypto primitive.
* Matches wallet's storage model (`bytea` end-to-end per bsv-wallet#300) — SDK + wallet talk binary natively.
* Reinforces the SDK's declarative character: the SDK ships primitives and interfaces; the JSON emit layer belongs to the consumer.

### Negative

* Consumers building HTTP / JSON layers must convert explicitly at their boundary. This is the same pattern they already apply for txids, so it is not new work — just consciously applied.
* BRC-100 spec uses hex-typed names (`PubKeyHex`); the Ruby interface holds binary. Readers who skim spec text and assume the Ruby module mirrors the JSON contract will be momentarily confused. The wtxid-dtxid guide and this ADR address that explicitly.
* Existing ProtoWallet code at the BRC-100 boundary returns hex; bringing it into alignment is a small refactor (#812).

### Neutral

* The wire format itself is unchanged — bytes on the wire have always been binary 33 bytes. This ADR documents what the Ruby side does with those bytes after deserialisation, not the wire protocol.
* The rule is a clarification of existing practice for txids; for other types it makes implicit practice explicit.

## Implementation Strategy

### Blast Radius

**Impact Scope**: The rule is already followed by `BSV::Primitives` (binary throughout), `BSV::Transaction` (`wtxid` enforced), `BSV::Script` (binary), and `WalletWireTransceiver` (binary). The active alignment item is `ProtoWallet` (#812). No mass refactor required; this ADR mostly documents established practice.

**Affected Components**:

- `ProtoWallet` — small refactor to return binary at BRC-100 boundary; coordinated with bsv-wallet#300.
- Loopback integration spec — assertions updated from hex to binary parity (#804).
- Downstream consumers building HTTP/JSON layers — apply conversions at their emit boundary (most already do).

**User Impact**: None for end users. SDK consumers building wallet UIs or JSON APIs apply `.unpack1('H*')` or `PublicKey#to_hex` at their JSON boundary — the same pattern they already apply for txids.

**Risk Mitigation**:

- Runtime validation at boundaries (existing for wtxid/dtxid; mirrors for pubkeys can be added if a recurring issue emerges).
- ADR + extended `wtxid-dtxid.md` guide give reviewers and future contributors a single referent.

### Reversibility

**Reversibility Level**: High in principle, Low in practice.

The rule documents existing practice; reversing it would require flipping the SDK to hex-internal across `wtxid`, public keys, scripts, etc. This would invert 15+ years of accumulated Bitcoin convention learning. Highly unlikely.

## Alternatives Considered

### Alternative 1: Hex-internal everywhere

Keep cryptographic values as hex strings throughout the SDK, converting to binary only at primitive crypto operations.

* **Pro**: Easy to print and log; matches BRC-100 spec text directly.
* **Con**: Every hash, comparison, storage operation, and crypto primitive call would convert hex → binary → hex. Performance and bug surface both worse.
* **Con**: Diverges from the wallet's `bytea` storage model.
* **Rejected** — the wasted conversions on the hot path were the original reason the wtxid/dtxid rule exists. Generalising the rule rather than reversing it.

### Alternative 2: Per-method representation choice (no SDK-wide rule)

Let each method decide; document case-by-case.

* **Pro**: Maximum flexibility per call site.
* **Con**: Reintroduces the `txid` ambiguity that motivated the original convention; reviewers cannot apply a single rule.
* **Con**: Recurring "is this a bug?" question — exactly what HLR #797 demonstrated.
* **Rejected** — the value of a single explicit rule outweighs per-method flexibility.

### Alternative 3: Match TS SDK (convert to hex at wire deserialise)

Follow the TypeScript SDK's pattern of converting to hex in the wire transceiver's deserialiser.

* **Pro**: Surface alignment with one reference SDK.
* **Con**: Diverges from both the Ruby SDK's existing `wtxid`/`dtxid` rule and the wallet's `bytea`-internal model. The reframing in HLR #797 established that BRC-100 is a Ruby method-shape contract; what TS SDK does internally is not binding on the Ruby side, exactly as `wtxid`/`dtxid` are not bound by TS's `txid` choice.
* **Rejected** — explicitly "we walked our own path with wtxid and dtxid and are not about to change this." Same logic applies here.

## Validation

* The rule applies to existing practice across `BSV::Primitives`, `BSV::Transaction`, `BSV::Script`, and `WalletWireTransceiver` today — no behavioural change required for those.
* Test suite green at adoption (5,900 bsv-sdk + 30 bsv-attest examples passing).
* Alignment items tracked as SDK issues #804 (loopback parity assertion) and #812 (ProtoWallet alignment).
* Wallet-side mirror at sgbett/bsv-wallet#300 keeps the binary discipline consistent across both gems.

## Pragmatic Enforcer Analysis

**Necessity Assessment**: 9/10

The rule prevents a recurring class of representation-mismatch bugs (the wtxid/dtxid ambiguity, generalised) and directly resolves an audit question (HLR #797 → #798 closeout) that would otherwise recur each review cycle. Cost of waiting is real: every audit, every code review, every contributor onboarding repeats the same conversation. Evidence is the conversation thread itself.

**Complexity Assessment**: 2/10

Adds no new abstractions, types, or method signatures. Documents and generalises an existing convention. Learning curve is one paragraph and one analogy ("pubkeys are like txids"). No new dependencies.

**Alternative Analysis**: Three alternatives considered explicitly above. Hex-internal (alt 1) is the inverse choice and was rejected on performance and divergence grounds. Per-method (alt 2) reintroduces the original ambiguity. TS SDK parity (alt 3) was explicitly rejected by the project's "walked our own path" stance.

**Simpler Alternative Proposal**: The simplest alternative would be "no ADR; the wtxid-dtxid guide is sufficient." Rejected because (a) the guide is txid-specific by its title and history and (b) the principle is foundational enough that a contributor or auditor needs to land on it as a load-bearing decision, not as advice tucked into a txid-naming guide. ADR is the right vehicle.

**Recommendation**: Approve.

**Pragmatic Score**: Necessity 9, Complexity 2, Ratio 0.22 (target < 1.5).

**Overall Assessment**: Appropriate engineering. Documents a foundational principle with measured scope; introduces no new complexity; resolves a recurring decision point; aligns SDK and wallet under a single rule.

## References

* `docs/guides/wtxid-dtxid.md` — primary developer-facing guide; extended with the generalised principle in PR #813.
* `gem/bsv-sdk/lib/bsv/wallet/interface/brc100.rb` — the Ruby method-shape contract referenced above.
* `gem/bsv-sdk/spec/bsv/wallet/loopback_integration_spec.rb:51-68` — existing binary contract for `get_public_key`; precedent for the binary-pubkey rule.
* HLR #797 — codebase correctness audit that surfaced the reframing.
* #798 — closed not-a-bug; closeout comment carries the reframing rationale.
* #804 — T1: loopback parity assertion locking in the binary contract.
* #812 — P1: ProtoWallet alignment with the principle.
* PR #813 — `wtxid-dtxid.md` extension.
* sgbett/bsv-wallet#300 — wallet-side mirror (Option A: binary-internal end-to-end).
