# Changelog

All notable changes to this project will be documented in this file.

This repository ships two gems with independent versioning:

- **`bsv-sdk`** — the declarative SDK (primitives, script, transaction, etc.)
- **`bsv-wallet`** — the BRC-100 wallet interface gem (depends on `bsv-sdk`)

The two gems may release on different schedules. Section headers identify
which gem(s) released, e.g.:

- `## sdk-0.7.0 / wallet-0.3.0 — 2026-04-06` — both gems released together
- `## sdk-0.6.1 — 2026-04-05` — sdk-only release
- `## wallet-0.3.3 — 2026-04-06` — wallet-only release

Every bullet is prefixed with `[sdk]` or `[wallet]` to disambiguate which gem
the change belongs to, regardless of which header it sits under.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and each gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
independently.

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
