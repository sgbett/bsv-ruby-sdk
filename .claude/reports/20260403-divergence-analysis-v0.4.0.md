# SDK Divergence Analysis — bsv-sdk v0.4.0 + bsv-wallet v0.2.0

**Date:** 2026-04-03
**Ruby SDK version:** 0.4.0 (bsv-sdk), 0.2.0 (bsv-wallet)
**Reference baselines:** TS SDK, Go SDK, Python SDK

---

## Coverage Matrix

### Primitives

| Component | TS SDK | Go SDK | Py SDK | Ruby SDK |
|-----------|--------|--------|--------|----------|
| secp256k1 curve ops | Yes (custom BigNumber) | Yes (custom pure-Go) | Yes (coincurve/libsecp256k1) | Yes (OpenSSL stdlib) |
| SHA-256 / SHA-256d | Yes (custom) | Yes | Yes | Yes |
| SHA-512 | Yes (custom) | Yes | Yes | Yes |
| SHA-1 | Yes (custom) | **No** | Yes | Yes |
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
| Symmetric encryption (AES-GCM) | Yes (custom AES-GCM) | Yes | Yes | Yes |
| AES-CBC | Yes (compat ECIES) | Yes | Yes | Yes (within ECIES) |
| BRC-42 key derivation | Yes | Yes | Yes | Yes |
| Shamir's Secret Sharing | Yes | Yes | Yes | Yes |
| Schnorr ZKP (BRC-94) | Yes | Yes | **No** | Yes |
| secp256r1 (P-256) | Yes | **No** | **No** | **No** |

### Compat

