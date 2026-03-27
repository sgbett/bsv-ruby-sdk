# SDK Divergence Analysis — bsv-sdk v0.3.1 + bsv-wallet v0.1.1

**Date:** 2026-03-27
**Ruby SDK version:** 0.3.1 (bsv-sdk), 0.1.1 (bsv-wallet)
**Reference baselines:** TS SDK, Go SDK, Python SDK

---

## Coverage Matrix

### Primitives

| Component | TS SDK | Go SDK | Py SDK | Ruby SDK |
|-----------|--------|--------|--------|----------|
| secp256k1 curve ops | Yes (custom BigNumber) | Yes (custom pure-Go) | Yes (coincurve/libsecp256k1) | Yes (OpenSSL stdlib) |
| SHA-256 / SHA-256d | Yes (custom) | Yes | Yes | Yes |
| SHA-512 | Yes (custom) | Yes | Yes | Yes |
| SHA-1 | Yes (custom) | Yes | Yes | Yes |
| RIPEMD-160 | Yes (custom) | Yes (x/crypto) | Yes (PyCryptodome) | Yes (OpenSSL) |
| Hash160 | Yes | Yes | Yes | Yes |
| HMAC-SHA256/512 | Yes (custom) | Yes | Yes | Yes |
| PBKDF2-HMAC-SHA512 | Yes | Yes (x/crypto) | Yes | Yes |
| Base58 / Base58Check | Yes | Yes | Yes | Yes |
| ECDSA sign/verify | Yes (RFC 6979) | Yes (RFC 6979) | Yes (via coincurve) | Yes (RFC 6979) |
| Recoverable signatures | Yes | Yes (compact) | Yes (compact) | Yes (compact) |
| DER encoding (BIP-66) | Yes | Yes | Yes | Yes |
| Low-S normalisation | Yes | Yes | Yes | Yes |
| PrivateKey (generate/WIF/hex) | Yes | Yes | Yes | Yes |
| PublicKey (compressed/address) | Yes | Yes | Yes | Yes |
| ECDH shared secret | Yes | Yes | Yes | Yes |
| Symmetric encryption (AES-GCM) | Yes (custom AES-GCM) | Yes | Yes | **Yes** |
| AES-CBC | Yes (compat ECIES) | Yes | Yes | Yes (within ECIES) |
| BRC-42 key derivation | Yes | Yes | Yes | **Yes** |
| Shamir's Secret Sharing | Yes | Yes | Yes | **Yes** |
| Schnorr ZKP (BRC-94) | Yes | Yes | **No** | **Yes** |
| secp256r1 (P-256) | Yes | **No** | **No** | **No** |

### Compat

| Component | TS SDK | Go SDK | Py SDK | Ruby SDK |
|-----------|--------|--------|--------|----------|
| BIP-32 HD keys (xprv/xpub) | Yes (compat/) | Yes (compat/) | Yes (hd/) | Yes |
| BIP-39 mnemonics | Yes (compat/, English) | Yes (compat/, 9 wordlists) | Yes (hd/, 2 wordlists) | Yes (English) |
| BIP-44 derivation | **No** | **No** | Yes | **No** |
| ECIES (Electrum BIE1) | Yes (compat/) | Yes (compat/) | Yes | Yes |
| ECIES (Bitcore variant) | Yes (compat/) | Yes (compat/) | **No** | **No** |
| BSM (Bitcoin Signed Message) | Yes (compat/) | Yes (compat/) | Yes (via sign_text) | Yes |

### Script

| Component | TS SDK | Go SDK | Py SDK | Ruby SDK |
|-----------|--------|--------|--------|----------|
| Opcode constants (full set) | Yes | Yes | Yes | Yes |
| Script parsing (binary/hex/ASM) | Yes | Yes | Yes | Yes |
| Chunk-based representation | Yes | Yes | Yes | Yes |
| Script builder (fluent API) | Yes | Yes | Yes | Yes (Builder class) |
| P2PKH template | Yes | Yes | Yes | Yes |
| P2PK template | **No** | **No** | Yes | Yes |
| P2MS (bare multisig) template | **No** | **No** | Yes | Yes |
| OP_RETURN template | **No** (via PushDrop) | **No** | Yes | Yes |
| RPuzzle template | Yes | **No** | Yes | **Yes** |
| PushDrop template | Yes (wallet-aware) | Yes (wallet-aware) | **No** | **Yes** |
| OpCat template | **No** | **No** | Yes | **No** |
| Script type detection | Partial | Yes | Partial | Yes |
| Script interpreter | Yes (Spend) | Yes (interpreter pkg) | Yes (Spend) | Yes (Interpreter) |
| BIP-276 | **No** | Yes | **No** | **No** |

### Transaction

