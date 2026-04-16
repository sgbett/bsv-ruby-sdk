# Changelog — bsv-wallet

All notable changes to the `bsv-wallet` gem are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.9.0 — 2026-04-16

### Changed — **Breaking**

#### Action status taxonomy aligned with BRC-100 reference SDK (HLR #455)

This release realigns the action status values with the wallet-toolbox reference
implementation. The meaning of `'completed'` has changed — **consumers must
update any code that checks for `'completed'` as the post-broadcast success
state**.

| Status | Old meaning | New meaning |
|--------|-------------|-------------|
| `'nosend'` | No change | Transaction built but not broadcast (`no_send: true`) |
| `'sending'` | No change | Async queue accepted; worker has not yet attempted broadcast |
| `'unproven'` | *(new)* | Broadcast succeeded; awaiting merkle proof |
| `'completed'` | Broadcast succeeded | **Merkle proof received and stored** |
| `'failed'` | No change | Broadcast rejected or transaction invalid |

**Migration:**

- Code querying `list_actions(status: 'completed')` will return fewer results
  until a proof-watcher is implemented (out of scope for this release). To find
  successfully-broadcast actions that have not yet received a proof, query
  `status: 'unproven'` instead.
- `create_action` and `sign_action` now raise `BSV::Wallet::WalletError` when
  no broadcaster is configured and `options: { no_send: true }` is not set.
  Previously these calls succeeded silently. To resolve: pass
  `broadcaster: BSV::Network::ARC.default` to `WalletClient.new`, or pass
  `options: { no_send: true }` to `create_action` to build without
  broadcasting.
- `internalize_action` now sets status to `'completed'` only when the supplied
  BEEF contains a merkle proof for the subject transaction. Plain BEEF (raw
  transaction, no BUMP) results in status `'unproven'`.
- Wallets configured with a `SolidQueueAdapter` satisfy the broadcaster
  requirement if the adapter carries an embedded `broadcaster:` — the
  `WalletClient` itself does not need one.

**Related upstream incidents:** x402-rack #148, x402-rack #158, x402-doom #196.
**Tracking issue:** #455.

## 0.8.0 — 2026-04-15

