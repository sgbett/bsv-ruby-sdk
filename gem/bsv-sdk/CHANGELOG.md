# Changelog — bsv-sdk

All notable changes to the `bsv-sdk` gem are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.26.0 — 2026-07-08

### Breaking Changes
- `Transaction::Tx#verify` — the `verified:` kwarg now accepts `nil | Hash{String => Boolean}`
  (previously `nil | Set<String>`). The Hash is mutated in place, so a caller can both pre-seed
  the already-verified wtxid set and read back the wtxids walked during verification. A frozen
  Hash, or a Hash with a truthy `default`/`default_proc`, is rejected at entry (funds risk) (#904).

### Added
- `Transaction::Tx#verify(verified:)` bidirectional verification cache: pre-seeding short-circuits
  already-verified ancestor subtrees; post-read exposes the walked wtxid set for a persistent
  verification cache (#904, #909, #910).
- Transaction memoisation: per-struct binary, component-hash, and wire-order memos across `Tx`,
  inputs, and outputs, invalidated on mutation — repeated `to_binary`/`wtxid`/hash computation is
  now cached (#881).
- Conformance canonical corpus: a pinned-revision loader plus fetch/sync tooling and cache layout,
  with the BEEF, BUMP, sighash, SHA-256, ECIES, BRC-42 key-derivation, and script-test specs
  migrated onto it (#840, #841, #842–#847).

### Fixed
- Interpreter consensus hardening: correct Chronicle gating of `OP_VER`/`OP_VERIF` (with
  tx_version), `OP_2MUL`/`OP_2DIV`, and multi-`OP_ELSE` (relaxed mode); enforce the `CLEANSTACK`
  and `SIGPUSHONLY` verification flags; whitelist verification flags (#837, #850, #851, #852, #853,
  #854).
- `Transaction::Tx#verify` — translate the fee-gate `ArgumentError` (missing source data) into a
  `VerificationError` (`:missing_source`) so every failure mode raises a consistent error type
  (#904).
- `Transaction::Tx#verify` — fix a funds-risk bug where a Hash with a truthy default could silently
  short-circuit verification for unseen wtxids (#904).

### Changed
- Performance: reuse OpenSSL digest contexts in primitives hashing (thread-safety documented); split
  `clear_caches` from `invalidate_caches` in the transaction cache lifecycle (#881, #882).

## 0.25.0 — 2026-06-18

### Added
- `BSV::Storage::Utils` — UHRP URL helpers (`normalise_url`, `url_for_hash`,
  `url_for_file`, `hash_from_url`, `valid_url?`) (#817).
- `BSV::Overlay::Historian` — generic output-history walker over `LookupResolver`,
  enabling protocol-specific replay of an outpoint's lineage (#818).
- `BSV::Registry` — typed `resolve_basket`, `resolve_protocol`, and
  `resolve_certificate` methods on the registry client (#819).
- `BSV::KVStore::Interpreter` — `Historian`-compatible interpreter for KV
  protocol outputs (#820).
- `BSV::Storage::Downloader` — UHRP resolver and content fetcher with
  hash verification (#821).
- `BSV::KVStore::Global` — overlay-backed read-only key-value reader (#822).
- `BSV::Script::BIP276` — text encoding for scripts and templates (`encode`,
  `decode`) (#830).
- `BSV::Transaction::BeefParty` — `Beef` subclass tracking per-party knowledge
  of transactions for multi-party BEEF exchange, plus supporting methods on
  `Beef` (#831).

### Changed
- `Beef` wire-inputs debug log now uses the existing `TransactionInput#dtxid_hex`
  and `Tx#dtxid` accessors instead of inlined byte-order conversions (#828).

### Fixed
- ECIES bitcore variant — added `iv:` kwarg and TypeScript SDK conformance
  vector (#829).

## 0.24.0 — 2026-06-11

### Breaking Changes
- **`BSV::Transaction::Transaction` renamed to `BSV::Transaction::Tx`** (#795). Class only;
  module `BSV::Transaction` and peer classes (`TransactionInput`, `TransactionOutput`,
  `ChainTracker`, `Beef`, etc.) unchanged. No compat alias — pre-1.0 clean break.
  Downstream consumers update with `s/BSV::Transaction::Transaction/BSV::Transaction::Tx/g`.
- **`BSV::Wallet::WalletWireTransceiver` pubkey results are now 66-char hex** (#798),
  matching the BRC-100 `PubKeyHex` contract and `ProtoWallet`'s direct-call shape.
  Affects `get_public_key`, `reveal_counterparty_key_linkage`, `reveal_specific_key_linkage`.
  Wire bytes remain 33-byte compressed binary; only the deserialised Ruby return shape
  changed. See ADR-001 for the rationale.
- **`BSV::Identity::Client` and `BSV::Registry::Client` raise `BSV::Overlay::OverlayError`
  subclasses on overlay broadcast failure** (#802) — `publicly_reveal_attributes`,
  `revoke_certificate_revelation`, `register_definition`, `sign_and_broadcast` previously
  returned a result hash and required callers to inspect `status` themselves.

### Added
- `BSV::Wallet::ProtoWallet::KeyDeriver#identity_key_bytes` — binary accessor for the
  identity pubkey, alongside the hex `identity_key`. Mirrors the planned bsv-wallet
  KeyDeriver shape.
- `BSV::Overlay::OverlayBroadcastResult#success?` and `#raise_if_error!` — let callers
  treat broadcast failure as an exception with the appropriate `OverlayError` subclass.
- ADR-001 documenting the SDK's binary-internal rule and the public-key hex exception
  (`docs/guides/wtxid-dtxid.md` extension + `.architecture/decisions/adrs/ADR-001-…`).

### Fixed
- `BSV::Network::Util.resolve_tx_hex` rejects empty input rather than silently producing
  an empty `rawTx` broadcast (#799).
- `BSV::Network::Protocol#default_call` converts transport-level exceptions
  (`SocketError`, `Errno::ECONNREFUSED`, `Net::OpenTimeout`, `OpenSSL::SSL::SSLError`,
  etc.) into structured `ProtocolResponse` with `http_success: false` and descriptive
  `error_message`, rather than propagating raw exceptions to callers (#807).
- `BSV::Auth::AuthPayload.serialize_request` raises `ArgumentError` for `request_nonce`
  that isn't exactly 32 bytes, preventing malformed BRC-103 wire frames (#800).
- `BSV::MCP::Tools::BroadcastP2pkh` rescues `StandardError` rather than just
  `ArgumentError`, so non-`ArgumentError` exceptions from invalid WIF input (e.g.
  `NoMethodError` on `nil`) return a structured MCP error instead of crashing the tool
  handler (#801).
- `BSV::Wallet::ProtoWallet#create_signature` / `#verify_signature` and matching wire
  serialisers validate that `hash_to_directly_sign` / `hash_to_directly_verify` are
  exactly 32 bytes, preventing malformed signatures (#805).
- `BSV::Attest.verify` asserts that the provider's `fetch_transaction` returns a Tx-like
  object before iterating, producing a clear `ArgumentError` instead of a low-signal
  `NoMethodError` (#803).

### Changed
- Bitcoin Core script-vectors spec now enforces a bidirectional regression gate:
  previously-failing vectors that now pass surface as failures so `known_failures.json`
  stays honest. Cleaned out 101 stale entries (#806).

## 0.23.1 — 2026-06-06

### Fixed
- `Protocols::Arcade#parse_broadcast_response`, `Protocols::ARC#parse_single_broadcast_response`,
  and `Protocols::ARC#parse_batch_broadcast_response` now preserve the parsed response body as
  `data:` on non-2xx responses. Previously the body was parsed only to extract an `error_message`,
  then discarded — leaving callers with `data: nil` and no way to read `txStatus` / `extraInfo`
  from synchronous broadcast failures (the terminal-rejection shape). Additive change; the 2xx
  success path and ARC's existing 2xx-REJECTED branch are unchanged. (#793)

## 0.23.0 — 2026-06-03

### Changed (breaking)
- **Canonical block-header response shape across protocols.** `Protocols::JungleBus`,
  `Protocols::Chaintracks`, and `Protocols::WoCREST` now emit the merkle root as
  `'merkle_root'` (lowercase snake_case) in their `:get_block_header` and
  `:get_block_headers` responses, replacing the upstream-specific names
  (`'merkleroot'` for JungleBus/WoCREST, `'merkleRoot'` for Chaintracks). Consumers
  reading the raw field directly from `provider.call(:get_block_header).data` must
  migrate to the canonical key. Wire protocols stay honest about other fields;
  only the merkle-root key is renamed. No shim. (#791)
- `WoCREST#:valid_root` now reads the normalised `merkle_root` key internally
  (no behaviour change — same comparison output).
- `BSV::Transaction::ChainTracker#valid_root_for_height?` reads
  `result.data['merkle_root']` directly; the previous private
  `normalise_merkle_root` helper is removed. Subclass-override pattern unchanged.

### Note
- This is the "Pattern A" normalisation from #791 — push cosmetic field-name
  divergence down into the wire-protocol classes where the data is semantically
  identical across upstreams. Pattern B (broadcast / get_tx_status with
  structurally divergent shapes) stays at the consumer layer and is not part of
  this release.

## 0.22.0 — 2026-05-30

### Added
- BRC-103 wire layer: `WalletWire` transport abstraction, `WalletWireTransceiver` (client), `WalletWireProcessor` (server), `Substrates::HTTPWalletWire` (binary HTTP transport), and `Substrates::HTTPWalletJSON` (JSON-over-HTTP, MetaNet Desktop compatible)
- Full BRC-103 serialisers for all 28 BRC-100 methods; wire format compatible with go-sdk byte-for-byte
- `BSV::Wallet.error_from_wire` helper rehydrates error frames into typed `BSV::Wallet::Error` subclasses (codes 1–7)
- New guide: `docs/guides/brc-103-wire.md` — end-to-end walkthrough of the wire layer
- Wire layer reference section added to `docs/sdk/wallet.md`
- `BSV::Transaction::ChainTracker.default(testnet: false)` — provider-routed chain tracker backed by GorillaPool + JungleBus by default; no credentials required (closes #783)
- `BSV::Network::Protocols::JungleBus` declares `:current_height` so the GorillaPool provider can satisfy chain-tip queries (#784)
- `BSV::Network::Providers::GorillaPool.testnet` now registers `Protocols::JungleBus` alongside `Protocols::Arcade` so chain-header lookups work on testnet

### Changed
- `BSV::Transaction::ChainTracker` is now a working default implementation when constructed with a `Provider`; subclasses that override `valid_root_for_height?` and `current_height` continue to work unchanged (constructor now accepts an optional positional `provider` argument: `ChainTracker.new(provider)`, with `provider = nil` preserved for subclass-only use)

### Removed (breaking)
- **`BSV::Transaction::ChainTrackers::Chaintracks`** is removed. Migrate to
  `BSV::Transaction::ChainTracker.default` for general use (GorillaPool), or construct
  a single-protocol Provider explicitly for own-server use:

  ```ruby
  own = BSV::Network::Provider.new('local') do |p|
    p.protocol BSV::Network::Protocols::Chaintracks, base_url: 'http://my-server'
  end
  tracker = BSV::Transaction::ChainTracker.new(own)
  ```

- **`BSV::Transaction::ChainTrackers.default`** (the namespace-level factory method) is
  removed. Use `BSV::Transaction::ChainTracker.default` (the singular class-level
  method) instead. The `ChainTrackers` namespace is now a pure autoload container for
  concrete protocol-specific wrappers; `ChainTracker` (singular) is the porcelain entry
  point.

- Closes #778 — GorillaPool chaintracks connectivity: chain data is now reachable
  through the provider via JungleBus; the open question dissolves.

### Note
- The default `ChainTracker` in the Ruby SDK resolves against GorillaPool/JungleBus,
  which diverges from the TS SDK (WhatsOnChain) and Go/Python SDK defaults. This
  reflects the broader pattern of GorillaPool being the default broadcast provider in
  the Ruby SDK.

## 0.21.0 — 2026-05-29 (not separately released — see 0.22.0)

### Added
- `Protocols::Arcade` for `bsv-blockchain/arcade` services (run by GorillaPool at
  `arcade.gorillapool.io`). Commands: `broadcast` (`POST /tx`), `get_tx_status`
  (`GET /tx/{txid}`), `health` (`GET /health`). Distinct from `Protocols::ARC` —
  paths, response bodies, and status taxonomies do not overlap. (#775)
- Shared `BSV::Network::Util` helpers: `safe_parse_json`, `resolve_tx_hex` —
  available to all protocol classes without copy-paste. (#775)

### Changed
- `ARC#call_broadcast` and `ARC#call_broadcast_many` now read their broadcast and
  batch-broadcast paths from the endpoint table rather than hardcoding `/v1/tx` and
  `/v1/txs`. Behaviour is unchanged; subclasses can now declare a different path. (#775)
- `LivePolicy.default` now points at `https://arc.taal.com` for fee-policy queries
  rather than GorillaPool's Arcade endpoint, which does not expose `/v1/policy`. (#775)
- `broadcast_p2pkh` MCP tool updated to handle Arcade's `{"status": "submitted"}`
  response shape from GorillaPool. (#775)

### Breaking Changes
- **`Providers::GorillaPool` no longer registers `Protocols::ARC` or
  `Protocols::Chaintracks`.** Mainnet now registers `Protocols::Arcade` instead.
  Consumers calling `provider.call(:broadcast, ...)` against GorillaPool and
  expecting an ARC-shaped response (`{txid, txStatus, ...}`) must migrate to
  Arcade's response shape (`{status: "submitted"}`). No compatibility shim is
  provided — pre-1.0 clean break. (#775)
- **`BSV_TESTNET_ARC_URL` environment variable renamed to `BSV_TESTNET_ARCADE_URL`.**
  Update any scripts or CI configuration that set this variable. Default value:
  `https://testnet.arcade.gorillapool.io`. (#775, #779)
- **`Providers::GorillaPool` no longer provides `:current_height` or
  `:get_block_header` commands** (previously routed through the broken
  `Protocols::Chaintracks` registration). A follow-up issue (#778) tracks correctly
  wiring GorillaPool's chaintracks_server at its actual separate URL/port.

### Removed
- `Protocols::Chaintracks` registration from `Providers::GorillaPool` (mainnet and
  testnet). The registration was broken — GorillaPool's chaintracks_server runs as
  a separate service on a separate port; the `/chaintracks/v2/` paths were returning
  404. See #778 for the follow-up to wire it correctly.

## 0.20.0 — 2026-05-24

### Changed
- Raise minimum Ruby version from 2.7 to 3.3; add Ruby 4.0 to CI matrix
- Remove Ruby 2.7 compatibility workarounds (Point#add fallback, OpenSSL.fixed_length_secure_compare fallback)
- Apply RuboCop modernisations unlocked by Ruby 3.3 target (anonymous forwarding, redundant `require 'set'`, `Hash#except`)

## 0.19.1 — 2026-05-13

### Fixed
- `Stack#length` missing — raised `NoMethodError` in interpreter debug logging when `BSV.logger` level was DEBUG (#752)

### Changed
- `Stack#length` and `Stack#size` aliased to `Stack#depth` rather than re-implementing

## 0.19.0 — 2026-05-11

### Breaking Changes
- `Result::Success/Error/NotFound` replaced by single `ProtocolResponse` class composing `Net::HTTPResponse`
- Predicates renamed: `success?` → `http_success?`, `not_found?` → `http_not_found?`, `error?` removed (use `!http_success?`)
- Constructor keyword `ok:` → `http_success:`
- ARC `arc_data_from` key remapping removed — `.data` returns raw API JSON with string keys (`'txid'` not `:txid`)
- Batch broadcast `.data` returns raw JSON array (no per-item `Result` wrapping)
- `BroadcastError`, `BroadcastResponse`, `ChainProviderError`, deprecated `BSV::Network::ARC` and `BSV::Network::WhatsOnChain` facades removed

### Added
- `ProtocolResponse` class with progressive enhancement: `.body`/`.code` (raw HTTP) → `.data` (parsed) → `.canonical` (placeholder)
- `ProtocolResponse#with(**overrides)` for escape hatch post-processing
- `fake_http_response` shared test helper for building real `Net::HTTPResponse` subclass instances
- Debug logging in Protocol (`call`, `default_call`, `build_response`) and `ProtocolResponse#with`

### Changed
- `Protocol#map_response` renamed to `build_response`
- Chain trackers raise `RuntimeError` instead of deleted `ChainProviderError`
- `ChainTracker` doc rewritten to explain the declarative/imperative split
- MCP tools updated: `.metadata[:status_code]` → `.code`, symbol keys → string keys

### Fixed
- `http_success?` returns `false` (not `nil`) when `http_response` is nil
- `Ordinals#call_get_spend` rescues `TypeError` alongside `JSON::ParserError`
- ARC malformed-2xx error messages include diagnostic detail
- WoC `call_is_utxo` clears stale `error_message` when overriding 404 to success

## 0.18.1 — 2026-05-09

### Added
- ARC broadcast accepts hex and binary strings directly, in addition to transaction objects

### Fixed
- Hex string detection uses content inspection rather than string encoding
- Stale "Phase B" text removed from Protocols namespace module doc

## 0.18.0 — 2026-05-09

### Breaking Changes
- Eliminated display-order binary txid from public API — all methods now use `wtxid` (wire-order) internally (#690)

### Added
- Provider auth and rate limit metadata: `auth:`, `rate_limit:`, `authenticated?` on Provider; generic auth dispatch in Protocol `build_request` (#718)
- JungleBus protocol: transaction lookup, address queries, block headers via GorillaPool JungleBus REST API (#717)
- Ordinals protocol: fixed endpoint paths, added tx details, tx status, UTXOs, balance, spends, chain tip (#727)
- Full WoC API coverage: expanded from 30 to 54 endpoints with complete address, script, UTXO, and analytics support (#715)
- Integration tests for ARC, JungleBus, Ordinals, and WoCREST against live APIs (#726)
- API documentation URLs in all protocol file headers (#730)

### Fixed
- Ordinals `get_tx` path corrected (`/hex` → `/raw`) and response handler fixed (binary, not JSON) (#727)
- Auth normalisation: `{ bearer: nil }` and `{ api_key: nil }` treated as unauthenticated (#725)
- WoC health endpoint path corrected (`/health` → `/woc`)
- Bulk POST body formats and `get_utxos_all` path corrected for WoC
- Lazy removal of expired sessions during identity-key lookup (#707)
- Session TTL expiration added to SessionManager (#707)
- Guard against nil source data and out-of-bounds input_index in sighash (#702)
- Wire format deep conversion depth limit (#709)

### Changed
- BeefTx refactored to polymorphic subclass hierarchy with validated constructors (#692-698)
- WoCREST `build_request` override removed — replaced by generic auth dispatch
- MCP dependency bumped from ~> 0.12 to ~> 0.15 (#700)

## 0.17.0 — 2026-05-02

### Breaking Changes
- Renamed `TransactionInput#prev_tx_id` to `#prev_wtxid` — all call sites must update (#678)
- Renamed MerklePath parameters from `txid_hex` to `dtxid_hex` throughout (#681)

### Added
- `Transaction#wtxid` — wire-order transaction ID (raw SHA-256d bytes) (#673)
- `Transaction#dtxid` / `#dtxid_hex` — display-order hex aliases (#680)
- `TransactionInput#dtxid_hex` — display-order hex of the referenced transaction (#678)
- `TransactionInput.wtxid_from_hex` — convert display-order hex to wire-order bytes (#678)
- `Hex.validate_wtxid!` / `Hex.validate_dtxid_hex!` — runtime validation for wire/display txid formats (#685)
- `Hex.validate_hash32!` — general-purpose 32-byte binary hash validator (#686)
- `BSV.logger` — opt-in debug instrumentation with zero overhead when unused (#686)
- Debug logging at txid conversions, sighash preimage, script interpreter, ARC broadcast, BEEF ancestry, and ProtoWallet key derivation (#686, #688)

### Changed
- All internal txid variables renamed to `wtxid` (wire-order) convention (#679)
- BEEF internals enforce wire-order throughout — no byte-reversals inside the bundle (#675)
- MerklePath `compute_root_hex` and `from_tsc` now validate hex input (#686)

### Fixed
- `BeefTx#dtxid` now returns hex string (was returning binary) (#677)
- Certificate field naming aligned with BRC-52 convention (#677)

## 0.16.0 — 2026-05-01

### Breaking Changes
- Removed `bsv-wallet` and `bsv-wallet-postgres` gems from the monorepo (#662)
- Unified `BSV::Wallet` namespace with canonical BRC-100 interface, error reconciliation, and idiomatic ProtoWallet (#664)
- Hard-deprecated `Network::ARC` and `Network::WhatsOnChain` facades (#659)

### Added
- `BSV::Wallet::ProtoWallet` for SDK-native cryptographic operations (signing, encryption, HMAC, key derivation) (#662)

### Fixed
- Guard nil `status_code` in MCP error messages (#659)

## 0.15.0 — 2026-04-29

### Added
- Extracted secp256k1 elliptic curve operations to the standalone
  `secp256k1-native` gem, with an optional native C extension providing
  ~22x speedup for field, scalar, and Jacobian point operations (#648)
- Native C extension scaffold with field arithmetic, scalar arithmetic,
  and Jacobian point operations (#627, #628, #629, #630, #631)
- Constant-time Montgomery ladder with branchless conditional swap for
  scalar multiplication; `mul` is now constant-time by default, with
  `mul_vt` available for variable-time use cases (#641, #653)
- Wycheproof Bitcoin ECDSA test vectors (463 cases) with explicit
  categorisation of high-S malleability cases as mathematically valid
  but policy-rejected — documenting the layer separation between
  ECDSA verification and Bitcoin's low-S enforcement (#652)
- Wycheproof standard ECDSA test vectors (474 cases), RFC 6979
  compliance suite, and secp256k1 field/scalar/point compliance
  examples (#636, #637, #638)

### Fixed
- Carry overflow in schoolbook multiplication (L2) and branchless
  borrow extraction in field reduction (#631)
- Gemspec version floor, docstring, and variable name corrections
  from PR review (#653)

### Changed
- Replaced `BN` hex intermediaries with direct binary construction
  for improved performance (#622)
- Binary byte comparison in `SignedMessage` verification (#624)

## 0.14.0 — 2026-04-22

### Added
- `BSV::Network::WhatsOnChain` expanded with `current_height`,
  `get_block_header(height)`, and `valid_root_for_height?(root, height)` —
  a single WhatsOnChain instance now serves as a complete chain data source
  (#596)
- BEEF-based SPV verification conformance tests (#607)

### Changed
- `Transaction#verify` now raises `VerificationError` for all failure modes:
  `:script_failure` (wraps `ScriptError` with cause chaining),
  `:missing_source` (replaces `ArgumentError`), `:invalid_merkle_proof`,
  `:insufficient_fee`, and `:output_overflow`. Code rescuing `ArgumentError`
  or `ScriptError` from `verify` must switch to `VerificationError` (#608)
- Removed dead code: `BSV::Wallet::Wallet` (superseded by bsv-wallet gem's
  `Client`), `BSV::Messages` (unused re-export alias), and duplicate
  `BSV::Wallet::InsufficientFundsError` (#594)

### Fixed
- WhatsOnChain `valid_root_for_height?` YARD doc now correctly documents
  that 404 returns `false` rather than raising

## 0.13.0 — 2026-04-21

### Added
- Protocol layer: base class with declarative DSL, HTTP dispatch, and Result value types
- WoCREST protocol with transaction detail, script query, exchange rate, fee, mempool, SPV, wallet, and address commands
- ARC protocol with broadcast escape hatches and enriched response data
- TAALBinary protocol with binary broadcast support
- Chaintracks and Ordinals protocols with base_url override
- Provider configuration container with block DSL and `.default(testnet:)` pattern
- Provider introspection and capability matrix
- Concrete provider defaults for GorillaPool, WhatsOnChain, and TAAL

### Changed
- Facades (ARC, WhatsOnChain, ChainTracker) hollowed out to delegate via Protocol
- Removed `BSV::MAINNET_URL`/`TESTNET_URL` constants and ENV var reading — provider defaults are the single source of truth
- Removed `BASE_URL` from protocols — `base_url:` is now mandatory
- Wallet namespace reorganisation: `Store` and `BroadcastQueue` collaborators namespaced under `Client`
- `ProtoWallet` and `WalletClient` replaced with `Client`

### Fixed
- Ruby 2.7 kwargs compatibility in `Protocol#call` and TAALBinary spec doubles
- Nil-guard on WoCREST broadcast and ARC status metadata
- ARC status rejection checks and TAALBinary nil-txid guard
- `BSV::Wallet::Wallet` autoload failure in multi-gem setup
- SimpleCov coverage gate now requires `COVERAGE=true` explicitly

## 0.12.1 — 2026-04-16

### Fixed

- `Transaction#to_ef` now derives `source_satoshis` and `source_locking_script`
  from `input.source_transaction.outputs[input.prev_tx_out_index]` when the
  explicit fields are unset. Previously `to_ef` raised `ArgumentError` on inputs
  wired via `Transaction.from_beef`, causing `ARC#broadcast` to silently fall back
  to raw hex — which ARC rejects when parent transactions are unconfirmed.
  Consumer impact: recently-received UTXOs that previously could not be
  re-broadcast now can. Matches TS SDK `writeEF` behaviour. (#467, HLR #466)
- `Transaction.from_beef` and `from_beef_hex` now use `Beef#find_atomic_transaction`
  to locate the subject transaction, ensuring that `FORMAT_RAW_TX` ancestors whose
  txid appears as a leaf in a separately-stored BUMP have their `merkle_path`
  attached. Covers a late-bound BUMP attachment gap not handled by the initial
  `wire_source_transactions` pass. Matches `Transaction.fromAtomicBEEF` semantics
  in the TS SDK. (#468, HLR #466)

**Related upstream issue:** [wallet-toolbox#149](https://github.com/bsv-blockchain/wallet-toolbox/issues/149) — same architectural gap in the TS SDK.

## 0.12.0 — 2026-04-15

### Added
- Certificate infrastructure: `BSV::Auth::Certificate` base class with field map,
  serialisation, and signature verification (#420)
- `BSV::Auth::MasterCertificate` for certificate issuance with identity key
  binding (#421)
- `BSV::Auth::VerifiableCertificate` for selective field revelation with
  proof-of-field-revelation (#422)
- Certificate utilities: `validate_certificates` and `get_verifiable_certificates`
  helpers (#427, #428)
- Peer protocol: `certificateRequest`/`certificateResponse` message handling,
  callback registration, and `last_interacted_peer` (#430, #431)
- High-level peer session API: `Peer#to_peer` and `Peer#get_authenticated_session`
  for reusable authenticated sessions (#433)
- BRC-104 HTTP auth transport: `AuthFetch` client, `SimplifiedFetchTransport`,
  `AuthMiddleware` (Rack), and `AuthHeaders`/`AuthPayload` serialiser (#437–#441)
- `AuthFetch` 402 payment handling for paid API endpoints (#441)
- `BSV::WireFormat` module for camelCase/snake_case conversion at JSON
  boundaries (#447)
- Cross-SDK conformance and integration specs for certificates (#423)
- Peer protocol integration tests (#434)
- BRC-104 integration tests (#442)

### Fixed
- Auth handshake now uses shallow key conversion to avoid corrupting nested
  message payloads
- Certificate classes hardened against edge cases from code review
- Certifier allowlist enforced in `process_certificate_response`
- Flaky `validate_certificates_spec` fixed (missing `require 'base64'`)

### Changed
- `GetVerifiableCertificates` bug warning note removed (underlying bug now
  fixed in bsv-wallet)
- Peer protocol internals refactored: `PairedTransport` helper, deduplicated
  high-level API, hardened message processing

## 0.11.1 — 2026-04-13

### Fixed
- `ARC.default` and `LivePolicy::DEFAULT_ARC_URL` now point to `arcade.gorillapool.io` (ARCADE) instead of the old `arc.gorillapool.io` endpoint (#418)
- Centralised ARCADE URLs into `BSV::MAINNET_URL` / `BSV::TESTNET_URL` constants, overridable via `BSV_ARC_MAINNET_URL` and `BSV_ARC_TESTNET_URL` environment variables

## 0.11.0 — 2026-04-12

### Added
- `Base58Check.check_encode` accepts `prefix:` parameter; `check_decode` accepts `prefix_length:` (F1.1)
- `Base58.decode("")` raises `ArgumentError` instead of returning empty bytes (F1.2)
- `Digest.hash256` alias for `sha256d` (F1.7)
- `Script.p2pkh_lock` accepts Base58Check address strings as well as raw 20-byte hashes (F3.18)
- `TransactionInput#sequence` and `TransactionOutput#locking_script` now writable via `attr_accessor` (F4.10/F4.11)
- Coinbase 100-block maturity check in `MerklePath#verify` — intentionally diverges from TS SDK bug (F5.11)
- ECIES Electrum `no_key:` encrypt and `sender_public_key:` decrypt with uncompressed key detection (F6.7)
- `BSV::Messages` namespace re-exporting `SignedMessage` and `EncryptedMessage` (F6.16)

### Fixed
- `PointInFiniteField` zero-coordinate Base58 round-trip (BN(0) now encodes as `"\x00"`)
- `p2pkh_lock` encoding check uses bytesize only — accepts 20-byte hashes regardless of string encoding
- `Base58Check.check_decode` raises on `prefix_length` exceeding payload
- ECIES key-format ambiguity documented (inherited TS SDK design)

### Changed
- Numeric fee `.ceil` behaviour documented with inline comment (F4.6)

## 0.10.1 — 2026-04-12

### Added
- `arc_status` attribute on `BroadcastError` to distinguish ARC rejection reasons
  (double-spend, invalid, malformed) for downstream status mapping

## 0.10.0 — 2026-04-11

### Added

- **Chronicle opcode support** (HLR #328). All 10 Chronicle-restored opcodes
  now execute with correct semantics, replacing the 0.9.0 "raise first"
  fail-safes:
  - **Splice:** OP_SUBSTR, OP_LEFT, OP_RIGHT
  - **Arithmetic:** OP_LSHIFTNUM, OP_RSHIFTNUM (sign-preserving right shift)
  - **Arithmetic:** OP_2MUL, OP_2DIV (restored from disabled)
  - **Flow control:** OP_VER (push 4-byte LE tx version), OP_VERIF/OP_VERNOTIF
    (version-conditional branching, added to CONDITIONAL_OPCODES)
  - `MISSING_TX_CONTEXT` error code for OP_VER without transaction context

- **Arcade integration** (HLR #329):
  - `BSV::Transaction::ChainTrackers::Chaintracks` — chain tracker using
    Arcade's Chaintracks v2 API for SPV verification
  - `ChainTrackers.default(testnet:)` — factory returning a Chaintracks
    instance pointed at Arcade
  - `ARC.default(testnet:)` — factory returning an ARC broadcaster pointed
    at GorillaPool, matching TS/Go/Py SDK defaults
  - `ARC#broadcast_many(txs)` — batch broadcast via POST `/v1/txs`, returns
    mixed array of `BroadcastResponse`/`BroadcastError`
  - Skip-validation headers (`skip_fee_validation:`, `skip_script_validation:`)
    on `broadcast` and `broadcast_many`

### Changed

- **Directory restructure** (PR #327). Source files moved to per-gem
  directories: `gem/bsv-sdk/`, `gem/bsv-wallet/`, `gem/bsv-attest/`.
  No change to gem names or require paths.

### Removed

- **`op_disabled` handler** — OP_2MUL/OP_2DIV are now restored; the handler
  is no longer needed.

## 0.9.0 — 2026-04-10

### Changed

- **Change distribution threshold fixed** (#323, F4.1). `distribute_change`
  now drops change outputs only when `available <= 0`, not when
  `available <= change_outputs.length`. Previously 1 satoshi of available
  change with 1 output was incorrectly dropped.

- **`estimated_size` raises on inputs without template** (#323, F4.3).
  Previously fell back to a 148-byte P2PKH estimate. Now raises
  `ArgumentError` matching TS/Go behaviour. **Migration:** set
  `unlocking_script_template` on all inputs before calling `estimated_size`
  or `estimated_fee`.

- **`total_input_satoshis` falls back through `source_transaction`** (#323,
  F4.4). If `source_satoshis` is nil but `source_transaction` is wired,
  the satoshis are extracted from the referenced output automatically.

- **`Transaction#sign` validates output satoshis** (#323, F4.9). Raises
  `ArgumentError` if any output has nil satoshis, preventing a corrupt
  sighash preimage.

- **BEEF/BUMP validation and merge hardening** (HLR #315, A3 cluster).
  Twelve findings addressed across `Beef` and `MerklePath`:
  - **F5.1** — `BeefTx` TXID_ONLY entries now store txid in display byte
    order (matching `Transaction#txid`). Wire serialisation reverses at
    the boundary. Fixes cross-SDK TXID_ONLY interop.
  - **F5.12** — `Beef.from_binary` now raises `ArgumentError` for unknown
    version magic bytes instead of silently accepting them.
  - **F5.10** — `MerklePath` constructor now validates: non-negative
    `block_height`, non-empty `path`, all levels are `Array<PathElement>`,
    and level 0 contains at least one `txid: true` element.
  - **F5.2** — `MerklePath#compute_root` correctly handles single-level
    compound paths where `max_offset.bit_length > path.length` (matches TS
    SDK `computeRoot` logic including duplicate-sibling handling for odd
    rightmost nodes).
  - **F5.4** — `Beef#valid?` now cross-checks each `FORMAT_RAW_TX_AND_BUMP`
    entry: the BUMP must exist and `compute_root(txid)` must succeed.
  - **F5.3** — New `Beef#verify(chain_tracker = nil, allow_txid_only: false)`
    method: calls `valid?` then optionally verifies each BUMP's root against
    a chain tracker via `valid_root_for_height?(root_hex, block_height)`.
  - **F5.5** — `sort_transactions!` now preserves unsortable (cyclic)
    transactions in `@txs_not_valid` instead of silently dropping them.
    `to_binary` now calls `sort_transactions!` before serialising.
  - **F5.6** — `merge_bump` retroactively upgrades existing
    `FORMAT_RAW_TX` entries to `FORMAT_RAW_TX_AND_BUMP` when the new BUMP
    covers their txid.
  - **F5.7** — `merge_transaction` and `merge_raw_tx` now implement the
    full upgrade chain: `TXID_ONLY → RAW_TX → RAW_TX_AND_BUMP`.
  - **F5.8** — `find_bump` now also scans `@bumps` directly when the
    transaction-table has no matching entry.
  - **F5.9** — `Beef#merge` constructs new `BeefTx` instances rather than
    sharing (and mutating) source references.
  - **F5.20** — `to_binary` calls `sort_transactions!` before serialising
    to ensure correct dependency order.

- **`PrivateKey#to_wif` always produces compressed WIF** (#316, F2.4).
  The `compressed: false` keyword has been removed. BSV exclusively uses
  compressed public keys, so exporting an uncompressed WIF is never valid
  on the network ("construct only what's valid"). `from_wif` continues to
  accept both compressed and uncompressed WIF for import compatibility with
  legacy wallets.
  **Migration:** remove any `to_wif(compressed: false)` call sites. If you
  need to import an existing uncompressed WIF, `from_wif` still handles it.

- **`Curve.multiply_generator` / `multiply_point` route secret scalars
  through constant-time Montgomery ladder** (#316, F2.1).
  `PrivateKey#public_key`, `PrivateKey#derive_shared_secret`,
  `PublicKey#derive_shared_secret`, and `ECDSA.sign_raw` now call
  `Curve.multiply_generator_ct` / `Curve.multiply_point_ct` (new),
  which delegate to `Point#mul_ct` (Montgomery ladder). Variable-time
  wNAF (`mul`) is retained for public-scalar paths (signature verification).
  Benchmarked at ~2× slower than wNAF, within the expected 2–3× bound.

- **`WNAF_TABLE_CACHE` is now bounded at 512 entries** (#316, F2.1).
  Evicts the oldest entry (FIFO) when the limit is reached. Prevents
  unbounded memory growth in long-running server processes that operate
  on many distinct base points.

- **`Signature.from_der` rejects multi-byte DER length encoding** (#316,
  F2.3). Signatures with a length byte where bit 7 is set (e.g. `0x81`,
  `0x82`) are now rejected with `ArgumentError: non-canonical DER length`.
  This enforces BIP-66 strict DER; such encodings were never generated by
  this SDK and should never appear in valid BSV transactions.

- **`ECDSA.sign` accepts `force_low_s:` keyword** (#316, F2.2).
  `ECDSA.sign(hash, key, force_low_s: true)` explicitly normalises S to the
  lower half of the curve order. Default (`false`) preserves existing
  behaviour (`sign_raw` already normalises internally). Documented that BSV
  consensus requires low-S.

### Removed

- **`Curve.ec_key_from_private_bytes` and `Curve.ec_key_from_public_bytes`
  deleted** (#316, F2.9). These methods were unused in all production code
  paths — the only callers were test helpers and the shim's `parse_der`
  method, which are also removed. The `BSVShimEC` DER-parsing constructor
  (`OpenSSL::PKey::EC.new(der_string)`) is no longer supported; pass a
  `BSVShimECPoint` directly.

- **`Script::Script.pushdrop_lock` default `lock_position` changed to `:before`**
  ([#317](https://github.com/sgbett/bsv-ruby-sdk/issues/317), F3.12).
  The `lock_position:` keyword argument has been added to `pushdrop_lock` and
  `PushDropTemplate#lock`. The default is now `:before` (lock script first,
  then data fields and drops), matching the ts-sdk convention used by overlay
  token protocols. The previous implicit behaviour was equivalent to `:after`.
  **Migration:** callers that built PushDrop outputs using the old default must
  add `lock_position: :after` to preserve their existing on-chain script layout.
  Scripts already on-chain are unaffected — the parser detects both layouts.

- **`Script#parse_chunks` is now lenient on truncated scripts** (#317, F3.16).
  Previously, calling `#chunks` on a truncated script raised `ArgumentError`.
  Now the parser returns a partial chunk array with a trailing raw-bytes chunk,
  consistent with `p2pkh?`, `op_return?`, and other byte-level predicates that
  already returned `false` rather than raising. Callers that rescue
  `ArgumentError` from `#chunks` should update their rescue logic.

- **`Script::Script.op_return` and OP_RETURN parsing** (#317, F3.1, F3.10).
  The parser now terminates at a top-level `OP_RETURN` and absorbs all trailing
  bytes into a single raw-data chunk (matching ts-sdk). `Chunk#to_asm` renders
  these as `OP_RETURN <tail_hex>` rather than separate push chunks. The
  `#op_return_data` method re-parses the tail internally, so it still returns
  individual data items. Code that inspected `script.chunks[2..]` after an
  `OP_RETURN` must switch to `script.op_return_data`.

### Added

- **Extended NOP range `OP_NOP11`–`OP_NOP77`** (#317, F3.2). Opcodes
  `0xba`–`0xfc` are now defined as named constants so that `to_asm` /
  `from_asm` can round-trip scripts containing them.

- **Canonical ASM aliases `"0"` and `"-1"`** (#317, F3.3). `Script.from_asm`
  now accepts `"0"` as an alias for `OP_0` and `"-1"` as an alias for
  `OP_1NEGATE`, matching the ts-sdk's `fromASM` behaviour.

- **Explicit PUSHDATA sequences in `from_asm`** (#317, F3.4). Token sequences
  of the form `OP_PUSHDATA1 <len> <hex>`, `OP_PUSHDATA2 <len> <hex>`, and
  `OP_PUSHDATA4 <len> <hex>` are now consumed as a unit by `from_asm`.

- **`OP_UNKNOWN<n>` ASM rendering for unlisted opcodes** (#317, F3.6).
  `Chunk#to_asm` now emits `OP_UNKNOWN<n>` (e.g. `OP_UNKNOWN186`) for opcodes
  with no defined constant, making the output unambiguous and round-trippable
  via `from_asm`.

- **`PushDropTemplate#lock` supports `lock_position:`** (#317, F3.12). The
  `lock_position:` keyword argument (`:before` default / `:after`) is now
  forwarded from `PushDropTemplate#lock` to `Script.pushdrop_lock`.

### Fixed

- **`encode_minimally` no longer collapses `[0x00]` to `OP_0`** (#317,
  F3.14/F3.21). `OP_0` pushes an empty byte array; pushing a single zero byte
  `[0x00]` is semantically different. The ts-sdk has the same bug in
  `createMinimallyEncodedScriptChunk` — we fix it locally and plan to raise it
  upstream.

- **`Stack#pop_int` / `Stack#peek_int` now enforce minimal encoding by default**
  ([#318](https://github.com/sgbett/bsv-ruby-sdk/issues/318), F7.11).
  `require_minimal:` now defaults to `true`, matching post-Genesis BSV consensus
  rules. Previously the default was `false`, allowing non-minimally encoded script
  numbers to be silently accepted.
  **Migration:** callers that relied on decoding non-minimal encodings (e.g.
  `"\x80\x00\x01"` for 256 instead of the minimal `"\x00\x01"`) will now receive a
  `ScriptError` with code `:minimal_data`. Pass `require_minimal: false` explicitly
  to restore the previous behaviour where that is intentional.

- **Chronicle opcodes now raise `ScriptErrorCode::UNIMPLEMENTED_OPCODE`**
  ([#318](https://github.com/sgbett/bsv-ruby-sdk/issues/318), F7.1/F7.2).
  `OP_SUBSTR` (0xb3), `OP_LEFT` (0xb4), `OP_RIGHT` (0xb5), `OP_LSHIFTNUM` (0xb6),
  `OP_RSHIFTNUM` (0xb7), `OP_VER` (0x62), `OP_VERIF` (0x65), and `OP_VERNOTIF`
  (0x66) previously executed silently as no-ops or reserved-opcode errors with
  a different code. Any script that executes one of these opcodes will now raise
  `ScriptError` with code `:unimplemented_opcode` rather than succeeding silently.
  Full Chronicle string and numeric-shift semantics are planned for SDK v0.10.
  **Migration:** scripts relying on these opcodes producing no-op or
  `RESERVED_OPCODE` behaviour must be updated. Chronicle opcode constants
  (`OP_SUBSTR`, `OP_LEFT`, etc.) are now defined in `BSV::Script::Opcodes`.

### Added

- **32 MB stack memory limit** ([#318](https://github.com/sgbett/bsv-ruby-sdk/issues/318),
  F7.18). The script execution stack now enforces a 32 MB aggregate memory cap,
  matching the ts-sdk. Every push (including those from `dup_n`, `over_n`, `pick_n`,
  and `tuck`) checks the limit and raises `ScriptError` with code
  `:stack_memory_exceeded` if exceeded. This naturally bounds O(n²) opcodes such
  as `OP_MUL` on large operands.

- **CHECKMULTISIG post-Genesis key-count limit removed** ([#318](https://github.com/sgbett/bsv-ruby-sdk/issues/318),
  F7.8). The 20-key cap on `OP_CHECKMULTISIG` has been removed in line with
  post-Genesis BSV rules. The stack memory limit is now the practical bound.

- **Conditional nesting depth cap** ([#318](https://github.com/sgbett/bsv-ruby-sdk/issues/318),
  F7.19). `OP_IF` / `OP_NOTIF` now raise `ScriptError` with code
  `:unbalanced_conditional` if the nesting depth exceeds 256, preventing interpreter
  stack overflow from deeply nested conditionals.

- **Hybrid public key prefix rejection** ([#318](https://github.com/sgbett/bsv-ruby-sdk/issues/318),
  F7.10). `CHECKSIG` and `CHECKMULTISIG` now explicitly document that hybrid
  encoding prefix bytes 0x06 and 0x07 are rejected. Only compressed (0x02/0x03)
  and uncompressed (0x04) keys are valid.

- **CHECKSIG / CHECKMULTISIG no-tx behaviour corrected** ([#318](https://github.com/sgbett/bsv-ruby-sdk/issues/318),
  F7.9). When no transaction context is provided (e.g. `Interpreter.evaluate`
  without a tx), `OP_CHECKSIG` and `OP_CHECKMULTISIG` now push `false` for
  non-empty signatures rather than raising `SIG_NULLFAIL`. NULLFAIL only applies
  when a real verification failure occurs — without a tx there is nothing to verify.

- **`Transaction#estimated_fee` default rate aligned and deprecated**
  ([#310](https://github.com/sgbett/bsv-ruby-sdk/issues/310), F4.2).
  The default fee rate changed from 0.5 sat/byte (500 sat/kB) to 0.1
  sat/byte (100 sat/kB), matching the `SatoshisPerKilobyte.new` default.
  The method now delegates through `SatoshisPerKilobyte` internally and
  emits a deprecation warning pointing consumers at the fee model API.
  **Migration:** replace `tx.estimated_fee` with
  `SatoshisPerKilobyte.new.compute_fee(tx)`. If you relied on the 0.5
  sat/byte default, pass `value: 500` to the fee model.

- **`BSV::Primitives::Hex` module** (#310, F1.5). Strict hex
  decode/encode with validation — raises `ArgumentError` on odd-length
  or non-hex input instead of silently truncating. All consumer-facing
  `from_hex` parse paths (`Transaction`, `Beef`, `MerklePath`, `Script`,
  `PublicKey`, `Signature`, `Builder`) now use `Hex.decode` and reject
  malformed hex loudly. `Script.from_asm` hex tokens are also validated —
  previously non-hex tokens were silently packed as garbled bytes.

- **Pure-Ruby RIPEMD-160** (#310, F1.8). Replaces the
  `OpenSSL::Digest::RIPEMD160` dependency with a pure-Ruby
  implementation (`BSV::Primitives::Ripemd160`), eliminating the
  portability failure on OpenSSL 3 builds that don't load the legacy
  provider. Same precedent as the pure-Ruby secp256k1 port (#253).
  Verified against all 9 official RIPEMD-160 spec vectors.

### Testing

- **Cross-SDK conformance vector suite** ([#307](https://github.com/sgbett/bsv-ruby-sdk/issues/307)).
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

## 0.8.2 — 2026-04-08

Paired security patch release. Three P0 findings from the
[2026-04-08 cross-SDK compliance review](.architecture/reviews/20260408-cross-sdk-compliance-review.md)
plus follow-up hardening from the PR review pass. Must be installed
together — the `bsv-wallet` gemspec now pins its `bsv-sdk` dependency
to `>= 0.8.2, < 1.0` to enforce the paired upgrade and prevent a stale
pair where one gem has its fixes and the other doesn't.

Two GitHub Security Advisories accompany this release (draft until
CVE IDs return from MITRE):


### Security

- **`VarInt.encode` now rejects negative integers** and values
  above 2^64 − 1. Previously `VarInt.encode(-1)` fell into the single-
  byte branch and emitted `0xFF` (the marker for a 9-byte encoding),
  silently corrupting the transaction stream with no exception raised.
  The docstring already required a non-negative integer; the
  implementation did not enforce it. Closes F1.3.

- **ARC broadcaster recognises the full failure status set**. The
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

- **ARC broadcaster HTTP wire format** brought into line with the
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


### Internal

- `lib/bsv/network/**/*` added to `Metrics/ClassLength` and
  `Metrics/ParameterLists` RuboCop exclusion lists to match the
  existing treatment of `lib/bsv/wallet_interface/**/*`. ARC is
  HTTP-client boilerplate in the same shape.
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

## 0.8.1 — 2026-04-08

### Fixed

- **`Transaction#to_beef` strips phantom `txid: true` leaves** —
  when a proof loaded from a shared `LocalProofStore` carries txid flags
  for transactions that are not part of the bundle being constructed,
  `to_beef` now rebuilds each per-block BUMP from only the bundle's own
  txids instead of propagating the phantoms into the serialised output.
  ARC previously rejected such BEEFs with misleading parser errors,
  blocking any wallet workflow that received a BEEF via
  `internalize_action` and then spent the internalised UTXOs.
  Closes #302.

### Added

- **`MerklePath#extract(txid_hashes)`** — returns a new trimmed
  compound path covering only the requested txids, reconstructing the
  minimum set of sibling hashes at each tree level. Raises
  `ArgumentError` on empty input, unknown txid, or root mismatch.
  Ported from the TypeScript SDK. Used internally by
  `Transaction#to_beef` and available for direct use.
- **`MerklePath#trim`** — removes internal nodes not required by
  level-zero txid leaves. Called implicitly by `#combine` and `#extract`
  and rarely needs to be invoked directly. Ported from the TypeScript
  SDK.
- **`MerklePath#initialize_copy`** — `.dup` now produces a new
  MerklePath whose outer and level arrays are independent of the
  source, so the copy can be freely mutated via `#combine`, `#trim`,
  or `#extract` without affecting the original. `PathElement`s
  remain immutable and are shared between source and copy.

### Changed

- **`MerklePath#combine`** now calls `#trim` at the end so merged
  paths stay minimal across repeated merges, matching the TypeScript
  SDK. Combined paths are strictly smaller than before — external
  callers that inspected `mp.path` after `#combine` may see fewer
  nodes, though every txid leaf's merkle proof is preserved.
- **`MerklePath#combine`** also preserves `txid: true` flags when
  the incoming leaf is flagged and the existing leaf at the same offset
  isn't, so merging an ancestor's single-leaf proof into a compound
  that already contains the same offset as a sibling no longer loses
  the txid flag.
- **`Transaction#to_beef`** now raises `ArgumentError` if an
  ancestor's merkle path doesn't actually contain that transaction's
  txid, or if the rebuilt BUMP's root doesn't match the source root.
  Previously such corrupt proof data would silently emit a broken BEEF.
  Callers relying on `to_beef` not raising on valid data are
  unaffected; the new exception only triggers on corrupt proof stores.

### Internal

- **`Beef#merge_transaction`** indirectly benefits from the
  tighter `#combine` + `#trim` behaviour: compound BUMPs no longer
  accumulate dead sibling hashes across repeated merges.
- On the real-world `#302` regression fixture, the cleaned BUMP
  shrinks from 2476 B to 1300 B (47% reduction) as a side effect of
  `#extract` removing intermediate siblings that are no longer needed
  once phantom leaves are gone.

## 0.8.0 — 2026-04-08

### Added

- **`MerklePath.from_tsc`** — convert WhatsOnChain TSC merkle proofs
  (the flat leaf-to-root sibling list returned by
  `/tx/{txid}/proof/tsc`) into BRC-74 BUMP format. Verified end-to-end
  against a real mainnet vector (block 612251). Closes #280.
- **`Beef#version=`** writer — promoted from internal
  `instance_variable_set` to a proper accessor.

### Changed

- **`Beef#to_binary` rewrite** — serialises BUMPs from the canonical
  `@bumps` array and uses `beef_tx.bump_index` as the on-wire reference,
  instead of walking each transaction's `merkle_path` via object identity.
  Fixes duplicate-BUMP serialisation for same-block ancestors that
  previously caused ARC `468 BEEF invalid` rejections. Matches the TS and
  Go reference SDKs. Closes #288.
- **`Beef#to_hex`** preserves the bundle's `@version` so a BEEF
  parsed from V2 round-trips to V2 hex (and V1 to V1) instead of always
  silently downgrading to V1. The original docstring already claimed
  "V2 hex string" — this fix matches the original intent. Closes #292.
- **`Beef#initialize`** default `version:` parameter changed from
  `BEEF_V2` to `BEEF_V1` to match `to_binary`'s default. Every existing
  `Beef.new + to_hex` caller continues to emit V1 (preserving every
  existing observable behaviour). Closes #292.
- **`bsv-sdk` gem packaging** — explicit module list in
  `bsv-sdk.gemspec` excludes `bsv-attest` and `bsv-wallet` code. Reduces
  `bsv-sdk` from 144 files to 98 (24% smaller); no overlap with the
  sibling gems except `LICENSE`.
- `Transaction#to_beef` docstring corrected from "BEEF V2 binary
  bundle" to "BEEF V1 binary bundle (BRC-62)" to match what the method
  actually emits.

### Fixed

- **`Beef#to_binary`** raises `ArgumentError` upfront when V1
  (BRC-62) is requested for a bundle containing `FORMAT_TXID_ONLY`
  entries, instead of crashing deep inside `write_v1_tx` with
  `NoMethodError`. V2 (BRC-96) supports TXID-only and is unaffected. The
  error message points the caller at `version: BEEF_V2`. Closes #290.
- **`Beef#merge`** raises `ArgumentError` on inconsistent
  `bump_index` from the source bundle (when the source has a transaction
  pointing at a `bump_index` that doesn't exist in the source's
  `@bumps`), instead of silently propagating a stale index that could
  attach the wrong merkle path to a transaction in the merged bundle.
  Closes #291.
- **`Beef::BeefTx#initialize`** validates that
  `FORMAT_RAW_TX_AND_BUMP` requires a non-nil `bump_index`, failing fast
  in the constructor instead of crashing later in `VarInt.encode(nil)`.
- **`Beef#merge_raw_tx`** bounds-checks the `bump_index` parameter
  and raises `ArgumentError` if out of range, instead of silently writing
  an invalid index that downstream parsers would misinterpret.

### Internal

- CI is now green: 73 pre-existing RuboCop offenses across
  `spec/conformance/openssl_shim_compliance/` resolved. Closes #293.
- OpenSSL EC shim conformance suite is now skipped on Ruby 2.7,
  where stock `OpenSSL::PKey::EC::Point#add` is unavailable. The shim
  itself still has direct unit-test coverage on every supported Ruby.

## 0.7.0 — 2026-04-06

### Changed

- `Beef#to_binary` now defaults to BEEF V1 (BRC-62) format, matching
  the TS reference SDK's `Transaction#toBEEF()`. ARC's parser does not
  support V2. Pass `version: BEEF_V2` for BRC-96 format. Atomic BEEF (BRC-95)
  inner envelope remains V2 per spec.

## 0.6.2 — 2026-04-06

### Added

The sdk gem was re-released alongside this wallet change with no
behavioural changes of its own.

## 0.6.1 — 2026-04-05

### Fixed

- Use internal byte order for Atomic BEEF subject txid lookup, fixing
  serialisation of transactions loaded from Atomic BEEF format.

## 0.6.0 — 2026-04-04

### Added

#### Primitives

- **Pure Ruby secp256k1** — native Ruby implementation of secp256k1
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

- **Registry client** — `BSV::Registry` module for on-chain definition
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

- OpenSSL usage reduced — OpenSSL now used only for hashing
  (SHA/RIPEMD), HMAC, PBKDF2, AES, and constant-time comparison. Elliptic
  curve operations are pure Ruby.

## 0.5.0 — 2026-04-04

### Added

#### Overlay

- **SHIP/SLAP overlay services** — `BSV::Overlay` module for
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

- **Identity client** — `BSV::Identity` module for certificate-based
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

- **PushDropTemplate** — reusable wallet-aware PushDrop template with
  BRC-42 key derivation, optional ECDSA field signing, and P2PKH
  lock/unlock. Used by Identity client, reusable for ContactsManager and
  other PushDrop-based features.

### Fixed

- `ProtoWallet` parameter name mismatch: `_originator:` →
  `originator:` to match the `WalletInterface` contract.

## 0.4.0 — 2026-04-01

### Added

#### Primitives

- **Bitcore ECIES** — `ECIES.bitcore_encrypt` /
  `ECIES.bitcore_decrypt`. AES-256-CBC with random IV, SHA-512(X-coordinate)
  key derivation. Matches ts-sdk and go-sdk Bitcore variants.

#### Transaction

- **`LivePolicy.default`** — one-line convenience for live fee queries
  via GorillaPool ARC with 5-minute cache and 100 sat/kB fallback. (The
  underlying `LivePolicy` fee model itself shipped in sdk-0.3.2.)

#### Wallet


### Changed

- **Default fee rate**: `SatoshisPerKilobyte` default changed from 50
  to 100 sat/kB (matches ts-sdk LivePolicy fallback).

## 0.3.2 — 2026-03-30

### Added

#### Script

- **OP_CAT template** — OP_CAT concatenation script template with
  lock/unlock constructors.

#### Transaction

- **LivePolicy fee model** — fetches policy from ARC `/v1/policy`
  endpoint. (The convenience constructor `LivePolicy.default` was added
  in sdk-0.4.0.)

#### Wallet


### Fixed

- PUSHDATA1/2/4 bounds check (silent data corruption on truncated
  scripts).
- Extended key path validation (reject non-numeric indices).

This was the first formal `bsv-wallet` gem release tag. Wallet code that
landed in master before this date (notably the BRC-100 identity certificate
methods and the BRC-100 blockchain-data / authentication methods committed
during the sdk-0.3.1 window) is part of this gem's initial released state.

## 0.3.1 — 2026-03-27

### Added

#### Network

- **`ARC#broadcast` `wait_for:` parameter** — sets the `X-WaitFor`
  header (RECEIVED, STORED, ANNOUNCED_TO_NETWORK, SEEN_ON_NETWORK, MINED)
  so callers can choose how long ARC blocks before responding.

## 0.3.0 — 2026-03-27

### Added

#### Primitives

- **SymmetricKey** — AES-256-GCM encryption/decryption with 32-byte
  IV (cross-SDK compatible). Construct from random, ECDH, or raw bytes.
- **BRC-77 SignedMessage** — authenticated message signing and
  verification using BRC-42 derived keys. Supports targeted (specific
  verifier) and "anyone" modes.
- **BRC-78 EncryptedMessage** — end-to-end encrypted messaging using
  ECDH-derived symmetric keys.
- **Schnorr ZKP (BRC-94)** — zero-knowledge proof of ECDH shared
  secret knowledge. `Schnorr.generate_proof` / `Schnorr.verify_proof`.
- **Shamir's Secret Sharing** — split private keys into threshold
  shares (`PrivateKey#to_key_shares`) with Lagrange interpolation
  reconstruction. Backup format with integrity check.

#### Script

- **PushDrop template** — data carrier with P2PK spending.
  `Script.pushdrop_lock` / `Script.pushdrop_unlock` with field extraction.
- **RPuzzle template** — R-puzzle hash-based spending with 6 hash
  type variants (raw, SHA1, SHA256, RIPEMD160, HASH160, HASH256).

#### Transaction

- **Benford's law change distribution** — privacy-preserving change
  output splitting using Benford's first-digit distribution.

### Fixed

- Empty plaintext/ciphertext handling on older OpenSSL versions.
- PushDrop detection for minimally-encoded fields.

### Changed

- `Transaction#fee` change distribution uses Benford's law (was equal
  split).
- `LineLength` raised to 150.

## 0.2.1 — 2026-03-07

### Fixed

- Truncated `OP_PUSHDATA1`/`2`/`4` scripts now raise `ArgumentError`
  instead of crashing with `TypeError`.
- `Transaction#to_beef` uses `merge_bump` to correctly handle
  multiple ancestors at the same block height.
- `PrivateKey#derive_child` uses `BN.mod_add` instead of Integer
  roundtrip for modular addition.
- Fixed txid byte-order documentation (display order, not internal
  order).

### Testing

- FORKID enforcement spec verifying interpreter rejects signatures
  without SIGHASH_FORKID.
- ExtendedKey fingerprint chain integrity across 3-generation
  derivation.
- Mnemonic entropy round-trip across all 5 valid entropy lengths.
- BEEF spec for multiple ancestors at the same block height.

## 0.2.0 — 2026-03-07

### Added

#### Primitives

- ECDH shared secret derivation
  (`PrivateKey#derive_shared_secret`, `PublicKey#derive_shared_secret`).
- BRC-42 key derivation (`PrivateKey#derive_child`,
  `PublicKey#derive_child`) with official spec test vectors.

#### Transaction

- Chain tracker interface (`ChainTracker` base class) with
  WhatsOnChain implementation.
- Fee model interface (`FeeModel` base class) with
  `SatoshisPerKilobyte` implementation.
- `Transaction#fee` with change output distribution across multiple
  change outputs.
- `Transaction#verify` for full SPV verification (merkle path,
  script execution, recursive ancestry).
- `TransactionOutput#change` flag for identifying change outputs.
- `MerklePath#verify` for SPV chain tracker integration.
- BEEF completion: `Beef#merge`, `Beef#valid?`, lookup methods
  (`find_bump`, `find_transaction_for_signing`).
- `Transaction#to_beef` / `Transaction.from_beef` convenience
  methods.
- Extended Format (EF) transaction serialisation (`to_ef`,
  `to_ef_hex`, `from_ef`, `from_ef_hex`).
- `VerificationError` with typed error codes for SPV verification
  failures.

### Changed

- ECIES refactored to use `PrivateKey#derive_shared_secret`
  internally (no API change).
- `Transaction#estimated_size` made public for fee model access.

### Fixed

- Nil `source_satoshis` now raises instead of silently coercing to
  zero in fee distribution and verification.
- Script chunk round-trips preserve original push encoding.
- `OP_RETURN` inside conditionals correctly checked for conditional
  balance.
- Point x-coordinate extraction preserves leading zeros via octet
  string.
- `Integer#nobits?` replaced with Ruby 2.7-compatible bitwise check.
- Defensive parsing with descriptive errors for truncated binary
  input.

### Testing

- BRC-42 conformance specs with 9 official specification test
  vectors.
- ECDH conformance specs (commutativity, cross-method, pinned
  known-key vector).
- SPV verification conformance specs (merkle path, script execution,
  ancestry).
- Fee model conformance specs (formula validation, default rate,
  change distribution).
- Chain tracker conformance specs.
- BEEF cross-SDK conformance vectors.
- Schnorr (BRC-94) cross-SDK interoperability vectors.
- 6 exact-match RFC 6979 vectors from Trezor/CoreBitcoin.
- VarInt boundary tests at size-prefix transitions.
- Script vectors converted to tracked known-failures system.

## 0.1.0 — 2026-02-14

Initial release of the BSV Ruby SDK.

### Added

#### Primitives

- secp256k1 elliptic curve operations (point arithmetic, scalar
  multiplication).
- ECDSA signing and verification with RFC 6979 deterministic nonces.
- Public and private key handling (WIF import/export,
  compressed/uncompressed formats).
- Base58Check encoding and decoding.
- Hash functions: SHA-256, RIPEMD-160, Hash160 (SHA-256 +
  RIPEMD-160), SHA-512, HMAC.
- BIP-32 hierarchical deterministic key derivation (extended keys,
  hardened/normal child paths).
- BIP-39 mnemonic phrase generation and seed derivation.
- ECIES encryption and decryption (BIE1 format).
- Bitcoin Signed Message (BSM) signing and verification.

#### Script

- Opcode constants (full set).
- Script chunk representation and parsing.
- Script serialisation and deserialisation.
- Script templates: P2PKH, P2PK, P2MS (multisig), OP_RETURN data.
- Script type detection (including read-only recognition of P2SH and
  other legacy types).
- Script builder API for programmatic construction.
- Script interpreter with stack operations, arithmetic, crypto, flow
  control, splice, and bitwise ops.

#### Transaction

- Transaction construction and serialisation (raw format).
- BIP-143 sighash computation (all hash types with FORKID).
- Transaction signing with configurable sighash flags.
- BEEF serialisation (BRC-95/BRC-96).
- Merkle path representation and verification.
- Fee estimation.
- Script verification during signing.
- Unlocking script templates for common script types.

#### Network

- ARC broadcaster for transaction submission.
- WhatsOnChain chain data provider.
- Basic wallet functionality.

#### Testing

- Cross-SDK test vectors from Go, TypeScript, and Python reference
  implementations.
- NIST and RFC hash function test vectors.
- Bitcoin Core script interpreter test suite.
- Protocol conformance specs for opcodes, sighash flags, and
  transaction templates.
