# Plan: Pure Ruby secp256k1 Implementation

**HLR:** #253

## Context

The BSV TypeScript (reference) and Go SDKs both implement secp256k1 from scratch. The Ruby SDK delegated to OpenSSL — following the Python SDK, which is the odd one out. This created misalignment with reference implementations, OpenSSL version fragility, and black-box curve operations.

## What Was Delivered (Phase 1 — Engine Replacement)

The original plan assumed a big-bang replacement: swap the engine, change all types, migrate all consumers, update all tests atomically. During implementation we discovered this destroyed the regression confidence the test suite was supposed to provide — changing 18 spec files alongside the engine swap meant the tests couldn't prove the new code behaved identically to the old.

We chose a different path: **engine first, interface preserved, confidence proved.**

### Implementation

1. **`lib/bsv/primitives/secp256k1.rb`** — Pure Ruby secp256k1 module with field arithmetic, Jacobian point operations, and windowed-NAF scalar multiplication. Ported from the TypeScript reference SDK. 486 lines, no external dependencies.

2. **`lib/bsv/primitives/openssl_ec_shim.rb`** — Replaces `OpenSSL::PKey::EC::Group`, `Point`, and `EC` with pure Ruby equivalents backed by the Secp256k1 module. OpenSSL retained for BN, Digest, HMAC, Cipher.

3. **`lib/bsv/primitives/curve.rb`** — One line changed: `require 'openssl'` → `require_relative 'openssl_ec_shim'`. Zero consumer code changes. Zero test changes.

### Verification

- 2763 original SDK tests pass unchanged (the regression harness)
- 56 secp256k1 module unit tests
- 126 compliance specs comparing shim vs real OpenSSL byte-for-byte
- 24 process-isolated integration specs (separate Ruby processes, MD5 file comparison)
- Security review with hardening applied

## What's Left (Phase 2 — Type Migration)

Tracked in #253. The engine is proven; this phase is incremental cleanup:

1. Replace `OpenSSL::BN` with Ruby `Integer` across 12 consumer files
2. Replace `OpenSSL::PKey::EC::Point` type checks with `Secp256k1::Point`
3. Remove `ec_key_from_private_bytes` / `ec_key_from_public_bytes`
4. Remove the compatibility shim
5. Update tests to match new types
6. Remove `OpenSSL::BN` / `ASN1` references from `lib/`