### Added
- BRC-100 substrates: `HTTPWalletJSON` for JSON-over-HTTP, `HTTPWalletWire`
  for binary transport, and `WalletWireTransceiver` Interface adapter (#449–#451)
- `WalletClient` accepts `substrate:` constructor param for remote wallet
  delegation — all Interface methods delegate to the substrate when set (#452)
- `list_actions` and `list_outputs` honour `include_labels`, `include_inputs`,
  and `include_outputs` flags (#448)
- `acquire_certificate` uses `AuthFetch` for BRC-104 authenticated certificate
  issuance (#453)

### Fixed
- `prove_certificate` now uses correct protocol ID (`'certificate field encryption'`)
  and key ID format (`"#{serial_number} #{field_name}"`) matching TS/Go SDKs —
  previously incompatible cross-SDK (#424)
- Code review findings addressed for substrates and include flags

### Changed
- `BSV::WalletInterface` module removed — `VERSION` now lives in `BSV::Wallet::VERSION`
  where all other wallet constants already reside

## 0.7.0 — 2026-04-12

### Added
- Pluggable `BroadcastQueue` interface module — duck-typed, follows the `StorageAdapter` pattern
- `InlineQueue` synchronous default adapter — consolidates broadcast and no-broadcaster paths
- `WalletClient` accepts `broadcast_queue:` constructor parameter (auto-creates `InlineQueue` when not provided)
- `BroadcastQueue.status_for_error` shared helper for consistent broadcast error mapping
- Integration specs for broadcast/rollback flows (20 specs)
- MemoryStore production warning — logs to stderr when `RACK_ENV`/`RAILS_ENV` is `production` or `staging`

### Fixed
- TOCTOU window on change outputs — stored as `:pending` directly, eliminating race with concurrent `auto_fund`
- Broadcast promotion failure no longer deletes confirmed on-chain outputs — only broadcast failure triggers rollback

### Changed
- `accept_delayed_broadcast: true` no longer logs "not yet implemented" warning — handled by the queue adapter
- MemoryStore demoted to test/development only (production use triggers a suppressible warning)

## 0.6.0 — 2026-04-12

### Added
- Broadcast-before-promote semantics for `create_action` — transactions are
  broadcast via a configurable `broadcaster:` before promoting state, with
  automatic rollback on failure to prevent phantom UTXOs (#369, #371)
- `send_with` for batched broadcast of previously `no_send` transactions,
  with per-transaction rollback on failure (#373)
- `accept_delayed_broadcast` option accepted as a stub (defaults to `false`;
  background broadcasting deferred to a follow-up) (#374)
- `delete_action` and `update_action_status` on `StorageAdapter`, implemented
  in MemoryStore, FileStore, and PostgresStore (#370)
- Broadcast results mapped to `ReviewActionResultStatus` (`success`,
  `doubleSpend`, `invalidTx`, `serviceError`) and returned in the result
  hash (#372)

### Fixed
- EF version marker overhead corrected from 2 to 6 bytes in fee estimation
- Fee estimation now includes EF overhead for ARC compatibility
- `FeeEstimator` default raised from 1 sat/kB to 100 sat/kB
- `internalize_payment` now stores outputs in the default basket
- `derivation_type` comparison uses string comparison for JSON round-trip
  safety (#367)

### Changed
- Extracted `DEFAULT_SATS_PER_KB` constant for fee estimation
- Specs reorganised into per-gem directories (#363)

## 0.5.1 — 2026-04-11

### Fixed

- **Auto-fund coin selection and change use default basket** (#344):
  coin selection and change generation now correctly target the `default`
  basket, matching TS SDK behaviour. Previously, auto-funded transactions
  could select UTXOs from or generate change into the wrong basket.
- **Normalise protocol name in KeyDeriver** (#262, #263): `compute_invoice_number`
  now applies `.downcase.strip` to the protocol name before building the
  invoice string, matching TS and Go SDK behaviour. Mixed-case or
  whitespace-padded protocol names previously derived different keys.

### Changed

- **SDK dependency floor raised** to `bsv-sdk >= 0.10.0` (from 0.9.0)
  to pick up the KeyDeriver normalisation fix in the SDK layer.

---

## 0.5.0 — 2026-04-11

Native UTXO management, coin selection, and automatic change handling.
The wallet can now fund transactions end-to-end without an external
wallet server — `create_action` with outputs but no inputs triggers
automatic UTXO selection, fee estimation, and change generation.

### Added

- **UTXO management pipeline** (#264, #265–#272): complete transaction-
  funding pipeline with `CoinSelector` (exact-match, smallest-sufficient,
  largest-first strategies), `ChangeGenerator` (BRC-29 multi-output change
  with dust consolidation, randomised splits, pool-health-aware output
  caps), and `FeeEstimator` (size-based sats/kB with ceil rounding).
- **`WhatsOnChainProvider`**: chain UTXO discovery via the WhatsOnChain API,
  implementing `sync_utxos` for on-chain balance loading.
- **StorageAdapter extensions**: 6 new interface methods —
  `update_output_state`, `lock_utxos`, `find_spendable_outputs`,
  `release_stale_pending!`, `store_setting`, `find_setting`. All default
  to `NotImplementedError`; `MemoryStore` and `FileStore` implement them.
- **Atomic UTXO locking**: `lock_utxos` checks and marks outputs as
  `:pending` within a single mutex hold, closing the TOCTOU race where two
  threads could select the same UTXO.
- **Pending state management**: outputs transition through `:spendable` →
  `:pending` → `:spent`, with timestamps and caller references for stale
  lock recovery.
- **Auto-funding in `create_action`**: when given outputs without inputs,
  the wallet selects UTXOs, estimates fees, generates change outputs, and
  locks inputs automatically.
- **`set_wallet_change_params`**: configures target UTXO count and value
  for the change pool.

### Fixed

- **Identity UTXO filter alignment**: `sync_utxos` stores
  `derivation_type: :identity` but auto-fund filtered on a field that was
  never set. Fixed the filter and added a signing branch that uses
  `root_key` directly for identity UTXOs.
- **`tx_pos` bounds validation in `sync_utxos`**: untrusted WhatsOnChain
  API responses with negative or out-of-bounds `tx_pos` could exploit
  Ruby's negative array indexing or raise `NoMethodError` on nil. Now
  validates before use.
- **Stale pending recovery rate-limited**: `release_stale_pending!` now
  skips if invoked within 30 seconds, preventing O(n) output scans on
  every `create_action` call.
- **`no_send` change outputs stored as `:pending`**, matching the TS SDK
  where `noSend` outputs have `spendable: false`. Prevents them from
  being auto-selected by concurrent `create_action` calls.
- **`abort_action` cleans up change outputs** created by the aborted
  transaction, matching TS SDK behaviour.
- **Nil state guard**: `effective_state` handles `state: nil` (from NULL
  DB column) without raising `NoMethodError`.
- **`change_params` wiring**: stored change params and pool size are now
  wired into `converge_change` so `set_wallet_change_params` actually
  affects auto-fund output count.

### Changed

- **`FeeModel` consolidated into `FeeEstimator`**: `FeeModel` is now a
  backward-compatible alias for `FeeEstimator`, which is the canonical
  implementation with dust floor, varint handling, and extra-bytes
  support.
- **`BRC29_PROTOCOL_ID` constant** replaces hardcoded protocol ID in
  `internalize_payment`.

## 0.4.0 — 2026-04-10

### Added

- **Protocol-ID normalisation** (F8.7): `Validators.validate_protocol_id!` now
  strips and downcases the name before applying rules, so `' MyProtocol '` and
  `'myprotocol'` are treated identically and cannot silently fork to different
  key-derivation paths.
- **Permission-rule constants** (F8.8): Reserved prefix/suffix strings are now
  named constants on `BSV::Wallet::Validators` (`RESERVED_PROTOCOL_PREFIXES`,
  `RESERVED_PROTOCOL_SUFFIX`, `RESERVED_BASKET_PREFIXES`, `RESERVED_BASKET_SUFFIX`,
  `RESERVED_BASKET_NAME`), making them discoverable and documentable.
- **BEEF verification in `internalize_action`** (F8.14): The BEEF bundle is now
  verified via `Beef#verify` before any outputs are stored. If the bundle is
  structurally invalid, a `WalletError` is raised rather than storing unverified
  data. When the chain provider supports `valid_root_for_height?`, full SPV
  verification is performed.
- **Depth cap and cycle detection in `wire_source_tx_ancestors`** (F8.18):
  Recursion is now bounded by `WalletClient::ANCESTOR_DEPTH_CAP` (64 levels)
  and a visited-txid `Set`, preventing stack overflow on deep or cyclic
  transaction ancestry chains.

### Changed

- **`ProtoWallet#create_signature` default counterparty** (P305.1): The default
  value for `counterparty` has changed from `'self'` to `'anyone'`, matching the
  behaviour of `ts-sdk`'s `ProtoWallet.createSignature`. Callers that rely on
  the `'self'` derivation path when omitting `counterparty:` must now pass
  `counterparty: 'self'` explicitly.

### Migration notes

**P305.1 — `create_signature` counterparty default change (breaking)**

Previously, calling `wallet.create_signature({ protocol_id: ..., key_id: ...,
data: ... })` without a `counterparty:` key would derive using `'self'`. It now
derives using `'anyone'`. This changes the resulting private key and therefore
the signature. If your application omits `counterparty:`, add
`counterparty: 'self'` to preserve the old behaviour.

**F8.14 — BEEF verification now mandatory in `internalize_action`**

Calls to `internalize_action` that previously succeeded with a malformed or
unverifiable BEEF will now raise `BSV::Wallet::WalletError`. In practice this
only affects callers passing synthetic or hand-crafted BEEF bytes; legitimate
BEEF produced by `create_action` or broadcast round-trips will continue to work.

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
