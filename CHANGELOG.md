# Changelog

All notable changes to this project will be documented in this file.

This repository ships several gems with independent versioning:

- **`bsv-sdk`** — the declarative SDK (primitives, script, transaction, etc.)
- **`bsv-wallet`** — the BRC-100 wallet interface gem (depends on `bsv-sdk`)
- **`bsv-wallet-postgres`** — PostgreSQL-backed `StorageAdapter` for `bsv-wallet`
- **`bsv-attest`** — data attestation helpers built on top of `bsv-sdk`

Gems may release on different schedules. Section headers identify which
gem(s) released, e.g.:

- `## sdk-0.7.0 / wallet-0.3.0 — 2026-04-06` — both gems released together
- `## sdk-0.6.1 — 2026-04-05` — sdk-only release
- `## wallet-0.3.3 — 2026-04-06` — wallet-only release

Every bullet is prefixed with `[sdk]`, `[wallet]`, `[wallet-postgres]`, or
`[attest]` to disambiguate which gem the change belongs to, regardless of
which header it sits under.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and each gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
independently.

## Unreleased — sdk-0.9.0

### Testing

- [sdk] **Cross-SDK conformance vector suite** ([#307](https://github.com/sgbett/bsv-ruby-sdk/issues/307)).
  Canonical test vectors are now vendored under `spec/conformance/vectors/`
  and executed as part of the default test run. The initial set covers
  BRC-42 key derivation (private + public), `SymmetricKey` AES-256-GCM
  decryption, BIP-143 sighash, legacy sighash, the Bitcoin Core
  `script_tests.json` corpus, BUMP parse/round-trip, and three canonical
  BEEF fixtures (BRC-62, BRC-95 / V2 multi-tx, base64). Provenance (source
  SDK, source path, upstream commit SHA) is tracked in
  `spec/conformance/vectors/README.md`; the sync procedure lives at
  `docs/testing/conformance-vectors.md`. Existing inline BRC-42 and BEEF
  vectors in `spec/conformance/` have been migrated to load from the
  vendored files, so future syncs are a plain `diff` rather than a Ruby
  literal edit.

  Four vector families (`sighash_bip143.json`, `sighash_legacy.json`,
  `script_tests.json`) are vendored but their execution is deferred:
  legacy sighash is not supported on BSV (kept for reference only);
  BIP-143 vectors require a non-FORKID sighash entry point that the
  Ruby SDK correctly rejects, so execution is deferred to the A2 cluster;
  `script_tests.json` is deferred to A5 (parser) and A6 (interpreter).
  Each deferred spec documents its gap explicitly.

## wallet-postgres-0.1.0 — 2026-04-09

Initial release of `bsv-wallet-postgres`, a PostgreSQL-backed
`BSV::Wallet::StorageAdapter` implementation. Unblocks production
deployments of `bsv-wallet` where state has to survive container
restarts, and makes multi-instance wallet services possible for the
first time.

### Added

- [wallet-postgres] **`BSV::Wallet::PostgresStore`** — full
  `StorageAdapter` implementation over Sequel + Postgres. Passes the
  same shared conformance suite that MemoryStore and FileStore pass
  (53 examples), plus 10 postgres-specific specs covering upsert
  semantics, GIN tag queries, JSONB attribute containment, concurrent
  inserts, and migration idempotency.

- [wallet-postgres] **Shipped Sequel migration** at
  `lib/bsv/wallet_postgres/migrations/001_create_wallet_tables.rb`.
  Five tables (wallet_outputs, wallet_actions, wallet_certificates,
  wallet_proofs, wallet_transactions) with JSONB data columns,
  dedicated indexed columns for filter paths, and GIN indexes on the
  `tags` / `labels` arrays.

- [wallet-postgres] **`PostgresStore.migrate!(db)`** convenience
  wrapper over `Sequel::Migrator.run` so consumers can apply the
  shipped schema with a single call. Operators who prefer their own
  migration framework can copy the migration file instead.

- [wallet] **Shared conformance suite** for `StorageAdapter`
  implementations at `spec/support/shared_examples_for_storage_adapter.rb`.
  `MemoryStore` and `FileStore` now both drive their behavioural
  tests through `it_behaves_like 'a storage adapter'`, and the
  extraction backfilled previously-missing coverage (certificate
  `:attributes` filter, `count_certificates`, proof and transaction
  round-trip, pagination ordering).

- [wallet-postgres] **Docs** at `docs/guides/wallet-postgres.md` with
  a 30-second quickstart, schema overview, and production
  considerations (pool sizing, multi-instance, backups,
  thread-safety).

### Infrastructure

- **CI postgres service**. The GitHub Actions test job now runs a
  Postgres 16 container and exposes `DATABASE_URL` to rspec, so the
  `:postgres`-tagged specs run against a live database on every
  Ruby matrix row (2.7 → 3.4). Local developers without Postgres
  still get a green suite — those specs skip gracefully.

### Dependencies

- `bsv-wallet-postgres` runtime: `bsv-wallet >= 0.3.4, < 1.0`,
  `sequel ~> 5`, `pg ~> 1`. The wallet floor matches the pinning style
  `bsv-wallet` uses for its `bsv-sdk` dependency so security releases
  propagate.

## sdk-0.8.2 / wallet-0.3.4 — 2026-04-08

Paired security patch release. Three P0 findings from the
[2026-04-08 cross-SDK compliance review](.architecture/reviews/20260408-cross-sdk-compliance-review.md)
plus follow-up hardening from the PR review pass. Must be installed
together — the `bsv-wallet` gemspec now pins its `bsv-sdk` dependency
to `>= 0.8.2, < 1.0` to enforce the paired upgrade and prevent a stale
pair where one gem has its fixes and the other doesn't.

Two GitHub Security Advisories accompany this release (draft until
CVE IDs return from MITRE):

- [GHSA-hc36-c89j-5f4j](.security/advisories/2026-0001-acquire-certificate-signature-bypass.md) — F8.15 / F8.16 partial — `acquire_certificate` persists unverified certifier signatures (CWE-347, CVSS 8.1 HIGH)
- [GHSA-9hfr-gw99-8rhx](.security/advisories/2026-0002-arc-broadcaster-failure-statuses.md) — F5.13 — ARC broadcaster treats failure statuses as success (CWE-754, CVSS 7.5 HIGH)

### Security

- [wallet] **`acquire_certificate` now verifies certifier signatures** before
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

- [sdk] **`VarInt.encode` now rejects negative integers** and values
  above 2^64 − 1. Previously `VarInt.encode(-1)` fell into the single-
  byte branch and emitted `0xFF` (the marker for a 9-byte encoding),
  silently corrupting the transaction stream with no exception raised.
  The docstring already required a non-negative integer; the
  implementation did not enforce it. Closes F1.3.

- [sdk] **ARC broadcaster recognises the full failure status set**. The
  previous `REJECTED_STATUSES` contained only `REJECTED` and
  `DOUBLE_SPEND_ATTEMPTED`; responses with txStatus `INVALID`,
  `MALFORMED`, `MINED_IN_STALE_BLOCK`, or any `ORPHAN`-containing
  `txStatus` / `extraInfo` were silently treated as successful
  broadcasts. Callers relying on `broadcast()` to signal failure would
  trust transactions that were never actually accepted by the network.
  The new failure set matches the TypeScript reference broadcaster
  exactly, and case-insensitive matching defends against ARC's
  documented history of emitting values outside its own OpenAPI enum
  (TS issue #105). Malformed 2xx responses without a `txid` field
  also raise, closing the same silent-success class for shape
  corruption. Closes F5.13.

### Changed

- [sdk] **ARC broadcaster HTTP wire format** brought into line with the
  TypeScript reference:
  - Content-Type is now `application/json` (was `application/octet-stream`)
  - Body is `{"rawTx": hex}` — Extended Format (BRC-30) hex when every
    input has `source_satoshis` / `source_locking_script` populated
    (so ARC can validate sighashes without fetching parents), falling
    back to plain raw-tx hex otherwise
  - New `XDeployment-ID` header (default: `bsv-ruby-sdk-<random hex>`,
    overridable via `deployment_id:` constructor kwarg)
  - New optional `X-CallbackUrl` and `X-CallbackToken` constructor
    kwargs for ARC status callbacks

- [wallet] **`bsv-wallet.gemspec` bsv-sdk dependency pinned** to
  `>= 0.8.2, < 1.0`. The previous `~> 0.4` constraint was stale (wallet
  hasn't been tested against bsv-sdk 0.4.x in months) and would have
  let a user install `bsv-wallet 0.3.4` against an old `bsv-sdk` that
  was missing F1.3 and F5.13. Technically breaking — any consumer
  pinned to `bsv-sdk < 0.8.2` must upgrade — but un-breaking in
  practice: it forces users to the known-good pair rather than a
  silently-broken combination.

### Internal

- [sdk] `lib/bsv/network/**/*` added to `Metrics/ClassLength` and
  `Metrics/ParameterLists` RuboCop exclusion lists to match the
  existing treatment of `lib/bsv/wallet_interface/**/*`. ARC is
  HTTP-client boilerplate in the same shape.
- [wallet] `lib/bsv/wallet_interface/**/*` added to the
  `Metrics/ModuleLength` exclusion list (was previously only excluded
  from `Metrics/ClassLength`). The new `CertificateSignature` module
  triggered the discrepancy.
- [sdk, wallet] Review-feedback hardening bundled into the same PR to
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

## sdk-0.8.1 — 2026-04-08

### Fixed

- [sdk] **`Transaction#to_beef` strips phantom `txid: true` leaves** —
  when a proof loaded from a shared `LocalProofStore` carries txid flags
  for transactions that are not part of the bundle being constructed,
  `to_beef` now rebuilds each per-block BUMP from only the bundle's own
  txids instead of propagating the phantoms into the serialised output.
  ARC previously rejected such BEEFs with misleading parser errors,
  blocking any wallet workflow that received a BEEF via
  `internalize_action` and then spent the internalised UTXOs.
  Closes #302.

### Added

- [sdk] **`MerklePath#extract(txid_hashes)`** — returns a new trimmed
  compound path covering only the requested txids, reconstructing the
  minimum set of sibling hashes at each tree level. Raises
  `ArgumentError` on empty input, unknown txid, or root mismatch.
  Ported from the TypeScript SDK. Used internally by
  `Transaction#to_beef` and available for direct use.
- [sdk] **`MerklePath#trim`** — removes internal nodes not required by
  level-zero txid leaves. Called implicitly by `#combine` and `#extract`
  and rarely needs to be invoked directly. Ported from the TypeScript
  SDK.
- [sdk] **`MerklePath#initialize_copy`** — `.dup` now produces a new
  MerklePath whose outer and level arrays are independent of the
  source, so the copy can be freely mutated via `#combine`, `#trim`,
  or `#extract` without affecting the original. `PathElement`s
  remain immutable and are shared between source and copy.

### Changed

- [sdk] **`MerklePath#combine`** now calls `#trim` at the end so merged
  paths stay minimal across repeated merges, matching the TypeScript
  SDK. Combined paths are strictly smaller than before — external
  callers that inspected `mp.path` after `#combine` may see fewer
  nodes, though every txid leaf's merkle proof is preserved.
- [sdk] **`MerklePath#combine`** also preserves `txid: true` flags when
  the incoming leaf is flagged and the existing leaf at the same offset
  isn't, so merging an ancestor's single-leaf proof into a compound
  that already contains the same offset as a sibling no longer loses
  the txid flag.
- [sdk] **`Transaction#to_beef`** now raises `ArgumentError` if an
  ancestor's merkle path doesn't actually contain that transaction's
  txid, or if the rebuilt BUMP's root doesn't match the source root.
  Previously such corrupt proof data would silently emit a broken BEEF.
  Callers relying on `to_beef` not raising on valid data are
  unaffected; the new exception only triggers on corrupt proof stores.

### Internal

- [sdk] **`Beef#merge_transaction`** indirectly benefits from the
  tighter `#combine` + `#trim` behaviour: compound BUMPs no longer
  accumulate dead sibling hashes across repeated merges.
- [sdk] On the real-world `#302` regression fixture, the cleaned BUMP
  shrinks from 2476 B to 1300 B (47% reduction) as a side effect of
  `#extract` removing intermediate siblings that are no longer needed
  once phantom leaves are gone.

## sdk-0.8.0 — 2026-04-08

### Added

- [sdk] **`MerklePath.from_tsc`** — convert WhatsOnChain TSC merkle proofs
  (the flat leaf-to-root sibling list returned by
  `/tx/{txid}/proof/tsc`) into BRC-74 BUMP format. Verified end-to-end
  against a real mainnet vector (block 612251). Closes #280.
- [sdk] **`Beef#version=`** writer — promoted from internal
  `instance_variable_set` to a proper accessor.

### Changed

- [sdk] **`Beef#to_binary` rewrite** — serialises BUMPs from the canonical
  `@bumps` array and uses `beef_tx.bump_index` as the on-wire reference,
  instead of walking each transaction's `merkle_path` via object identity.
  Fixes duplicate-BUMP serialisation for same-block ancestors that
  previously caused ARC `468 BEEF invalid` rejections. Matches the TS and
  Go reference SDKs. Closes #288.
- [sdk] **`Beef#to_hex`** preserves the bundle's `@version` so a BEEF
  parsed from V2 round-trips to V2 hex (and V1 to V1) instead of always
  silently downgrading to V1. The original docstring already claimed
  "V2 hex string" — this fix matches the original intent. Closes #292.
- [sdk] **`Beef#initialize`** default `version:` parameter changed from
  `BEEF_V2` to `BEEF_V1` to match `to_binary`'s default. Every existing
  `Beef.new + to_hex` caller continues to emit V1 (preserving every
  existing observable behaviour). Closes #292.
- [sdk] **`bsv-sdk` gem packaging** — explicit module list in
  `bsv-sdk.gemspec` excludes `bsv-attest` and `bsv-wallet` code. Reduces
  `bsv-sdk` from 144 files to 98 (24% smaller); no overlap with the
  sibling gems except `LICENSE`.
- [sdk] `Transaction#to_beef` docstring corrected from "BEEF V2 binary
  bundle" to "BEEF V1 binary bundle (BRC-62)" to match what the method
  actually emits.

### Fixed

- [sdk] **`Beef#to_binary`** raises `ArgumentError` upfront when V1
  (BRC-62) is requested for a bundle containing `FORMAT_TXID_ONLY`
  entries, instead of crashing deep inside `write_v1_tx` with
  `NoMethodError`. V2 (BRC-96) supports TXID-only and is unaffected. The
  error message points the caller at `version: BEEF_V2`. Closes #290.
- [sdk] **`Beef#merge`** raises `ArgumentError` on inconsistent
  `bump_index` from the source bundle (when the source has a transaction
  pointing at a `bump_index` that doesn't exist in the source's
  `@bumps`), instead of silently propagating a stale index that could
  attach the wrong merkle path to a transaction in the merged bundle.
  Closes #291.
- [sdk] **`Beef::BeefTx#initialize`** validates that
  `FORMAT_RAW_TX_AND_BUMP` requires a non-nil `bump_index`, failing fast
  in the constructor instead of crashing later in `VarInt.encode(nil)`.
- [sdk] **`Beef#merge_raw_tx`** bounds-checks the `bump_index` parameter
  and raises `ArgumentError` if out of range, instead of silently writing
  an invalid index that downstream parsers would misinterpret.

### Internal

- [sdk] CI is now green: 73 pre-existing RuboCop offenses across
  `spec/conformance/openssl_shim_compliance/` resolved. Closes #293.
- [sdk] OpenSSL EC shim conformance suite is now skipped on Ruby 2.7,
  where stock `OpenSSL::PKey::EC::Point#add` is unavailable. The shim
  itself still has direct unit-test coverage on every supported Ruby.

## wallet-0.3.3 — 2026-04-06

### Fixed

- [wallet] `finalize_action` now stores the spending transaction so subsequent
  `internalize_action` / proof resolution flows can find it. Previously the
  wallet remembered the inputs and outputs but not the finalised tx itself.

## wallet-0.3.2 — 2026-04-06

### Fixed

- [wallet] `internalize_action` now stores **all** transactions from the
  incoming BEEF, not just the proven ones. Unproven ancestors are needed for
  later BEEF reconstruction in `create_action` → `to_beef`.

## wallet-0.3.1 — 2026-04-06

### Fixed

- [wallet] `internalize_action` now stores the subject transaction hex (not
  just its proof and outputs), so the wallet can rebuild BEEF for spends of
  the inbound outputs without re-fetching the tx.

## sdk-0.7.0 / wallet-0.3.0 — 2026-04-06

### Added

- [wallet] **Pluggable proof store** for merkle proof persistence. The wallet
  is now a lightweight SPV node: `internalize_action` extracts and stores
  merkle proofs from incoming BEEF; `create_action` reattaches them to
  produce valid BEEF with BUMPs for ARC broadcast.
  - `ProofStore` interface with `store_proof` / `resolve_proof`.
  - `LocalProofStore` default implementation using `StorageAdapter`.
  - `WalletClient` accepts injectable `proof_store:` parameter.
  - Transaction caching (`store_transaction` / `find_transaction`) for
    ancestry reconstruction.
- [wallet] `StorageAdapter` gains `store_proof`, `find_proof`,
  `store_transaction`, `find_transaction` methods, implemented in both
  `MemoryStore` and `FileStore`.

### Changed

- [sdk] `Beef#to_binary` now defaults to BEEF V1 (BRC-62) format, matching
  the TS reference SDK's `Transaction#toBEEF()`. ARC's parser does not
  support V2. Pass `version: BEEF_V2` for BRC-96 format. Atomic BEEF (BRC-95)
  inner envelope remains V2 per spec.

### Fixed

- [wallet] `wire_source_from_storage` resolves merkle proofs via proof store
  so `to_beef` produces valid BEEF that ARC accepts. Previously, BEEF
  contained source transactions without proofs, causing ARC 463/468
  rejections.

## wallet-0.2.2 — 2026-04-06

### Fixed

- [wallet] `to_beef` now includes source transactions in the BEEF output, not
  just the subject transaction. Without ancestors, ARC could not validate the
  spend graph.

## sdk-0.6.2 / wallet-0.2.1 — 2026-04-06

### Added

- [wallet] `WalletClient#create_action` now accepts `UnlockingScriptTemplate`
  objects (e.g. `P2PKH`) as input unlocking scripts, enabling template-based
  signing without BEEF.
- [wallet] `wire_source_from_storage` fallback populates `source_satoshis`
  and `source_locking_script` from wallet storage when BEEF is absent or
  incomplete, enabling BIP-143 sighash computation for wallet-tracked
  outputs.
- [wallet] `finalize_action` resolves template inputs via `sign_all` before
  serialisation.
- [wallet] `MemoryStore#filter_outputs` supports outpoint filtering for
  efficient single-output lookups.

The sdk gem was re-released alongside this wallet change with no
behavioural changes of its own.

## sdk-0.6.1 — 2026-04-05

### Fixed

- [sdk] Use internal byte order for Atomic BEEF subject txid lookup, fixing
  serialisation of transactions loaded from Atomic BEEF format.

## sdk-0.6.0 — 2026-04-04

### Added

#### Primitives

- [sdk] **Pure Ruby secp256k1** — native Ruby implementation of secp256k1
  elliptic curve operations, ported from the TypeScript reference SDK.
  Replaces OpenSSL's EC point arithmetic with an OpenSSL compatibility shim
  — zero consumer code changes required. See
  [docs/about/secp256k1.md](docs/about/secp256k1.md).
  - Field arithmetic (modular multiplication, inversion, square root) over
    the secp256k1 prime.
  - Jacobian coordinate point operations (addition, doubling, scalar
    multiplication).
  - Windowed-NAF (w=5) scalar multiplication with precomputed table caching.
  - SEC 1 point serialisation (compressed and uncompressed).
  - 126 byte-for-byte compliance specs against real OpenSSL.
  - 24 process-isolated integration tests (separate Ruby processes, MD5
    file comparison).

#### Registry

- [sdk] **Registry client** — `BSV::Registry` module for on-chain definition
  management.
  - `Client` — register, resolve, list, revoke, and update definitions for
    protocols, baskets, and certificate types via PushDrop tokens on the
    overlay network.
  - Per-type overlay topics (`tm_basketmap`, `tm_protomap`, `tm_certmap`)
    and lookup services matching TS and Go SDKs.
  - Types: `BasketDefinitionData`, `ProtocolDefinitionData`,
    `CertificateDefinitionData`, `CertificateFieldDescriptor`,
    `RegisteredDefinition`.
  - Ownership verification before revocation. BEEF Array/String
    normalisation for wire format compatibility.

### Changed

- [sdk] OpenSSL usage reduced — OpenSSL now used only for hashing
  (SHA/RIPEMD), HMAC, PBKDF2, AES, and constant-time comparison. Elliptic
  curve operations are pure Ruby.

## sdk-0.5.0 — 2026-04-04

### Added

#### Overlay

- [sdk] **SHIP/SLAP overlay services** — `BSV::Overlay` module for
  topic-based transaction broadcasting and service discovery.
  - `TopicBroadcaster` (aliased as `SHIPBroadcaster`) — broadcasts tagged
    BEEF to topic-interested hosts with configurable acknowledgement modes
    (all/any/specific hosts) and STEAK response parsing.
  - `LookupResolver` — discovers competent hosts via SLAP trackers, queries
    in parallel, aggregates and deduplicates results. TTL-based host
    caching.
  - `HostReputationTracker` — EWMA latency scoring with exponential
    backoff, DNS error escalation, thread-safe. Optional persistence via
    injectable store adapter.
  - `AdminTokenTemplate` — decode/lock/unlock for SHIP/SLAP advertisement
    PushDrop tokens with BRC-42 wallet key derivation.
  - Abstract base classes (`LookupFacilitator`, `BroadcastFacilitator`)
    with default HTTPS implementations — all dependencies injectable via
    constructor.
  - SSRF protection for SLAP-discovered domains (private/loopback IP
    rejection).

#### Identity

- [sdk] **Identity client** — `BSV::Identity` module for certificate-based
  identity resolution and publication.
  - `Client` — resolve identities by key or attributes, publicly reveal
    certificate fields on-chain, revoke revelations. All overlay
    dependencies injectable.
  - `IdentityParser` — converts identity certificates to
    `DisplayableIdentity`, handling all 9 known types (xCert, discordCert,
    phoneCert, emailCert, identiCert, registrant, coolCert, anyone, self)
    plus generic field-name heuristic fallback.
  - Types: `DisplayableIdentity`, `IdentityCertificate`, `CertifierInfo`,
    `ClientOptions` with cross-SDK constant alignment.
  - Certificate verifier injectable with safe-by-default (raises
    `NotImplementedError`).

#### Script

- [sdk] **PushDropTemplate** — reusable wallet-aware PushDrop template with
  BRC-42 key derivation, optional ECDSA field signing, and P2PKH
  lock/unlock. Used by Identity client, reusable for ContactsManager and
  other PushDrop-based features.

### Fixed

- [sdk] `ProtoWallet` parameter name mismatch: `_originator:` →
  `originator:` to match the `WalletInterface` contract.

## sdk-0.4.0 / wallet-0.2.0 — 2026-04-01

### Added

#### Primitives

- [sdk] **Bitcore ECIES** — `ECIES.bitcore_encrypt` /
  `ECIES.bitcore_decrypt`. AES-256-CBC with random IV, SHA-512(X-coordinate)
  key derivation. Matches ts-sdk and go-sdk Bitcore variants.

#### Transaction

- [sdk] **`LivePolicy.default`** — one-line convenience for live fee queries
  via GorillaPool ARC with 5-minute cache and 100 sat/kB fallback. (The
  underlying `LivePolicy` fee model itself shipped in sdk-0.3.2.)

#### Wallet

- [wallet] **FileStore** — JSON file-backed persistent storage, now the
  default for `WalletClient`. Data survives process restarts. `MemoryStore`
  becomes explicit opt-in for tests.
- [wallet] **File permissions** — directory created with 0700, files with
  0600. Warns via Logger on startup if permissions are too open.

### Changed

- [sdk] **Default fee rate**: `SatoshisPerKilobyte` default changed from 50
  to 100 sat/kB (matches ts-sdk LivePolicy fallback).

## sdk-0.3.2 / wallet-0.1.2 — 2026-03-30

### Added

#### Script

- [sdk] **OP_CAT template** — OP_CAT concatenation script template with
  lock/unlock constructors.

#### Transaction

- [sdk] **LivePolicy fee model** — fetches policy from ARC `/v1/policy`
  endpoint. (The convenience constructor `LivePolicy.default` was added
  in sdk-0.4.0.)

#### Wallet

- [wallet] **BRC-31 Auth/Peer** — mutual authentication with nonce-based
  challenges, ECDSA signatures, and session management.
- [wallet] **BRC-100 wire protocol** — binary ABI serialisation for all 28
  BRC-100 methods (call codes 1-28, VarInt encoding).
- [wallet] **Certificate issuance** — `acquire_certificate` with
  `'issuance'` protocol (POST to certifier URL).

### Fixed

- [sdk] PUSHDATA1/2/4 bounds check (silent data corruption on truncated
  scripts).
- [sdk] Extended key path validation (reject non-numeric indices).
- [wallet] Subject and certifier pinned in certificate issuance response
  (not overridable by remote certifier).
- [wallet] Wire reader negative `privileged_reason` length crash.

This was the first formal `bsv-wallet` gem release tag. Wallet code that
landed in master before this date (notably the BRC-100 identity certificate
methods and the BRC-100 blockchain-data / authentication methods committed
during the sdk-0.3.1 window) is part of this gem's initial released state.

## sdk-0.3.1 — 2026-03-27

### Added

#### Network

- [sdk] **`ARC#broadcast` `wait_for:` parameter** — sets the `X-WaitFor`
  header (RECEIVED, STORED, ANNOUNCED_TO_NETWORK, SEEN_ON_NETWORK, MINED)
  so callers can choose how long ARC blocks before responding.

## sdk-0.3.0 — 2026-03-27

### Added

#### Primitives

- [sdk] **SymmetricKey** — AES-256-GCM encryption/decryption with 32-byte
  IV (cross-SDK compatible). Construct from random, ECDH, or raw bytes.
- [sdk] **BRC-77 SignedMessage** — authenticated message signing and
  verification using BRC-42 derived keys. Supports targeted (specific
  verifier) and "anyone" modes.
- [sdk] **BRC-78 EncryptedMessage** — end-to-end encrypted messaging using
  ECDH-derived symmetric keys.
- [sdk] **Schnorr ZKP (BRC-94)** — zero-knowledge proof of ECDH shared
  secret knowledge. `Schnorr.generate_proof` / `Schnorr.verify_proof`.
- [sdk] **Shamir's Secret Sharing** — split private keys into threshold
  shares (`PrivateKey#to_key_shares`) with Lagrange interpolation
  reconstruction. Backup format with integrity check.

#### Script

- [sdk] **PushDrop template** — data carrier with P2PK spending.
  `Script.pushdrop_lock` / `Script.pushdrop_unlock` with field extraction.
- [sdk] **RPuzzle template** — R-puzzle hash-based spending with 6 hash
  type variants (raw, SHA1, SHA256, RIPEMD160, HASH160, HASH256).

#### Transaction

- [sdk] **Benford's law change distribution** — privacy-preserving change
  output splitting using Benford's first-digit distribution.

### Fixed

- [sdk] Empty plaintext/ciphertext handling on older OpenSSL versions.
- [sdk] PushDrop detection for minimally-encoded fields.

### Changed

- [sdk] `Transaction#fee` change distribution uses Benford's law (was equal
  split).
- [sdk] `LineLength` raised to 150.

## sdk-0.2.1 — 2026-03-07

### Fixed

- [sdk] Truncated `OP_PUSHDATA1`/`2`/`4` scripts now raise `ArgumentError`
  instead of crashing with `TypeError`.
- [sdk] `Transaction#to_beef` uses `merge_bump` to correctly handle
  multiple ancestors at the same block height.
- [sdk] `PrivateKey#derive_child` uses `BN.mod_add` instead of Integer
  roundtrip for modular addition.
- [sdk] Fixed txid byte-order documentation (display order, not internal
  order).

### Testing

- [sdk] FORKID enforcement spec verifying interpreter rejects signatures
  without SIGHASH_FORKID.
- [sdk] ExtendedKey fingerprint chain integrity across 3-generation
  derivation.
- [sdk] Mnemonic entropy round-trip across all 5 valid entropy lengths.
- [sdk] BEEF spec for multiple ancestors at the same block height.

## sdk-0.2.0 — 2026-03-07

### Added

#### Primitives

- [sdk] ECDH shared secret derivation
  (`PrivateKey#derive_shared_secret`, `PublicKey#derive_shared_secret`).
- [sdk] BRC-42 key derivation (`PrivateKey#derive_child`,
  `PublicKey#derive_child`) with official spec test vectors.

#### Transaction

- [sdk] Chain tracker interface (`ChainTracker` base class) with
  WhatsOnChain implementation.
- [sdk] Fee model interface (`FeeModel` base class) with
  `SatoshisPerKilobyte` implementation.
- [sdk] `Transaction#fee` with change output distribution across multiple
  change outputs.
- [sdk] `Transaction#verify` for full SPV verification (merkle path,
  script execution, recursive ancestry).
- [sdk] `TransactionOutput#change` flag for identifying change outputs.
- [sdk] `MerklePath#verify` for SPV chain tracker integration.
- [sdk] BEEF completion: `Beef#merge`, `Beef#valid?`, lookup methods
  (`find_bump`, `find_transaction_for_signing`).
- [sdk] `Transaction#to_beef` / `Transaction.from_beef` convenience
  methods.
- [sdk] Extended Format (EF) transaction serialisation (`to_ef`,
  `to_ef_hex`, `from_ef`, `from_ef_hex`).
- [sdk] `VerificationError` with typed error codes for SPV verification
  failures.

### Changed

- [sdk] ECIES refactored to use `PrivateKey#derive_shared_secret`
  internally (no API change).
- [sdk] `Transaction#estimated_size` made public for fee model access.

### Fixed

- [sdk] Nil `source_satoshis` now raises instead of silently coercing to
  zero in fee distribution and verification.
- [sdk] Script chunk round-trips preserve original push encoding.
- [sdk] `OP_RETURN` inside conditionals correctly checked for conditional
  balance.
- [sdk] Point x-coordinate extraction preserves leading zeros via octet
  string.
- [sdk] `Integer#nobits?` replaced with Ruby 2.7-compatible bitwise check.
- [sdk] Defensive parsing with descriptive errors for truncated binary
  input.

### Testing

- [sdk] BRC-42 conformance specs with 9 official specification test
  vectors.
- [sdk] ECDH conformance specs (commutativity, cross-method, pinned
  known-key vector).
- [sdk] SPV verification conformance specs (merkle path, script execution,
  ancestry).
- [sdk] Fee model conformance specs (formula validation, default rate,
  change distribution).
- [sdk] Chain tracker conformance specs.
- [sdk] BEEF cross-SDK conformance vectors.
- [sdk] Schnorr (BRC-94) cross-SDK interoperability vectors.
- [sdk] 6 exact-match RFC 6979 vectors from Trezor/CoreBitcoin.
- [sdk] VarInt boundary tests at size-prefix transitions.
- [sdk] Script vectors converted to tracked known-failures system.

## sdk-0.1.0 — 2026-02-14

Initial release of the BSV Ruby SDK.

### Added

#### Primitives

- [sdk] secp256k1 elliptic curve operations (point arithmetic, scalar
  multiplication).
- [sdk] ECDSA signing and verification with RFC 6979 deterministic nonces.
- [sdk] Public and private key handling (WIF import/export,
  compressed/uncompressed formats).
- [sdk] Base58Check encoding and decoding.
- [sdk] Hash functions: SHA-256, RIPEMD-160, Hash160 (SHA-256 +
  RIPEMD-160), SHA-512, HMAC.
- [sdk] BIP-32 hierarchical deterministic key derivation (extended keys,
  hardened/normal child paths).
- [sdk] BIP-39 mnemonic phrase generation and seed derivation.
- [sdk] ECIES encryption and decryption (BIE1 format).
- [sdk] Bitcoin Signed Message (BSM) signing and verification.

#### Script

- [sdk] Opcode constants (full set).
- [sdk] Script chunk representation and parsing.
- [sdk] Script serialisation and deserialisation.
- [sdk] Script templates: P2PKH, P2PK, P2MS (multisig), OP_RETURN data.
- [sdk] Script type detection (including read-only recognition of P2SH and
  other legacy types).
- [sdk] Script builder API for programmatic construction.
- [sdk] Script interpreter with stack operations, arithmetic, crypto, flow
  control, splice, and bitwise ops.

#### Transaction

- [sdk] Transaction construction and serialisation (raw format).
- [sdk] BIP-143 sighash computation (all hash types with FORKID).
- [sdk] Transaction signing with configurable sighash flags.
- [sdk] BEEF serialisation (BRC-95/BRC-96).
- [sdk] Merkle path representation and verification.
- [sdk] Fee estimation.
- [sdk] Script verification during signing.
- [sdk] Unlocking script templates for common script types.

#### Network

- [sdk] ARC broadcaster for transaction submission.
- [sdk] WhatsOnChain chain data provider.
- [sdk] Basic wallet functionality.

#### Testing

- [sdk] Cross-SDK test vectors from Go, TypeScript, and Python reference
  implementations.
- [sdk] NIST and RFC hash function test vectors.
- [sdk] Bitcoin Core script interpreter test suite.
- [sdk] Protocol conformance specs for opcodes, sighash flags, and
  transaction templates.
