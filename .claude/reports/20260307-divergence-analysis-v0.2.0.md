# SDK Divergence Analysis — bsv-sdk v0.2.0

**Date:** 2026-03-07
**Ruby SDK version:** 0.2.0
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
| ECDH shared secret | Yes | Yes | Yes | **Yes** |
| Symmetric encryption (AES-GCM) | Yes (AES-256-GCM) | Yes (AES-GCM) | Yes (AES-GCM for BRC-78) | **No** |
| AES-CBC | Yes (compat ECIES) | Yes | Yes | Yes (within ECIES only) |
| BRC-42 key derivation | Yes | Yes | Yes | **Yes** |
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
| Fee models (sat/kB) | Yes | Yes | Yes | **Yes** |
| Fee models (live policy) | Yes | **No** | Yes | **No** |
| Change distribution | Yes (Benford's law) | Yes (Benford's law) | Yes | **Yes** (equal split) |
| MerklePath (BRC-74 BUMP) | Yes | Yes | Yes | Yes |
| MerklePath combine | Yes | Yes | Yes | Yes |
| MerklePath verify (SPV) | Yes | Yes | Yes | **Yes** |
| BEEF V1 (BRC-62) | Yes | Yes | Yes | **Yes** |
| BEEF V2 (BRC-96) | Yes | Yes | **No** | **Yes** |
| Atomic BEEF (BRC-95) | Yes | Yes | **No** | **Yes** |
| BEEF merge/validate | Yes | Yes | **No** | **Yes** |
| Extended Format (EF) | Yes | Yes | Yes | **Yes** |
| SPV verification | Yes | Yes | Yes | **Yes** |
| Transaction.verify() | Yes | Yes | Yes | **Yes** |
| Broadcasters (ARC) | Yes | Yes | Yes | Yes |
| Chain trackers (WoC) | Yes | Yes | Yes | **Yes** |

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

| Layer | Reference Surface | Ruby SDK Coverage | v0.1.0 |
|-------|------------------|-------------------|--------|
| **Primitives** | ~20 components | ~90% | ~80% |
| **Compat** | ~6 components | ~83% | ~83% |
| **Script** | ~12 components | ~75% | ~75% |
| **Transaction** | ~20 components | ~85% | ~45% |
| **Higher-Level** | ~15 components | ~5% | ~5% |
| **Overall** | ~73 components | **~65%** | ~50% |

The jump from 50% to 65% is driven primarily by the Transaction layer going from 45% to 85%, reflecting the completion of all Tier 1 items: BEEF (full), EF, SPV verification, chain trackers, fee models, ECDH, and BRC-42.

---

## Alignment Assessment

All implemented components are **faithfully aligned** with reference SDKs. No semantic divergences detected.

Specific alignment notes for v0.2.0 additions:

- **ECDH**: `PrivateKey#derive_shared_secret` / `PublicKey#derive_shared_secret` — commutative, tested with pinned known-key vector
- **BRC-42**: `PrivateKey#derive_child` / `PublicKey#derive_child` — uses HMAC-SHA256(key: compressed_shared_secret, msg: invoice_UTF8), matching all three reference SDKs. Tested against 9 official BRC-42 specification vectors.
- **Fee model**: `SatoshisPerKilobyte` uses `ceil((size / 1000) * rate)` formula, matching all three reference SDKs. Default rate 50 sat/kB.
- **Change distribution**: Uses equal split across change outputs (not Benford's law). This is a simplification vs the TS/Go SDKs which use Benford's law randomisation for privacy. Functionally correct but less privacy-preserving.
- **SPV verification**: Full recursive ancestry verification with merkle path, script execution, and chain tracker integration.
- **BEEF**: Complete BRC-62/95/96 serialisation with merge, validate, and lookup methods.
- **EF**: Extended Format serialisation matching all three reference SDKs.

Architectural choice of OpenSSL stdlib vs custom crypto remains deliberate, not a divergence.

---

## Novelty Assessment

Two components exist in the Ruby SDK that are **not** direct translations of reference SDK features:

1. **`BSV::Wallet`** — Simple wallet with fund/sign workflow. Not present in any reference SDK (they have a more complex 29-method WalletInterface instead).
2. **`BSV::Attest`** — Attestation module for document timestamping. Unique to the Ruby SDK; no equivalent in any reference SDK. This is a companion gem concern but currently lives in the SDK.

No other novel components exist. All other implemented features are faithful translations of reference SDK capabilities.

---

## Gap Analysis (Prioritised)

### Tier 1 — Needed for real-world use

**All Tier 1 items are complete as of v0.2.0.** This includes:
- ~~BEEF full serialisation (BRC-62/95/96)~~ Done
- ~~Extended Format (EF)~~ Done
- ~~SPV verification~~ Done
- ~~Chain tracker interface + WoC implementation~~ Done
- ~~Fee model interface + sat/kB implementation~~ Done
- ~~ECDH shared secret~~ Done
- ~~BRC-42 key derivation~~ Done

### Tier 2 — Expected by ecosystem

| Component | Prerequisite | Effort |
|-----------|-------------|--------|
| SymmetricKey (AES-256-GCM) | None | S |
| BRC-78 encrypted messages | SymmetricKey, BRC-42 | M |
| BRC-77 signed messages | BRC-42 | M |
| PushDrop template | None | S |
| RPuzzle template | None | S |
| Shamir's Secret Sharing | None | M |
| Change distribution (Benford's law) | None | S |

**Recommended order:** SymmetricKey → BRC-78 → BRC-77 → PushDrop → RPuzzle → Shamir → Benford's

### Tier 3 — Compatibility & advanced

| Component | Notes |
|-----------|-------|
| WalletInterface / ProtoWallet | 29-method interface; major effort |
| KeyDeriver (BRC-42/43) | Convenience wrapper around existing derive_child |
| Auth/Peer (BRC-31) | Certificate exchange protocol |
| Overlay tools (SHIP/SLAP) | Topic/lookup service integration |
| ECIES (Bitcore variant) | Minor variant of existing BIE1 ECIES |
| secp256r1 (P-256) | Only TS SDK has this; low priority |

---

## Summary

The BSV Ruby SDK v0.2.0 covers approximately **65%** of the reference SDK surface area, up from 50% at v0.1.0. All **Tier 1** items needed for real-world transaction building, signing, and verification are now complete. The SDK faithfully implements the same algorithms and data structures as the Go, TypeScript, and Python reference SDKs with no semantic divergences.

The most impactful next steps are Tier 2 items: **SymmetricKey** (AES-256-GCM) unlocks the BRC-77/78 messaging chain, which is the largest remaining gap in the primitives and compat layers. Script templates (PushDrop, RPuzzle) are small, independent additions. The Higher-Level layer (wallet interface, auth, overlay) represents the biggest gap but is also the most complex and least likely to be needed by early adopters — the Python SDK similarly lacks these features.
