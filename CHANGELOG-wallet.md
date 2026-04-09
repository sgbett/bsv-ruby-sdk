# Changelog — bsv-wallet

All notable changes to the `bsv-wallet` gem are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- **Shared conformance suite** for `StorageAdapter`
  implementations at `spec/support/shared_examples_for_storage_adapter.rb`.
  `MemoryStore` and `FileStore` now both drive their behavioural
  tests through `it_behaves_like 'a storage adapter'`, and the
  extraction backfilled previously-missing coverage (certificate
  `:attributes` filter, `count_certificates`, proof and transaction
  round-trip, pagination ordering).

## 0.3.4 — 2026-04-08

Paired security patch release. Three P0 findings from the
[2026-04-08 cross-SDK compliance review](.architecture/reviews/20260408-cross-sdk-compliance-review.md)
plus follow-up hardening from the PR review pass. Must be installed
together — the `bsv-wallet` gemspec now pins its `bsv-sdk` dependency
to `>= 0.8.2, < 1.0` to enforce the paired upgrade and prevent a stale
pair where one gem has its fixes and the other doesn't.

Two GitHub Security Advisories accompany this release (draft until
CVE IDs return from MITRE):


### Security

- **`acquire_certificate` now verifies certifier signatures** before
  persisting (BRC-52). Both the `'direct'` and `'issuance'` acquisition
  paths previously wrote user-supplied `signature:` values to storage
  without any verification — a caller could forge a certificate that
  `list_certificates` / `prove_certificate` would later treat as
  authentic. This was a credential forgery primitive masquerading as
  an API finding. The new `BSV::Wallet::CertificateSignature` module
  builds the canonical BRC-52 preimage (matching the TS reference
  `Certificate#toBinary(false)` byte-for-byte) and delegates to
  `ProtoWallet#verify_signature`. Invalid certificates raise
  `BSV::Wallet::CertificateSignature::InvalidError` and are not
  persisted. Closes F8.15 (and the verification aspect of F8.16).



### Changed

