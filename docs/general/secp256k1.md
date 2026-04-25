# secp256k1 in the BSV Ruby SDK

The BSV Ruby SDK implements the secp256k1 elliptic curve — the curve used by Bitcoin for all digital signature and key derivation operations — in pure Ruby, with an optional native C extension for performance-critical paths.

## Pure Ruby implementation

`BSV::Primitives::Secp256k1` is a pure Ruby module providing:

- **Field arithmetic** over the secp256k1 prime (modular multiplication, squaring, inversion, square root)
- **Point operations** using Jacobian coordinates internally for performance (addition, doubling, negation, serialisation)
- **Windowed-NAF scalar multiplication** (window size 5) with precomputed table caching for the generator point
- **SEC 1 encoding** — compressed (33-byte) and uncompressed (65-byte) point serialisation

No external gems for elliptic curve operations. OpenSSL is used only for hashing (SHA-256, RIPEMD-160, SHA-512), HMAC, PBKDF2, and AES encryption.

## Native C acceleration

`BSV::Primitives::Secp256k1Native` is an optional C extension that replaces the hot-path field, scalar, and Jacobian point operations with fixed-width C implementations. When compiled, `secp256k1.rb` automatically delegates these operations to the extension at load time; the pure-Ruby methods remain as a readable reference and as the fallback when the extension is unavailable.

### What the extension accelerates

The extension provides native implementations for all operations in the following categories:

- **Field arithmetic** (`fmul`, `fsqr`, `fadd`, `fsub`, `fneg`, `finv`, `fsqrt`, `fred`) — arithmetic modulo the secp256k1 field prime P = 2²⁵⁶ − 2³² − 977
- **Scalar arithmetic** (`scalar_mul`, `scalar_add`, `scalar_inv`, `scalar_mod`) — arithmetic modulo the curve order N
- **Jacobian point operations** (`jp_double`, `jp_add`, `jp_neg`) — point doubling, addition, and negation in Jacobian projective coordinates, with all intermediate field arithmetic in C (no Ruby method dispatch per operation)

### What stays in Ruby

- **Scalar multiplication** (wNAF loop, Montgomery ladder) — the high-level algorithm remains in Ruby, calling native field and point primitives per step
- **ECDSA signing and verification** — RFC 6979 deterministic nonce derivation and signature assembly
- **Schnorr signatures** — BIP-340 Schnorr signing and verification
- **Key derivation** — BIP-32 HD key derivation and BIP-39 mnemonic processing
- **Hashing and encryption** — all SHA-256, RIPEMD-160, HMAC, AES operations remain on OpenSSL

### Internal representation

The extension uses a `uint256_t` type: a 4 × `uint64_t` struct stored in little-endian limb order (d[0] is the least-significant 64-bit word). Values are marshalled between Ruby `Integer` and this struct via `rb_integer_pack` / `rb_integer_unpack`.

Field arithmetic uses a two-fold fast-reduction technique exploiting P = 2²⁵⁶ − c where c = 0x1000003D1. Jacobian point operations call field primitives directly in C without crossing the Ruby/C boundary per intermediate step: `jp_double` executes approximately 14 field operations and `jp_add` approximately 18, all in C.

### Constant-time field arithmetic

The field arithmetic functions (`fred`, `fsub`, `fneg`, `fadd`) use branchless conditional selection via bitwise masks derived from carry and borrow flags. Execution time for field operations does not depend on the field values. Inversion and square root iterate over public constants (P−2 and (P+1)/4), which is safe because those constants are not secret.

The wNAF scalar multiplication loop in Ruby branches on scalar bits, so the extension does not provide full constant-time scalar multiplication at the algorithm level. The pure-Ruby layer carries the same trade-off as the TypeScript and Go reference SDKs.

### Performance

Approximate throughput on a modern development machine:

| Mode | Operations/sec (scalar multiplication) |
|---|---|
| Pure Ruby | ~100 |
| Native C extension | ~2,277 |

The native extension provides approximately 22× speedup for scalar multiplication — the dominant cost in ECDSA signing, public key derivation, and Schnorr proof generation.

### Build requirements

- C99 compiler with `__uint128_t` support — satisfied by GCC and Clang on macOS (arm64 and x86\_64) and Linux (x86\_64)
- Ruby development headers (included with RVM builds)
- **Not supported** on MSVC (Windows); the extension gracefully skips compilation and the gem falls back to pure Ruby

### Fallback behaviour

`extconf.rb` checks for `__uint128_t` availability. If the type is not available, a no-op Makefile is generated and the extension is silently skipped. At runtime, `secp256k1.rb` wraps the `require` in a `rescue LoadError` block — if the compiled bundle is absent, the pure-Ruby implementation is used without any error or configuration required.

The gem installs and operates correctly without the native extension. Compilation is optional and additive.

### Build instructions

```bash
# From the repository root
bundle exec rake compile   # build the C extension
bundle exec rake spec:sdk  # run the test suite with native acceleration active
```

The compiled bundle is placed at `gem/bsv-sdk/lib/bsv/secp256k1_native.bundle` (or `.so` on Linux), matching the `require 'bsv/secp256k1_native'` path used by the extension loader.

## Why pure Ruby as the base

The BSV TypeScript SDK and Go SDK both implement secp256k1 from scratch. The Python SDK delegates to `libsecp256k1` via `coincurve`. The Ruby SDK originally used OpenSSL's built-in secp256k1 support, which created several problems:

- **OpenSSL fragility** — `Point#add` does not exist in OpenSSL < 3; secp256k1 support varies across builds and has been deprecated in some distributions.
- **Black-box operations** — the signing path passed through C code that could not be audited or tested in Ruby.
- **Portability** — JRuby and TruffleRuby have varying OpenSSL support.
- **Misalignment** — the OpenSSL approach followed the odd-one-out rather than the reference implementations.

The pure-Ruby base layer ensures the SDK is comprehensible, auditable, and portable. The native extension sits below this layer as an optional accelerator — the public API is identical regardless of whether the extension is loaded.

## OpenSSL compatibility shim

An `openssl_ec_shim.rb` replaces `OpenSSL::PKey::EC` classes with pure-Ruby equivalents backed by `BSV::Primitives::Secp256k1`. The rest of the SDK is unaware of the change — it continues to use the same `Curve` module API. OpenSSL is still used for all non-EC operations.

## Scope summary

| Concern | Implementation |
|---|---|
| Field arithmetic (mod P) | C extension (with pure-Ruby fallback) |
| Scalar arithmetic (mod N) | C extension (with pure-Ruby fallback) |
| Jacobian point operations | C extension (with pure-Ruby fallback) |
| Scalar multiplication (wNAF) | Ruby, calling native primitives |
| ECDSA, Schnorr, key derivation | Ruby |
| SHA-256, RIPEMD-160, HMAC, AES | OpenSSL |

## Roadmap

The next phase is a **type migration** that will clean up the internal API:

- Replace `OpenSSL::BN` with Ruby `Integer` across all consumer files
- Replace `OpenSSL::PKey::EC::Point` type checks with `Secp256k1::Point`
- Remove the compatibility shim (no longer needed once consumers use native types)
- Remove `ec_key_from_private_bytes` / `ec_key_from_public_bytes` (unused in production code)

This is tracked in [#253](https://github.com/sgbett/bsv-ruby-sdk/issues/253).
