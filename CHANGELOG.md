# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.2] - 2026-04-06

### Added

- **Wallet** — `WalletClient#create_action` now accepts `UnlockingScriptTemplate` objects (e.g. `P2PKH`) as input unlocking scripts, enabling template-based signing without BEEF.
- **Wallet** — `wire_source_from_storage` fallback populates `source_satoshis` and `source_locking_script` from wallet storage when BEEF is absent or incomplete, enabling BIP-143 sighash computation for wallet-tracked outputs.
- **Wallet** — `finalize_action` resolves template inputs via `sign_all` before serialisation.
- **Storage** — `MemoryStore#filter_outputs` supports outpoint filtering for efficient single-output lookups.

## [0.6.1] - 2026-04-05

### Fixed

- **Transaction** — use internal byte order for Atomic BEEF subject txid lookup, fixing serialisation of transactions loaded from Atomic BEEF format.

## [0.6.0] - 2026-04-04

### Added

#### Primitives

- **Pure Ruby secp256k1** — native Ruby implementation of secp256k1 elliptic curve operations, ported from the TypeScript reference SDK. Replaces OpenSSL's EC point arithmetic with an OpenSSL compatibility shim — zero consumer code changes required. See [docs/about/secp256k1.md](docs/about/secp256k1.md).
  - Field arithmetic (modular multiplication, inversion, square root) over the secp256k1 prime.
  - Jacobian coordinate point operations (addition, doubling, scalar multiplication).
  - Windowed-NAF (w=5) scalar multiplication with precomputed table caching.
  - SEC 1 point serialisation (compressed and uncompressed).
  - 126 byte-for-byte compliance specs against real OpenSSL.
  - 24 process-isolated integration tests (separate Ruby processes, MD5 file comparison).

#### Registry

- **Registry client** — `BSV::Registry` module for on-chain definition management.
  - `Client` — register, resolve, list, revoke, and update definitions for protocols, baskets, and certificate types via PushDrop tokens on the overlay network.
  - Per-type overlay topics (`tm_basketmap`, `tm_protomap`, `tm_certmap`) and lookup services matching TS and Go SDKs.
  - Types: `BasketDefinitionData`, `ProtocolDefinitionData`, `CertificateDefinitionData`, `CertificateFieldDescriptor`, `RegisteredDefinition`.
  - Ownership verification before revocation. BEEF Array/String normalisation for wire format compatibility.

### Changed

- **OpenSSL usage reduced** — OpenSSL now used only for hashing (SHA/RIPEMD), HMAC, PBKDF2, AES, and constant-time comparison. Elliptic curve operations are pure Ruby.

## [0.5.0] - 2026-04-04

### Added

#### Overlay

- **SHIP/SLAP overlay services** — `BSV::Overlay` module for topic-based transaction broadcasting and service discovery.
  - `TopicBroadcaster` (aliased as `SHIPBroadcaster`) — broadcasts tagged BEEF to topic-interested hosts with configurable acknowledgement modes (all/any/specific hosts) and STEAK response parsing.
  - `LookupResolver` — discovers competent hosts via SLAP trackers, queries in parallel, aggregates and deduplicates results. TTL-based host caching.
  - `HostReputationTracker` — EWMA latency scoring with exponential backoff, DNS error escalation, thread-safe. Optional persistence via injectable store adapter.
  - `AdminTokenTemplate` — decode/lock/unlock for SHIP/SLAP advertisement PushDrop tokens with BRC-42 wallet key derivation.
  - Abstract base classes (`LookupFacilitator`, `BroadcastFacilitator`) with default HTTPS implementations — all dependencies injectable via constructor.
  - SSRF protection for SLAP-discovered domains (private/loopback IP rejection).

#### Identity

- **Identity client** — `BSV::Identity` module for certificate-based identity resolution and publication.
  - `Client` — resolve identities by key or attributes, publicly reveal certificate fields on-chain, revoke revelations. All overlay dependencies injectable.
  - `IdentityParser` — converts identity certificates to `DisplayableIdentity`, handling all 9 known types (xCert, discordCert, phoneCert, emailCert, identiCert, registrant, coolCert, anyone, self) plus generic field-name heuristic fallback.
  - Types: `DisplayableIdentity`, `IdentityCertificate`, `CertifierInfo`, `ClientOptions` with cross-SDK constant alignment.
  - Certificate verifier injectable with safe-by-default (raises `NotImplementedError`).

#### Script