- **`bsv-wallet.gemspec` bsv-sdk dependency pinned** to
  `>= 0.8.2, < 1.0`. The previous `~> 0.4` constraint was stale (wallet
  hasn't been tested against bsv-sdk 0.4.x in months) and would have
  let a user install `bsv-wallet 0.3.4` against an old `bsv-sdk` that
  was missing F1.3 and F5.13. Technically breaking — any consumer
  pinned to `bsv-sdk < 0.8.2` must upgrade — but un-breaking in
  practice: it forces users to the known-good pair rather than a
  silently-broken combination.

### Internal

- `lib/bsv/wallet_interface/**/*` added to the
  `Metrics/ModuleLength` exclusion list (was previously only excluded
  from `Metrics/ClassLength`). The new `CertificateSignature` module
  triggered the discrepancy.
- Review-feedback hardening bundled into the same PR to
  keep the security-patch window small: case-insensitive ARC failure
  matching, `Base64.strict_decode64` on BRC-52 preimage fields,
  `EncodingError` rescue in `CertificateSignature.verify!`, rejection
  of mixed string / symbol duplicate field names, malformed 2xx
  rejection in ARC, and even-length guard on hex signatures.

### Migration notes

- **Existing `bsv-wallet` users** pinned to `bsv-sdk ~> 0.4` will need
  to relax their constraint or upgrade. Anything installed before
  `bsv-wallet 0.3.4` is vulnerable to the F8.15 certificate forgery
  primitive.
- **Callers passing negative integers to `VarInt.encode`** (unlikely —
  the docstring already disallowed it) will now get an `ArgumentError`
  instead of silent corruption. Fix: pass non-negative values.
- **Callers relying on ARC broadcaster silently succeeding for INVALID
  / MALFORMED / MINED_IN_STALE_BLOCK / ORPHAN responses** will now see
  `BroadcastError` raised. Fix: handle the error — the previous
  behaviour was objectively wrong and any downstream logic that
  tolerated it was silently corrupt.
- **Callers of `acquire_certificate` with a fake or untrusted
  `signature:` field** will now see
  `BSV::Wallet::CertificateSignature::InvalidError`. Fix: ensure the
  certificate has been properly signed by the declared certifier.

### Test suite

- 3112 examples, 0 failures (up from 3080 on 0.8.1)
- 16 new regression tests for F1.3, F5.13, and F8.15
- 16 further regression tests for the review-feedback hardening
- Ruby 2.7 — 3.4 matrix green
- CodeQL clean; RuboCop clean across 266 files

## 0.3.3 — 2026-04-06

### Fixed

- `finalize_action` now stores the spending transaction so subsequent
  `internalize_action` / proof resolution flows can find it. Previously the
  wallet remembered the inputs and outputs but not the finalised tx itself.

## 0.3.2 — 2026-04-06

### Fixed

- `internalize_action` now stores **all** transactions from the
  incoming BEEF, not just the proven ones. Unproven ancestors are needed for
  later BEEF reconstruction in `create_action` → `to_beef`.

## 0.3.1 — 2026-04-06

### Fixed

- `internalize_action` now stores the subject transaction hex (not
  just its proof and outputs), so the wallet can rebuild BEEF for spends of
  the inbound outputs without re-fetching the tx.

## 0.3.0 — 2026-04-06

### Added

- **Pluggable proof store** for merkle proof persistence. The wallet
  is now a lightweight SPV node: `internalize_action` extracts and stores
  merkle proofs from incoming BEEF; `create_action` reattaches them to
  produce valid BEEF with BUMPs for ARC broadcast.
  - `ProofStore` interface with `store_proof` / `resolve_proof`.
  - `LocalProofStore` default implementation using `StorageAdapter`.
  - `WalletClient` accepts injectable `proof_store:` parameter.
  - Transaction caching (`store_transaction` / `find_transaction`) for
    ancestry reconstruction.
- `StorageAdapter` gains `store_proof`, `find_proof`,
  `store_transaction`, `find_transaction` methods, implemented in both
  `MemoryStore` and `FileStore`.

### Fixed

- `wire_source_from_storage` resolves merkle proofs via proof store
  so `to_beef` produces valid BEEF that ARC accepts. Previously, BEEF
  contained source transactions without proofs, causing ARC 463/468
  rejections.

## 0.2.2 — 2026-04-06

### Fixed

- `to_beef` now includes source transactions in the BEEF output, not
  just the subject transaction. Without ancestors, ARC could not validate the
  spend graph.

## 0.2.1 — 2026-04-06

### Added

- `WalletClient#create_action` now accepts `UnlockingScriptTemplate`
  objects (e.g. `P2PKH`) as input unlocking scripts, enabling template-based
  signing without BEEF.
- `wire_source_from_storage` fallback populates `source_satoshis`
  and `source_locking_script` from wallet storage when BEEF is absent or
  incomplete, enabling BIP-143 sighash computation for wallet-tracked
  outputs.
- `finalize_action` resolves template inputs via `sign_all` before
  serialisation.
- `MemoryStore#filter_outputs` supports outpoint filtering for
  efficient single-output lookups.

The sdk gem was re-released alongside this wallet change with no
behavioural changes of its own.

## 0.2.0 — 2026-04-01

### Added

#### Primitives


#### Transaction


#### Wallet

- **FileStore** — JSON file-backed persistent storage, now the
  default for `WalletClient`. Data survives process restarts. `MemoryStore`
  becomes explicit opt-in for tests.
- **File permissions** — directory created with 0700, files with
  0600. Warns via Logger on startup if permissions are too open.

## 0.1.2 — 2026-03-30

### Added

#### Script


#### Transaction


#### Wallet

- **BRC-31 Auth/Peer** — mutual authentication with nonce-based
  challenges, ECDSA signatures, and session management.
- **BRC-100 wire protocol** — binary ABI serialisation for all 28
  BRC-100 methods (call codes 1-28, VarInt encoding).
- **Certificate issuance** — `acquire_certificate` with
  `'issuance'` protocol (POST to certifier URL).

### Fixed

- Subject and certifier pinned in certificate issuance response
  (not overridable by remote certifier).
- Wire reader negative `privileged_reason` length crash.

This was the first formal `bsv-wallet` gem release tag. Wallet code that
landed in master before this date (notably the BRC-100 identity certificate
methods and the BRC-100 blockchain-data / authentication methods committed
during the sdk-0.3.1 window) is part of this gem's initial released state.