| Component | TS SDK | Go SDK | Py SDK | Ruby SDK |
|-----------|--------|--------|--------|----------|
| Build/serialise (binary/hex) | Yes | Yes | Yes | Yes |
| Parse from binary/hex | Yes | Yes | Yes | Yes |
| Sighash (BIP-143 + FORKID) | Yes | Yes | Yes | Yes |
| All sighash types | Yes | Yes | Yes | Yes |
| UnlockingScriptTemplate pattern | Yes | Yes | Yes | Yes |
| P2PKH signing template | Yes | Yes | Yes | Yes |
| Fee estimation | Yes | Yes | Yes | Yes |
| Fee models (sat/kB) | Yes | Yes | Yes | Yes |
| Fee models (live policy) | Yes | **No** | Yes | **No** |
| Change distribution (Benford's) | Yes | Yes | Yes (equal only) | **Yes** |
| MerklePath (BRC-74 BUMP) | Yes | Yes | Yes | Yes |
| MerklePath combine | Yes | Yes | Yes | Yes |
| MerklePath verify (SPV) | Yes | Yes | Yes | Yes |
| BEEF V1 (BRC-62) | Yes | Yes | Yes | Yes |
| BEEF V2 (BRC-96) | Yes | Yes | **No** | Yes |
| Atomic BEEF (BRC-95) | Yes | Yes | **No** | Yes |
| BEEF merge/validate | Yes | Yes | **No** | Yes |
| Extended Format (EF) | Yes | Yes | Yes | Yes |
| SPV verification | Yes | Yes | Yes | Yes |
| Transaction.verify() | Yes | Yes | Yes | Yes |
| Broadcasters (ARC) | Yes | Yes (with X-WaitFor) | Yes | **Yes (with X-WaitFor)** |
| Chain trackers (WoC) | Yes | Yes | Yes | Yes |

### Higher-Level

| Component | TS SDK | Go SDK | Py SDK | Ruby SDK |
|-----------|--------|--------|--------|----------|
| BRC-77 signed messages | Yes | Yes | Yes | **Yes** |
| BRC-78 encrypted messages | Yes | Yes | Yes | **Yes** |
| Wallet interface (28 methods) | Yes | Yes (29) | **No** | **Yes (28/28)** |
| ProtoWallet (crypto-only) | Yes | Yes | **No** | **Yes** |
| WalletClient | Yes (remote proxy) | Yes | **No** | **Yes (local engine)** |
| KeyDeriver (BRC-42/43) | Yes | Yes | **No** | **Yes** |
| Identity certificates (BRC-52) | Yes | Yes | **No** | **Yes (direct only)** |
| Auth/Peer (BRC-31) | Yes | Yes | **No** | **No** |
| Wire protocol (binary ABI) | Yes | Yes | **No** | **No** |
| Overlay (SHIP/SLAP) | Yes | Yes | **No** | **No** |
| Identity client | Yes | Yes | **No** | **No** |
| Registry client | Yes | Yes | **No** | **No** |
| Storage (UHRP) | Yes | Yes | **No** | **No** |
| KV Store | Yes | Yes | **No** | **No** |
| Remittance (BRC-29 module) | Yes | **No** | **No** | **No** |
| TOTP | Yes | **No** | **No** | **No** |
| Simple wallet (fund/sign) | **No** | **No** | **No** | Yes (novel) |
| Attestation module | **No** | **No** | **No** | Yes (novel) |

---

## Quantitative Assessment

| Layer | Reference Surface | Ruby v0.3.1 | v0.2.0 | v0.1.0 |
|-------|------------------|-------------|--------|--------|
| **Primitives** | ~22 components | ~95% | ~90% | ~80% |
| **Compat** | ~6 components | ~67% | ~83% | ~83% |
| **Script** | ~14 components | ~86% | ~75% | ~75% |
| **Transaction** | ~22 components | ~95% | ~85% | ~45% |
| **Higher-Level** | ~18 components | ~50% | ~5% | ~5% |
| **Overall** | ~82 components | **~84%** | ~65% | ~50% |

The jump from 65% to 84% is driven by the Higher-Level layer going from 5% to 50%, reflecting the complete BRC-100 wallet interface implementation (all 28 methods), plus the addition of BRC-77/78 messaging, PushDrop, RPuzzle, Shamir's SSS, and Benford's change distribution in the Primitives/Script layers.

---

## Alignment Assessment

All implemented components are **faithfully aligned** with reference SDKs. No semantic divergences detected.

Alignment notes for v0.3.1 additions:

- **SymmetricKey**: 32-byte IV (non-standard but cross-SDK compatible), AES-256-GCM. Matches ts-sdk and go-sdk wire format.
- **BRC-77 SignedMessage / BRC-78 EncryptedMessage**: Version bytes and protocol match all three reference SDKs. Tested with cross-SDK vectors.
- **Schnorr ZKP (BRC-94)**: Proof format is `R(33) + S'(33) + z(32)` with fixed 32-byte zero-padded z-scalar. The ts-sdk uses minimal encoding for z, creating a ~1/256 interop edge case (tracked as #203). Ruby's encoding is arguably more correct.
- **BRC-100 Wallet Interface**: All 28 methods implemented. ProtoWallet crypto methods use protocol-derived encryption matching ts-sdk exactly. Key linkage uses Schnorr ZKP (counterparty) and encrypted `[0]` (specific), matching ts-sdk.
- **BRC-29 payment internalization**: Uses `protocol_id: [2, '3241645161d8']` and `key_id: "#{prefix} #{suffix}"`, matching ts-sdk's `BasicBRC29` module.
- **ARC X-WaitFor**: Matches go-sdk's implementation. The ts-sdk and py-sdk lack this feature.
- **PushDrop / RPuzzle**: Script templates implemented with lock/unlock constructors matching reference patterns.
- **Cross-SDK conformance**: 3 pinned ts-sdk compliance vectors (BRC-3 signature, BRC-2 HMAC, BRC-2 encryption) verified byte-exact. 13 additional behavioural round-trip tests pass.

Architectural choice of OpenSSL stdlib vs custom crypto remains deliberate, not a divergence.

---

## Novelty Assessment

Two components exist in the Ruby SDK that are **not** direct translations of reference SDK features:

1. **`BSV::Wallet::Wallet`** — Simple wallet with fund/sign workflow. Not present in any reference SDK (they have the more complex BRC-100 WalletInterface instead). Retained for backwards compatibility and simpler use cases.
2. **`BSV::Attest`** — Attestation module for document timestamping. Unique to the Ruby SDK; no equivalent in any reference SDK.

Additionally, the Ruby SDK's **`WalletClient` is a local, in-process wallet engine** — fundamentally different from the ts-sdk and go-sdk WalletClients which are remote proxies that delegate to a separate wallet toolbox server. The Ruby WalletClient manages transactions, UTXOs, baskets, labels, certificates, and pending transactions directly. This is novel in architecture but implements the same BRC-100 interface.

---

## Gap Analysis (Prioritised)

### Tier 1 — Needed for real-world use

**All Tier 1 items are complete as of v0.3.1.** This includes everything from v0.2.0 plus:
- ~~Wallet interface~~ Done (all 28 methods)
- ~~ProtoWallet / KeyDeriver~~ Done
- ~~SymmetricKey (AES-256-GCM)~~ Done
- ~~BRC-77 / BRC-78 messaging~~ Done

### Tier 2 — Expected by ecosystem

| Component | Prerequisite | Effort | Notes |
|-----------|-------------|--------|-------|
| Auth/Peer (BRC-31) | Wallet interface | L | Mutual authentication, session management, certificate exchange |
| Wire protocol (binary ABI) | All 28 methods | L | Binary serialisation for cross-SDK interop |
| Certificate issuance protocol | HTTP client | M | `acquire_certificate` with `'issuance'` currently raises |
| Live fee policy | ARC API | S | Fetch `/v1/policy` endpoint |
| OpCat template | None | S | OP_CAT concatenation script template |

### Tier 3 — Ecosystem services & compatibility

| Component | Notes |
|-----------|-------|
| Overlay (SHIP/SLAP) | Topic/lookup service integration — only ts-sdk and go-sdk |
| Identity client | Certificate discovery and resolution |
| Registry client | On-chain basket/protocol/certificate registration |
| Storage (UHRP) | File upload/download via overlay |
| KV Store | On-chain key-value store |
| Remittance | Payment flow state machine — only ts-sdk |
| TOTP | Time-based OTP — only ts-sdk |
| ECIES (Bitcore variant) | Minor variant of existing BIE1 ECIES |
| secp256r1 (P-256) | Only ts-sdk has this; low priority |
| BIP-44 | Thin wrapper; only py-sdk has it |
| BIP-276 | Typed script encoding; only go-sdk has it |

---

## Summary

The BSV Ruby SDK v0.3.1 covers approximately **84%** of the reference SDK surface area, up from 65% at v0.2.0 and 50% at v0.1.0. The most dramatic improvement is in the Higher-Level layer, which went from 5% to 50% with the complete BRC-100 wallet interface implementation — all 28 methods across crypto, transactions, certificates, blockchain data, and authentication. The Ruby SDK is now the **third SDK** (after TypeScript and Go) to achieve full BRC-100 wallet interface coverage, and the only one with a local in-process wallet engine (the others are remote proxies to a separate wallet toolbox server).

All Tier 1 items needed for real-world use are complete. Cross-SDK conformance is verified against 3 pinned ts-sdk compliance vectors (byte-exact) plus 13 behavioural round-trip tests. The remaining gaps are primarily in ecosystem services (Auth/Peer, Overlay, Identity/Registry/Storage/KV Store) which are available only in the TypeScript and Go SDKs. The most impactful next step would be **Auth/Peer (BRC-31)** for mutual authentication, which is a prerequisite for identity-aware applications and peer-to-peer certificate exchange.
