# SDK Divergence Analysis — bsv-sdk v0.1.0

**Date:** 2026-03-05
**Ruby SDK version:** 0.1.0
**Reference baselines:** Go SDK, TS SDK v2.0.5, Python SDK v1.0.11

---

## Coverage Matrix

### Primitives

| Component | TS SDK | Go SDK | Py SDK | Ruby SDK |
|-----------|--------|--------|--------|----------|
| secp256k1 curve ops | Yes (custom BigNumber) | Yes (custom pure-Go) | Yes (coincurve/libsecp256k1) | Yes (OpenSSL stdlib) |
| SHA-256 / SHA-256d | Yes | Yes | Yes | Yes |
| SHA-512 | Yes | Yes | Yes | Yes |
| SHA-1 | Yes | Yes | Yes | Yes |
| RIPEMD-160 | Yes | Yes (x/crypto) | Yes (PyCryptodome) | Yes (OpenSSL) |
| Hash160 | Yes | Yes | Yes | Yes |
| HMAC-SHA256/512 | Yes | Yes | Yes | Yes |
| PBKDF2-HMAC-SHA512 | Yes | Yes (x/crypto) | Yes | Yes |
| Base58 / Base58Check | Yes | Yes | Yes | Yes |
| ECDSA sign/verify | Yes (RFC 6979) | Yes (RFC 6979) | Yes (via coincurve) | Yes (RFC 6979) |
| Recoverable signatures | Yes | Yes (compact) | Yes (compact) | Yes (compact) |
| DER encoding (BIP-66) | Yes | Yes | Yes | Yes |
| Low-S normalisation | Yes | Yes | Yes | Yes |
| PrivateKey (generate/WIF/hex) | Yes | Yes | Yes | Yes |
| PublicKey (compressed/address) | Yes | Yes | Yes | Yes |
| ECDH shared secret | Yes | Yes | Yes | **No** |
| Symmetric encryption (AES-GCM) | Yes (AES-256-GCM) | Yes (AES-GCM) | Yes (AES-GCM for BRC-78) | **No** |
| AES-CBC | Yes (compat ECIES) | Yes | Yes | Yes (within ECIES only) |
| BRC-42 key derivation | Yes | Yes | Yes | **No** |
| Shamir's Secret Sharing | Yes | Yes | Yes | **No** |
| Schnorr ZKP (BRC-94) | Yes | Yes | **No** | Yes |
| secp256r1 (P-256) | Yes | **No** | **No** | **No** |

### Compat