| Component | TS SDK | Go SDK | Py SDK | Ruby SDK |
|-----------|--------|--------|--------|----------|
| BIP-32 HD keys (xprv/xpub) | Yes (compat/, deprecated) | Yes (compat/) | Yes (hd/) | Yes |
| BIP-39 mnemonics | Yes (English) | Yes (9 wordlists) | Yes (English, Chinese) | Yes (English) |
| BIP-44 derivation | **No** | **No** | Yes | **No** |
| ECIES (Electrum BIE1) | Yes (compat/) | Yes (compat/) | Yes | Yes |
| ECIES (Bitcore variant) | Yes (compat/) | Yes (compat/) | **No** | Yes |
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
| RPuzzle template | Yes | **No** | Yes | Yes |
| PushDrop template | Yes (wallet-aware) | Yes (wallet-aware) | **No** | Yes |
| OpCat template | **No** | **No** | Yes | Yes |
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
| Fee models (live policy) | Yes | **No** | Yes | Yes |
| Change distribution (Benford's) | Yes | Yes | Yes (equal only) | Yes |
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
| Broadcasters (ARC) | Yes | Yes (with X-WaitFor) | Yes | Yes (with X-WaitFor) |
| Chain trackers (WoC) | Yes | Yes | Yes | Yes |

### Higher-Level

| Component | TS SDK | Go SDK | Py SDK | Ruby SDK |
|-----------|--------|--------|--------|----------|
| BRC-77 signed messages | Yes | Yes | Yes | Yes |
| BRC-78 encrypted messages | Yes | Yes | Yes | Yes |
| Wallet interface (28+ methods) | Yes | Yes (29) | **No** | Yes (28/28) |
| ProtoWallet (crypto-only) | Yes | Yes | **No** | Yes |
| WalletClient | Yes (remote proxy) | Yes (remote proxy) | **No** | Yes (local engine) |
| KeyDeriver (BRC-42/43) | Yes | Yes | **No** | Yes |
| Identity certificates (BRC-52) | Yes | Yes | **No** | Yes (direct only) |
| Auth/Peer (BRC-31) | Yes | Yes | **No** | Yes |
| Wire protocol (binary ABI) | Yes | Yes | **No** | Yes |
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

| Layer | Reference Surface | Ruby v0.4.0 | v0.3.1 | v0.2.0 | v0.1.0 |
|-------|------------------|-------------|--------|--------|--------|
| **Primitives** | ~22 components | ~95% | ~95% | ~90% | ~80% |
| **Compat** | ~6 components | ~83% | ~67% | ~83% | ~83% |
| **Script** | ~14 components | ~86% | ~86% | ~75% | ~75% |
| **Transaction** | ~22 components | ~95% | ~95% | ~85% | ~45% |
| **Higher-Level** | ~18 components | ~67% | ~50% | ~5% | ~5% |
| **Overall** | ~82 components | **~88%** | ~84% | ~65% | ~50% |

The jump from 84% to 88% reflects the completion of all five Tier 2 items from the v0.3.1 gap analysis: Auth/Peer (BRC-31), wire protocol, certificate issuance, live fee policy, OpCat template, and Bitcore ECIES. The Compat layer recovered from 67% to 83% with the addition of Bitcore ECIES.

---

## Alignment Assessment

All implemented components remain **faithfully aligned** with reference SDKs. No semantic divergences detected.

Alignment notes for v0.4.0 additions:

- **Auth/Peer (BRC-31)**: Implements mutual authentication with nonce-based handshake, session management, and certificate exchange. Matches the ts-sdk and go-sdk `Peer` class semantics. Protocol version "0.1" aligns with reference implementations.
- **Wire protocol (binary ABI)**: `BSV::Wallet::Wire::Serializer` and `Reader`/`Writer` implement the BRC-100 binary serialisation for all 28+ wallet methods. Frame encoding matches ts-sdk's `WalletWireTransceiver` and go-sdk's `wallet/serializer/`.
- **Certificate issuance**: `acquire_certificate` with `'issuance'` acquisition type now functional. Direct issuance (certifier signs locally) matches reference pattern.
- **LivePolicy fee model**: Fetches from ARC `/v1/policy` endpoint. Matches ts-sdk's `LivePolicy` and py-sdk's `live_policy.py`.
- **OpCat template**: Lock/unlock constructors for `OP_CAT <expected> OP_EQUAL` pattern. Matches py-sdk's OpCat template.
- **Bitcore ECIES**: AES-256-CBC variant with random IV, no BIE1 magic bytes. Matches ts-sdk and go-sdk `compat/ecies` Bitcore mode.
- **FileStore**: JSON-based persistent storage with 0700/0600 permissions. Novel implementation detail but serves the same role as ts-sdk's substrate-backed storage.
- **Schnorr z-scalar**: Fixed 32-byte encoding (matching go-sdk). ts-sdk uses minimal encoding — tracked as [ts-sdk#508](https://github.com/bsv-blockchain/ts-sdk/issues/508).

Architectural choice of OpenSSL stdlib vs custom crypto remains deliberate, not a divergence.

---

## Novelty Assessment

Three components exist in the Ruby SDK that are **not** direct translations of reference SDK features:

1. **`BSV::Wallet::Wallet`** — Simple wallet with fund/sign workflow. Not present in any reference SDK (they have the more complex BRC-100 WalletInterface instead). Retained for backwards compatibility and simpler use cases.
2. **`BSV::Attest`** — Attestation module for document timestamping. Unique to the Ruby SDK; no equivalent in any reference SDK.
3. **`BSV::Wallet::WalletClient` as local engine** — The Ruby WalletClient manages transactions, UTXOs, baskets, labels, certificates, and pending transactions directly in-process. The ts-sdk and go-sdk WalletClients are remote proxies that delegate to a separate wallet toolbox server. Same BRC-100 interface, fundamentally different architecture.

Additionally, the Ruby SDK has broader **script template coverage** than any single reference SDK. It is the only SDK implementing all seven template types (P2PKH, P2PK, P2MS, OP_RETURN, RPuzzle, PushDrop, OpCat). The ts-sdk has P2PKH/RPuzzle/PushDrop; py-sdk has P2PKH/P2PK/P2MS/OP_RETURN/RPuzzle/OpCat; go-sdk has P2PKH/PushDrop.

---

## Gap Analysis (Prioritised)

### Tier 1 — Needed for real-world use

**All Tier 1 items are complete as of v0.3.1.** No regressions.

### Tier 2 — Expected by ecosystem

**All Tier 2 items from v0.3.1 are now complete.** New Tier 2 items:

| Component | Prerequisite | Effort | Notes |
|-----------|-------------|--------|-------|
| Overlay (SHIP/SLAP) | Auth/Peer, Wire | L | Topic-based transaction broadcasting, host reputation, STEAK acknowledgements. Both ts-sdk and go-sdk have this. |
| Identity client | Overlay, Certificates | M | Resolve identity keys, publish verified attributes. Requires overlay lookup. |
| Registry client | Overlay | M | On-chain protocol/basket/certificate-type registration via PushDrop. |

### Tier 3 — Ecosystem services & compatibility

| Component | Notes |
|-----------|-------|
| Storage (UHRP) | File upload/download via overlay — only ts-sdk and go-sdk |
| KV Store | PushDrop-backed distributed key-value store — only ts-sdk and go-sdk |
| Remittance (BRC-29) | Payment flow state machine — only ts-sdk |
| TOTP | Time-based OTP — only ts-sdk |
| secp256r1 (P-256) | Alternative curve — only ts-sdk |
| BIP-44 | Thin wrapper over BIP-32 — only py-sdk |
| BIP-276 | Typed script encoding — only go-sdk |
| BIP-39 additional wordlists | Go has 9, Ruby has English only — low priority |

---

## Summary

The BSV Ruby SDK v0.4.0 covers approximately **88%** of the reference SDK surface area, up from 84% at v0.3.1. The entire Tier 2 backlog from the previous analysis has been cleared — Auth/Peer (BRC-31), wire protocol, certificate issuance, live fee policy, OpCat template, and Bitcore ECIES are all shipped. The Ruby SDK now matches or exceeds the Go SDK in every layer except overlay services, and is the **third SDK** (after TypeScript and Go) to implement BRC-31 mutual authentication.

The remaining gaps are concentrated in **ecosystem services**: Overlay (SHIP/SLAP), Identity client, Registry client, Storage (UHRP), and KV Store. These are available only in the TypeScript and Go SDKs and represent the networking/discovery layer that sits above the declarative SDK. The most impactful next step would be **Overlay (SHIP/SLAP)** — it's the prerequisite for Identity, Registry, Storage, and KV Store, so it unlocks the entire remaining gap in one go.
