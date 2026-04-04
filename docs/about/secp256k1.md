# Pure Ruby secp256k1

The BSV Ruby SDK includes a native Ruby implementation of the secp256k1 elliptic curve — the curve used by Bitcoin for all digital signature and key derivation operations.

## What it is

`BSV::Primitives::Secp256k1` is a pure Ruby module providing:

- **Field arithmetic** over the secp256k1 prime (modular multiplication, squaring, inversion, square root)
- **Point operations** using Jacobian coordinates internally for performance (addition, scalar multiplication, serialisation)
- **Windowed-NAF scalar multiplication** (window size 5) with precomputed table caching for the generator point
- **SEC 1 encoding** — compressed (33-byte) and uncompressed (65-byte) point serialisation

No external gems. No C extensions. Just Ruby's native arbitrary-precision `Integer` (which is C-backed in MRI for performance).

## Why it exists

The BSV TypeScript SDK (the reference implementation) and Go SDK both implement secp256k1 from scratch. The Python SDK delegates to the C library `libsecp256k1` via `coincurve`. The Ruby SDK originally followed Python's approach, using OpenSSL's built-in secp256k1 support.

This created problems:

- **OpenSSL fragility** — `Point#add` doesn't exist in OpenSSL < 3, requiring version-specific workarounds. secp256k1 support varies across OpenSSL builds and has been deprecated in some distributions.
- **Black-box operations** — the signing path passed through C code that couldn't be audited or tested in Ruby.
- **Portability** — JRuby, TruffleRuby, and other Ruby implementations have varying OpenSSL support.
- **Misalignment** — we were following the odd one out rather than the reference implementations.

## How it works today

The implementation sits behind an **OpenSSL compatibility shim** (`openssl_ec_shim.rb`) that replaces OpenSSL's `EC::Group`, `EC::Point`, and `EC` classes with pure Ruby equivalents backed by our `Secp256k1` module. The rest of the SDK is unaware of the change — it continues to use `OpenSSL::BN` for big numbers and the same `Curve` module API it always has.

One line changed in the SDK's curve module:

```ruby
# Before
require 'openssl'

# After
require_relative 'openssl_ec_shim'
```

All existing tests pass unchanged. The shim is verified against real OpenSSL through 126 byte-for-byte compliance specs and 24 process-isolated integration tests.

OpenSSL is still used for hashing (SHA-256, RIPEMD-160), HMAC, PBKDF2, and AES encryption. Only the elliptic curve operations have been replaced.

## Scope

### What it does

- All point arithmetic used by the SDK: scalar multiplication, point addition, serialisation, decompression
- Generator point operations (public key derivation, ECDSA signing)
- Arbitrary point operations (ECDH shared secrets, key derivation, Schnorr proofs)
- DER-encoded EC key parsing (for backward compatibility with `ec_key_from_*` methods)

### What it doesn't do

- **Hashing** — SHA-256, SHA-512, RIPEMD-160, HMAC remain on OpenSSL
- **Symmetric encryption** — AES-CBC, AES-GCM remain on OpenSSL
- **Constant-time guarantees** — Ruby's `Integer` arithmetic is not constant-time at the CPU level. This is the same trade-off made by the TypeScript and Go reference SDKs when implementing in their respective languages. The SDK is suitable for constructing and signing transactions; it is not intended for high-security embedded or multi-tenant environments where hardware-level timing resistance is required.

## Roadmap

The current implementation is a drop-in replacement — identical interface, proven conformance. The next phase is a **type migration** that will clean up the internal API:

- Replace `OpenSSL::BN` with Ruby `Integer` across all consumer files
- Replace `OpenSSL::PKey::EC::Point` type checks with `Secp256k1::Point`
- Remove the compatibility shim (no longer needed once consumers use native types)
- Remove `ec_key_from_private_bytes` / `ec_key_from_public_bytes` (unused in production code)

This is tracked in [#253](https://github.com/sgbett/bsv-ruby-sdk/issues/253).
