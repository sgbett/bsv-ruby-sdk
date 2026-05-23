# SDK Divergence Analysis — bsv-sdk v0.1.0

**Date:** 2026-02-14
**Ruby SDK version:** 0.1.0
**Reference baselines:** Go v1.2.18 (`725db51`), TS v2.0.0 (`8acc706`), Python v1.0.10 (`f505ea5`)

---

## Coverage Matrix

### Primitives

| Component | TS SDK | Go SDK | Py SDK | Ruby SDK |
|-----------|--------|--------|--------|----------|
| secp256k1 curve ops | Yes (custom BigNumber) | Yes (custom KoblitzCurve) | Yes (coincurve/libsecp256k1) | Yes (OpenSSL) |
| ECDSA signing (RFC 6979) | Yes (custom DRBG) | Yes | Yes (via coincurve) | Yes (custom implementation) |
| ECDSA recoverable signatures | Yes | Yes (SignCompact) | Yes | Yes (sign_recoverable) |
| Private key (WIF, hex, bytes) | Yes | Yes | Yes | Yes |
| Public key (compressed/uncompressed) | Yes | Yes | Yes | Yes |
| Signature (DER, low-S) | Yes | Yes | Yes | Yes (BIP-66 strict) |
| SHA-256 / SHA-512 | Yes (custom) | Yes | Yes (hashlib) | Yes (OpenSSL) |
| RIPEMD-160 | Yes (custom) | Yes | Yes (pycryptodome) | Yes (OpenSSL) |
| Hash160 (SHA-256 + RIPEMD-160) | Yes | Yes | Yes | Yes |
| SHA-256d (double SHA-256) | Yes | Yes | Yes | Yes |
| SHA-1 | Yes | No | Yes | Yes |
| HMAC-SHA256 / HMAC-SHA512 | Yes | Yes | Yes | Yes |
| PBKDF2-HMAC-SHA512 | Yes | Yes (via BIP-39) | Yes | Yes |
| Base58Check | Yes | Yes (compat) | Yes | Yes |
| AES-CBC | Yes (via ECIES) | Yes (aescbc pkg) | Yes (aes_cbc module) | Partial (internal to ECIES only) |
| AES-GCM | Yes (SymmetricKey) | Yes (aesgcm pkg) | Yes (encrypted messages) | No |
| Symmetric key class | Yes (SymmetricKey) | Yes (ec.SymmetricKey) | No | No |
| DRBG (standalone) | Yes | Yes | No (via coincurve) | No (embedded in RFC 6979) |
| Key shares / Polynomial (Shamir) | Yes | Yes (keyshares) | Yes (polynomial) | No |
| Schnorr ZKP (BRC-94) | Yes | Yes | No | Yes |
| ECDH (shared secret) | Yes (PrivateKey.ecs) | Yes (Point.Mul) | Yes (derive_shared_secret) | Partial (internal to ECIES/Schnorr) |
| BRC-42 key derivation | Yes (KeyDeriver) | Yes (KeyDeriver) | Yes (derive_child) | No |
| P-256 / secp256r1 | Yes (Secp256r1) | No | No | No |

### Compat / HD Keys

| Component | TS SDK | Go SDK | Py SDK | Ruby SDK |
|-----------|--------|--------|--------|----------|
| BIP-32 (extended keys, xprv/xpub) | Yes (compat, deprecated) | Yes (compat) | Yes (hd/bip32) | Yes |
| BIP-39 (mnemonics) | Yes (compat) | Yes (compat, multi-language) | Yes (en, zh-CN) | Yes (en) |
| BIP-44 (derivation paths) | No | No | Yes (hd/bip44) | No |
| ECIES (BIE1, Electrum) | Yes (compat) | Yes (compat) | Yes (PrivateKey.encrypt/decrypt) | Yes |
| BSM (Bitcoin Signed Message) | Yes (compat, deprecated) | Yes (compat) | Yes (sign_text/verify) | Yes |

### Script