| Component | TS SDK | Go SDK | Py SDK | Ruby SDK |
|-----------|--------|--------|--------|----------|
| BIP-32 HD keys (xprv/xpub) | Yes (compat/) | Yes (compat/) | Yes (hd/) | Yes |
| BIP-39 mnemonics | Yes (compat/) | Yes (compat/, 9 wordlists) | Yes (hd/, 2 wordlists) | Yes (English only) |
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
| RPuzzle template | Yes | **No** | Yes | **No** |
| PushDrop template | Yes (wallet-aware) | Yes (wallet-aware) | **No** | **No** |
| OpCat template | **No** | **No** | Yes | **No** |
| Script type detection | Partial | Yes | Partial | Yes |
| Script interpreter | Yes (Spend) | Yes (interpreter pkg) | Yes (Spend) | Yes (Interpreter) |
| Post-Genesis opcodes | Yes | Yes | Yes | Yes |

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
| Change distribution (Benford's law) | Yes | Yes | Yes | **No** |
| MerklePath (BRC-74 BUMP) | Yes | Yes | Yes | Yes |
| MerklePath combine | Yes | Yes | Yes | Yes |
| BEEF V1 (BRC-62) | Yes | Yes | Yes | Partial |
| BEEF V2 (BRC-96) | Yes | Yes | **No** | Partial |
| Atomic BEEF (BRC-95) | Yes | Yes | **No** | Partial |
| Extended Format (EF) | Yes | Yes | Yes | **No** |
| SPV verification | Yes | Yes | Yes | **No** |
| Broadcasters (ARC) | Yes | Yes | Yes | Yes |
| Broadcasters (WhatsOnChain) | Yes | Yes | Yes | Yes |
| Chain trackers | Yes | Yes | Yes | **No** |
| Fee models (sat/kB) | Yes | Yes | Yes | Partial |
| Fee models (live policy) | Yes | **No** | Yes | **No** |
| Transaction.verify() | Yes | Yes | Yes | Partial (single input) |
| BEEF merge/validate | Yes | Yes | **No** | **No** |

### Higher-Level

| Component | TS SDK | Go SDK | Py SDK | Ruby SDK |
|-----------|--------|--------|--------|----------|
| BRC-77 signed messages | Yes | Yes | Yes | **No** |
| BRC-78 encrypted messages | Yes | Yes | Yes | **No** |
| Wallet interface (29 methods) | Yes | Yes | **No** | **No** |
| ProtoWallet (crypto-only) | Yes | Yes | **No** | **No** |
| KeyDeriver (BRC-42/43) | Yes | Yes | **No** | **No** |
| Auth/Peer (BRC-31) | Yes | Yes | **No** | **No** |
| Overlay (SHIP/SLAP) | Yes | Yes | **No** | **No** |
| Simple wallet (fund/sign) | **No** | **No** | **No** | Yes (novel) |
| Attestation module | **No** | **No** | **No** | Yes (novel) |

---

## Quantitative Assessment

| Layer | Reference Surface | Ruby SDK Coverage |
|-------|------------------|-------------------|
| **Primitives** | ~20 components | ~80% |
| **Compat** | ~6 components | ~83% |
| **Script** | ~12 components | ~75% |
| **Transaction** | ~20 components | ~45% |
| **Higher-Level** | ~15 components | ~5% |
| **Overall** | ~73 components | **~50%** |

---

## Alignment Assessment

All implemented components are **faithfully aligned** with reference SDKs. No semantic divergences detected. API shape differences are idiomatic Ruby conventions (snake_case, etc.). Architectural choice of OpenSSL stdlib vs custom crypto is deliberate, not a divergence.

---

## Gap Analysis (Prioritised)

### Tier 1 — Needed for real-world use
- BEEF full serialisation (BRC-62/95/96)
- Extended Format (EF)
- SPV verification
- Chain tracker interface + WoC implementation
- Fee model interface + sat/kB implementation
- ECDH (standalone, prerequisite for BRC-42 chain)
- BRC-42 key derivation

### Tier 2 — Expected by ecosystem
- BRC-77/78 signed/encrypted messages
- SymmetricKey (AES-256-GCM)
- Shamir's Secret Sharing
- PushDrop template
- RPuzzle template
- WalletInterface / ProtoWallet
- Change distribution (Benford's law)

### Tier 3 — Compatibility & advanced
- Auth/Peer (BRC-31), Certificates
- Overlay tools (SHIP/SLAP)
- Identity, Registry, Storage clients

---

## x402 Protocol Impact Assessment

A BSV x402 middleware gem is **mostly buildable** with the current SDK. The core protocol flow (challenge/proof/verify/settle) requires transaction parsing, output inspection, hashing, and broadcasting — all implemented.

Gaps that affect x402:
- **EF serialisation** — ARC preferred submission format for settlement
- **BEEF serialisation** — SPV-ready proof bundles in settlement responses

ECDH/BRC-42 are **not required** for x402 (uses transaction-level payment, not key-derived encryption).

### Recommended development order (accounting for x402)
1. EF serialisation (small, unblocks ARC + x402 settle)
2. BEEF full serialisation (SPV proofs, general completeness)
3. Chain tracker interface (needed for SPV verify)
4. Fee model interface (pluggable fee calculation)
5. SPV verification (full Transaction.verify)
6. ECDH (unlocks BRC-42 chain)
7. x402 gem (buildable after items 1-2, enhanced by 3-5)