- **PushDropTemplate** — reusable wallet-aware PushDrop template with BRC-42 key derivation, optional ECDSA field signing, and P2PKH lock/unlock. Used by Identity client, reusable for ContactsManager and other PushDrop-based features.

### Fixed

- `ProtoWallet` parameter name mismatch: `_originator:` → `originator:` to match the `WalletInterface` contract.

## [0.4.0] - 2026-04-01

### Added

#### Primitives

- **Bitcore ECIES** — `ECIES.bitcore_encrypt` / `ECIES.bitcore_decrypt`. AES-256-CBC with random IV, SHA-512(X-coordinate) key derivation. Matches ts-sdk and go-sdk Bitcore variants.

#### Transaction

- **LivePolicy.default** — one-line convenience for live fee queries via GorillaPool ARC with 5-minute cache and 100 sat/kB fallback.

### Changed

- **Default fee rate**: `SatoshisPerKilobyte` default changed from 50 to 100 sat/kB (matches ts-sdk LivePolicy fallback). `Wallet#fund` default changed from 0.5 to 0.1 sat/byte.

### bsv-wallet v0.2.0

- **FileStore** — JSON file-backed persistent storage, now the default for `WalletClient`. Data survives process restarts. MemoryStore becomes explicit opt-in for tests.
- **File permissions** — directory created with 0700, files with 0600. Warns via Logger on startup if permissions are too open.
- **BRC-31 Auth/Peer** — mutual authentication with nonce-based challenges, ECDSA signatures, and session management.
- **Wire protocol** — binary ABI serialisation for all 28 BRC-100 methods (call codes 1-28, VarInt encoding).
- **Certificate issuance** — `acquire_certificate` with `'issuance'` protocol (POST to certifier URL).
- **OpCat template** — OP_CAT concatenation script template with lock/unlock constructors.
- **Live fee policy** — `LivePolicy` fee model fetching from ARC `/v1/policy`.

### Fixed

- Subject and certifier pinned in certificate issuance response (not overridable by remote certifier)
- Wire reader negative privileged_reason length crash
- PUSHDATA1/2/4 bounds check (silent data corruption on truncated scripts)
- Extended key path validation (reject non-numeric indices)

## [0.3.0] - 2026-03-27

### Added

#### Primitives

- **SymmetricKey** — AES-256-GCM encryption/decryption with 32-byte IV (cross-SDK compatible). Construct from random, ECDH, or raw bytes.
- **BRC-77 SignedMessage** — authenticated message signing and verification using BRC-42 derived keys. Supports targeted (specific verifier) and "anyone" modes.
- **BRC-78 EncryptedMessage** — end-to-end encrypted messaging using ECDH-derived symmetric keys.
- **Schnorr ZKP (BRC-94)** — zero-knowledge proof of ECDH shared secret knowledge. `Schnorr.generate_proof` / `Schnorr.verify_proof`.
- **Shamir's Secret Sharing** — split private keys into threshold shares (`PrivateKey#to_key_shares`) with Lagrange interpolation reconstruction. Backup format with integrity check.

#### Script

- **PushDrop template** — data carrier with P2PK spending. `Script.pushdrop_lock` / `Script.pushdrop_unlock` with field extraction.
- **RPuzzle template** — R-puzzle hash-based spending with 6 hash type variants (raw, SHA1, SHA256, RIPEMD160, HASH160, HASH256).

#### Transaction

- **Benford's law change distribution** — privacy-preserving change output splitting using Benford's first-digit distribution.
- **ARC X-WaitFor** — `ARC#broadcast` gains `wait_for:` parameter for `X-WaitFor` header (RECEIVED, STORED, ANNOUNCED_TO_NETWORK, SEEN_ON_NETWORK, MINED).

### Fixed

- Empty plaintext/ciphertext handling on older OpenSSL versions
- PushDrop detection for minimally-encoded fields

### Changed

- `Transaction#fee` change distribution uses Benford's law (was equal split)
- `LineLength` raised to 150

## [0.2.1] - 2026-03-07

### Fixed

- Truncated OP_PUSHDATA1/2/4 scripts now raise `ArgumentError` instead of crashing with `TypeError`
- `Transaction#to_beef` uses `merge_bump` to correctly handle multiple ancestors at the same block height
- `PrivateKey#derive_child` uses `BN.mod_add` instead of Integer roundtrip for modular addition
- Fixed txid byte-order documentation (display order, not internal order)

### Testing