| Component | TS SDK | Go SDK | Py SDK | Ruby SDK |
|-----------|--------|--------|--------|----------|
| Opcodes (full set) | Yes | Yes (150+) | Yes (144) | Yes |
| Script chunks / parsing | Yes (ScriptChunk) | Yes (ScriptChunk) | Yes (ScriptChunk) | Yes (Chunk) |
| Script from ASM / hex / binary | Yes | Yes | Yes | Yes |
| Script builder API | Yes (append methods) | Yes (Append methods) | Yes (from_chunks) | Yes (Builder) |
| LockingScript / UnlockingScript types | Yes (separate classes) | No (single Script) | No (single Script) | No (single Script) |
| P2PKH template | Yes | Yes | Yes | Yes |
| P2PK template | No explicit | Yes (detection) | Yes | Yes |
| P2MS (bare multisig) template | No explicit | Yes (detection) | Yes (BareMultisig) | Yes |
| OP_RETURN template | Yes (via Transaction) | Yes (via Transaction) | Yes (OpReturn) | Yes |
| PushDrop template | Yes | Yes | No | No |
| RPuzzle template | Yes | No | Yes | No |
| OpCat template | No | No | Yes | No |
| BIP-276 (script encoding) | No | Yes | No | No |
| Inscriptions | No | Yes | No | No |
| Script type detection | Yes (via chunk patterns) | Yes (IsP2PKH, etc.) | No explicit | Yes (p2pkh?, p2pk?, etc.) |
| P2SH detection (read-only) | No | Yes (IsP2SH) | No | Yes |
| Script interpreter | Yes (Spend) | Yes (Engine) | Yes (Spend) | Yes (Interpreter) |
| Interpreter: post-Genesis rules | Yes | Yes | Yes | Yes |
| Address generation | Yes (PublicKey.toAddress) | Yes (address pkg) | Yes (PrivateKey.address) | Yes (PublicKey.address) |

### Transaction

| Component | TS SDK | Go SDK | Py SDK | Ruby SDK |
|-----------|--------|--------|--------|----------|
| Transaction build / serialise | Yes | Yes | Yes | Yes |
| BIP-143 sighash (FORKID) | Yes | Yes | Yes | Yes |
| All sighash types (ALL/NONE/SINGLE + ACP) | Yes + CHRONICLE | Yes | Yes | Yes |
| Transaction signing | Yes | Yes | Yes | Yes |
| Unlocking script templates | Yes (P2PKH, RPuzzle, PushDrop) | Yes (P2PKH, PushDrop) | Yes (P2PKH, P2PK, RPuzzle, etc.) | Yes (P2PKH) |
| BEEF V1 (BRC-62) | Yes | Yes | Yes | Yes |
| BEEF V2 (BRC-96) | Yes | Yes | No | Yes |
| Atomic BEEF (BRC-95) | Yes | Yes | No | Yes |
| EF (Extended Format) | No | Yes | Yes | No |
| MerklePath / BUMP (BRC-74) | Yes | Yes | Yes | Yes |
| BeefParty | Yes | No | No | No |
| Fee model interface | Yes (FeeModel) | Yes (SatsPerKb) | Yes (FeeModel ABC) | No (method only) |
| SatoshisPerKilobyte fee model | Yes | Yes | Yes | No |
| LivePolicy fee model | Yes | No | Yes | No |
| Broadcaster interface | Yes | Yes | Yes (ABC) | No (duck-typed) |
| ARC broadcaster | Yes | Yes | Yes | Yes (concrete) |
| WhatsOnChain broadcaster | Yes | Yes | Yes | Yes (concrete) |
| Teranode broadcaster | Yes | No | No | No |
| ChainTracker interface | Yes | Yes | Yes (ABC) | No |
| WhatsOnChain chain tracker | Yes | Yes | Yes | No |
| SPV verification (via ChainTracker) | Yes | Yes (spv pkg) | Yes | No |
| Transaction verify (script execution) | Yes | Yes | Yes | Yes |
| VarInt encoding | Yes | Yes | Yes | Yes |

### Higher-Level Modules

| Component | TS SDK | Go SDK | Py SDK | Ruby SDK |
|-----------|--------|--------|--------|----------|
| ProtoWallet (crypto-only wallet) | Yes | Yes | No | No |
| WalletClient (full wallet protocol) | Yes (multi-substrate) | Yes (Interface) | No | No |
| Wallet (basic fund/sign) | No (higher-level) | No (higher-level) | No | Yes |
| KeyDeriver (BRC-42/43) | Yes | Yes | Yes (derive_child) | No |
| CachedKeyDeriver | Yes | Yes | No | No |
| Auth / Peer (BRC-104) | Yes (Peer, SessionManager) | Yes | No | No |
| Certificates (auth) | Yes | Yes | No | No |
| Auth transports (HTTP, WS) | Yes | Yes | No | No |
| Identity client | Yes | Yes | No | No |
| Contacts manager | Yes | No | No | No |
| Registry client | Yes | Yes | No | No |
| Overlay tools (SHIP, SLAP) | Yes | Yes | No | No |
| Signed messages (BRC-77) | Yes | Yes | Yes | No |
| Encrypted messages (BRC-78) | Yes | Yes | Yes | No |
| Storage (upload/download) | Yes (UHRP) | Yes | No | No |
| KV store | Yes | Yes | No | No |
| TOTP | Yes | No | No | No |
| Remittance | Yes | No | No | No |
| Block header type | No | Yes | No | No |
| HTTP client abstraction | Yes (multi-platform) | No | Yes (async) | No |

---

## Quantitative Assessment

| Layer | Components (union) | Ruby coverage | Estimate |
|-------|-------------------|---------------|----------|
| **Primitives** | 24 | 17 | **71%** |
| **Compat / HD** | 5 | 4 | **80%** |
| **Script** | 17 | 12 | **71%** |
| **Transaction** | 22 | 13 | **59%** |
| **Higher-level** | 21 | 1 | **5%** |
| **Overall** | **89** | **47** | **53%** |

**By architectural layer (weighted):**

The declarative core (primitives + script + transaction) accounts for ~68 components across all SDKs. Ruby covers 42 of those — approximately **62%** of the declarative surface area.

The imperative/higher-level layer accounts for ~21 components. Ruby covers 1 (basic Wallet) — approximately **5%**. This is consistent with the SDK's stated philosophy of deferring imperative features.

---

## Alignment Assessment

For components the Ruby SDK implements, alignment with reference SDKs is **strong**:

| Component | Alignment | Notes |
|-----------|-----------|-------|
| ECDSA (RFC 6979) | Faithful | Custom implementation, tested against Go/TS cross-SDK vectors |
| BIP-32 | Faithful | Tested against BIP-32 test vectors |
| BIP-39 | Faithful | Tested against BIP-39 test vectors, English wordlist only |
| BIP-143 sighash | Faithful | Tested against Go/TS sighash vectors |
| BEEF (V1/V2/Atomic) | Faithful | Tested against Go SDK BEEF vectors |
| MerklePath | Faithful | Tested against Go SDK BUMP vectors |
| Script interpreter | Faithful | Tested against Bitcoin Core script test suite (script_tests.json) |
| ECIES (BIE1) | Faithful | Tested against cross-SDK encryption vectors |
| BSM | Faithful | Tested against cross-SDK message signing vectors |
| Schnorr ZKP | Faithful | BRC-94 compliant, tested against Go SDK vectors |
| Base58Check | Faithful | Standard implementation, tested against known addresses |
| P2PKH template | Faithful | Lock/unlock match reference SDK patterns |
| DER signatures | Faithful | Strict BIP-66 validation, BIP-62 low-S normalisation |

**API shape differences (non-divergences, Ruby idioms):**

- Ruby uses `snake_case` method names vs. `camelCase` / `PascalCase` in other SDKs
- Ruby uses single `Script` class where TS SDK separates `LockingScript`/`UnlockingScript`
- Ruby uses duck-typed providers (Network module) rather than formal interface/ABC
- Ruby relies on OpenSSL for curve operations; all other SDKs use custom or libsecp256k1

**No semantic divergences detected.** Where implemented, the Ruby SDK faithfully reproduces reference SDK behaviour and passes cross-SDK test vectors.

---

## Novelty Assessment

The Ruby SDK is primarily a **faithful translation** of reference SDK capabilities. Notable differences:

| Item | Description |
|------|-------------|
| **OpenSSL curve backend** | Only SDK to use stdlib OpenSSL for secp256k1 — all others use custom implementations or libsecp256k1 bindings. This is an architectural choice (documented in ADR), not a divergence. |
| **BSV::Attest module** | Scaffolded module for document attestation. Not present in any reference SDK. Currently a stub. |
| **Ruby 3.3 minimum** | Floor raised from 2.7 to 3.3 (branch `feat/754-ruby-3.3-minimum`). Ruby 3.0+ features (pattern matching, `Hash#except`, `Data.define`) are now available. No longer an unusual backwards-compatibility divergence from the other SDKs. |
| **Script type detection** | More comprehensive type detection predicates (`p2pkh?`, `p2pk?`, `p2sh?`, `multisig?`, `op_return?`) than Go or TS SDKs. Python has template-based detection instead. |
| **P2SH read-only detection** | Explicit "recognise but don't construct" pattern for P2SH — documented philosophy not formally adopted by other SDKs (they simply omit P2SH). |

**No novel algorithms or protocol extensions.** The SDK implements established Bitcoin/BSV standards only.

---

## Gap Analysis (Prioritised)

### Tier 1 — Needed for Real-World Use

These gaps prevent the SDK from being used in production applications that interact with the network.