- FORKID enforcement spec verifying interpreter rejects signatures without SIGHASH_FORKID
- ExtendedKey fingerprint chain integrity across 3-generation derivation
- Mnemonic entropy round-trip across all 5 valid entropy lengths
- BEEF spec for multiple ancestors at the same block height

## [0.2.0] - 2026-03-07

### Added

#### Primitives

- ECDH shared secret derivation (`PrivateKey#derive_shared_secret`, `PublicKey#derive_shared_secret`)
- BRC-42 key derivation (`PrivateKey#derive_child`, `PublicKey#derive_child`) with official spec test vectors

#### Transaction

- Chain tracker interface (`ChainTracker` base class) with WhatsOnChain implementation
- Fee model interface (`FeeModel` base class) with `SatoshisPerKilobyte` implementation
- `Transaction#fee` with change output distribution across multiple change outputs
- `Transaction#verify` for full SPV verification (merkle path, script execution, recursive ancestry)
- `TransactionOutput#change` flag for identifying change outputs
- `MerklePath#verify` for SPV chain tracker integration
- BEEF completion: `Beef#merge`, `Beef#valid?`, lookup methods (`find_bump`, `find_transaction_for_signing`)
- `Transaction#to_beef` / `Transaction.from_beef` convenience methods
- Extended Format (EF) transaction serialisation (`to_ef`, `to_ef_hex`, `from_ef`, `from_ef_hex`)
- `VerificationError` with typed error codes for SPV verification failures

### Changed

- ECIES refactored to use `PrivateKey#derive_shared_secret` internally (no API change)
- `Transaction#estimated_size` made public for fee model access

### Fixed

- Nil `source_satoshis` now raises instead of silently coercing to zero in fee distribution and verification
- Script chunk round-trips preserve original push encoding
- `OP_RETURN` inside conditionals correctly checked for conditional balance
- Point x-coordinate extraction preserves leading zeros via octet string
- `Integer#nobits?` replaced with Ruby 2.7-compatible bitwise check
- Defensive parsing with descriptive errors for truncated binary input

### Testing

- BRC-42 conformance specs with 9 official specification test vectors
- ECDH conformance specs (commutativity, cross-method, pinned known-key vector)
- SPV verification conformance specs (merkle path, script execution, ancestry)
- Fee model conformance specs (formula validation, default rate, change distribution)
- Chain tracker conformance specs
- BEEF cross-SDK conformance vectors
- Schnorr (BRC-94) cross-SDK interoperability vectors
- 6 exact-match RFC 6979 vectors from Trezor/CoreBitcoin
- VarInt boundary tests at size-prefix transitions
- Script vectors converted to tracked known-failures system

## [0.1.0] - 2026-02-14

Initial release of the BSV Ruby SDK.

### Added

#### Primitives

- secp256k1 elliptic curve operations (point arithmetic, scalar multiplication)
- ECDSA signing and verification with RFC 6979 deterministic nonces
- Public and private key handling (WIF import/export, compressed/uncompressed formats)
- Base58Check encoding and decoding
- Hash functions: SHA-256, RIPEMD-160, Hash160 (SHA-256 + RIPEMD-160), SHA-512, HMAC
- BIP-32 hierarchical deterministic key derivation (extended keys, hardened/normal child paths)
- BIP-39 mnemonic phrase generation and seed derivation
- ECIES encryption and decryption (BIE1 format)
- Bitcoin Signed Message (BSM) signing and verification

#### Script

- Opcode constants (full set)
- Script chunk representation and parsing
- Script serialisation and deserialisation
- Script templates: P2PKH, P2PK, P2MS (multisig), OP_RETURN data
- Script type detection (including read-only recognition of P2SH and other legacy types)
- Script builder API for programmatic construction
- Script interpreter with stack operations, arithmetic, crypto, flow control, splice, and bitwise ops

#### Transaction

- Transaction construction and serialisation (raw format)
- BIP-143 sighash computation (all hash types with FORKID)
- Transaction signing with configurable sighash flags
- BEEF serialisation (BRC-95/BRC-96)
- Merkle path representation and verification
- Fee estimation
- Script verification during signing
- Unlocking script templates for common script types

#### Network

- ARC broadcaster for transaction submission
- WhatsOnChain chain data provider
- Basic wallet functionality

#### Testing

- Cross-SDK test vectors from Go, TypeScript, and Python reference implementations
- NIST and RFC hash function test vectors
- Bitcoin Core script interpreter test suite
- Protocol conformance specs for opcodes, sighash flags, and transaction templates