| Gap | Present in | Impact |
|-----|-----------|--------|
| **Fee model interface** (SatoshisPerKilobyte) | Go, TS, Py | Cannot calculate standard fees; current `estimated_fee` is a method, not a pluggable model |
| **ChainTracker interface** | Go, TS, Py | Cannot verify merkle proofs against the chain |
| **SPV verification** | Go, TS, Py | MerklePath exists but cannot verify against block headers |
| **Broadcaster interface** (formal) | Go, TS, Py | ARC/WoC exist but as concrete classes, not pluggable contracts |
| **BRC-42 key derivation** | Go, TS, Py | Foundation for BRC-77/78 messages, wallet operations, and PushDrop |
| **AES-GCM encryption** | Go, TS, Py | Required by BRC-78 encrypted messages |

### Tier 2 — Expected by the Ecosystem

These are capabilities that applications and companion gems will need.

| Gap | Present in | Impact |
|-----|-----------|--------|
| **Signed messages (BRC-77)** | Go, TS, Py | Modern replacement for BSM; privacy-preserving message signing |
| **Encrypted messages (BRC-78)** | Go, TS, Py | End-to-end encryption between peers using BRC-42 derived keys |
| **PushDrop template** | Go, TS | Primary data-carrying script template for overlay networks |
| **ECDH as standalone** | Go, TS, Py | Shared secret derivation exposed as public API (currently internal) |
| **Key shares / Polynomial (Shamir)** | Go, TS, Py | Threshold key splitting for backup and multi-party operations |
| **EF (Extended Format)** | Go, Py | Alternative to BEEF for transaction serialisation with input data |
| **HTTP client abstraction** | TS, Py | Pluggable HTTP layer for testing and platform portability |

### Tier 3 — Completeness / Compatibility

These round out the SDK but are not blockers for most use cases.

| Gap | Present in | Impact |
|-----|-----------|--------|
| **RPuzzle template** | TS, Py | Hash-puzzle script template; niche but useful for atomic swaps |
| **BIP-44 derivation paths** | Py | Standardised HD wallet paths (m/44'/236'/0') |
| **BIP-276 script encoding** | Go | Script encoding standard; limited adoption |
| **Inscriptions** | Go | Ordinal-style data embedding |
| **OpCat template** | Py | OP_CAT concatenation puzzle |
| **LivePolicy fee model** | TS, Py | Dynamic fee rate from ARC policy endpoint |
| **Multi-language BIP-39 wordlists** | Go (8 languages) | English-only is sufficient for most use cases |

### Tier 4 — Higher-Level (Deferred by Design)

These are explicitly outside the SDK's declarative scope per its architectural principles. They belong in companion gems.

| Gap | Present in | Notes |
|-----|-----------|-------|
| ProtoWallet / WalletClient | Go, TS | Full wallet protocol with actions, certificates, discovery |
| Auth / BRC-104 | Go, TS | Peer authentication, session management, transports |
| Identity client | Go, TS | Identity discovery and certificate management |
| Registry client | Go, TS | On-chain registry for baskets, protocols, certificates |
| Overlay tools (SHIP/SLAP) | Go, TS | Overlay network broadcasting and lookup |
| Storage (UHRP) | Go, TS | File upload/download to decentralised storage |
| KV store | Go, TS | Key-value persistence abstraction |
| Remittance | TS | Payment flow management (TS-only) |
| TOTP | TS | Time-based one-time passwords (TS-only) |
| Contacts manager | TS | Local contact management (TS-only) |

---

## Summary

The BSV Ruby SDK at v0.1.0 covers **approximately 53% of the union surface area** across all reference SDKs, with strong coverage of the declarative core (**62%** of primitives + script + transaction) and minimal coverage of higher-level modules (**5%**, by design).

Where implemented, the Ruby SDK is **faithfully aligned** with the reference SDKs — all major components pass cross-SDK test vectors, and no semantic divergences were found. The architectural choice of OpenSSL over custom curve implementations is documented and intentional.

The most impactful next steps for the Ruby SDK, in priority order:

1. **BRC-42 key derivation** — unlocks BRC-77/78 messages, PushDrop, and the entire wallet/auth layer
2. **Fee model + ChainTracker + Broadcaster interfaces** — formal contracts for pluggable network interaction
3. **AES-GCM + Signed/Encrypted messages** — modern message protocol (BRC-77/78)
4. **PushDrop template** — essential for overlay network data
5. **Key shares (Shamir)** — threshold key management

These five items would bring the declarative core to approximately **85%** coverage and lay the groundwork for companion gems to build the imperative layer.
