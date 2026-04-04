# Plan: Pure Ruby secp256k1 Implementation

**HLR:** #253

## Context

The BSV TypeScript (reference) and Go SDKs both implement secp256k1 from scratch. The Ruby SDK delegates to OpenSSL — following the Python SDK, which is the odd one out. This creates:

- **Misalignment** with reference implementations
- **OpenSSL fragility** — `Point#add` doesn't exist in OpenSSL < 3 (we already have a Ruby 2.7 hack), and secp256k1 support varies across builds
- **Black-box curve operations** — the signing path passes through C code that can't be audited or tested in Ruby

The SDK has **~462 test cases** across 18 spec files, including BIP-32 official vectors, RFC 6979 signing vectors, and cross-SDK interop vectors (Go, TS). This entire suite becomes a regression harness — swap the engine, run the specs.

## What Changes vs What Stays

**Replacing:**
- `OpenSSL::PKey::EC::Group` / `Point` — curve constants + point arithmetic
- `OpenSSL::BN` — big number scalars (~98 references across 12 files)
- `OpenSSL::ASN1` — EC key construction (only in `curve.rb`)
- `OpenSSL::PKey::EC` — key objects (only in `curve.rb`)

**Keeping:**
- `OpenSSL::Digest` — SHA-1/256/512, RIPEMD-160
- `OpenSSL::HMAC` — SHA-256/512
- `OpenSSL::PKCS5` — PBKDF2
- `OpenSSL::Cipher` — AES-128-CBC, AES-256-CBC, AES-256-GCM
- `OpenSSL.fixed_length_secure_compare` — constant-time comparison (ecies.rb, proto_wallet.rb)

## Design Decisions

### 1. Big numbers: Ruby Integer directly

Ruby's native `Integer` is arbitrary-precision and C-backed (uses GMP in MRI). No custom BigNumber class needed — the TS SDK's `BigNumber.ts` exists because JavaScript originally lacked `BigInt`.

### 2. Field arithmetic: Helper methods, not a class

A `Secp256k1` module provides `fmul`, `fadd`, `fsub`, `finv`, `fsqrt` as module functions on plain Integers. Lighter than a FieldElement class. `P = 2^256 - 2^32 - 977`.

### 3. Point: Class with Jacobian internals

`Secp256k1::Point` stores affine `(x, y)`. Jacobian `(X, Y, Z)` used internally during scalar multiplication to avoid field inversions. Single inversion on output.

### 4. Scalar multiplication: Windowed NAF (window=5)

Port from TS SDK's `scalarMultiplyWNAF`. Generator point gets a permanently cached precomputed table. ~256 doublings + ~52 additions per multiplication.

### 5. `ec_key_from_private_bytes` / `ec_key_from_public_bytes`: Remove

Only defined in `curve.rb`, only tested in `curve_spec.rb`, never called from production code. These return `OpenSSL::PKey::EC` objects — meaningless without OpenSSL EC.

### 6. `OpenSSL::BN` → `Integer` mapping

| OpenSSL::BN | Ruby Integer |
|---|---|
| `OpenSSL::BN.new(bytes, 2)` | `Secp256k1.bytes_to_int(bytes)` |
| `OpenSSL::BN.new(hex, 16)` | `hex.to_i(16)` |
| `OpenSSL::BN.new('0')` | `0` |
| `bn.to_s(2)` | `Secp256k1.int_to_bytes(n, 32)` |
| `bn.mod_inverse(m)` | `n.pow(m - 2, m)` (Fermat) |
| `bn.mod_add(b, m)` | `(a + b) % m` |
| `bn.mod_mul(b, m)` | `(a * b) % m` |
| `bn.num_bits` | `n.bit_length` |
| `bn.zero?` / `bn.negative?` | same on Integer |
| `OpenSSL::BN.rand(256)` | `Secp256k1.bytes_to_int(SecureRandom.random_bytes(32))` |

## Implementation Phases

### Phase 1: New secp256k1 module (standalone, no existing code changes)

**New file:** `lib/bsv/primitives/secp256k1.rb`

```
BSV::Primitives::Secp256k1
  Constants: P, N, HALF_N, GX, GY

  Byte helpers:
    .bytes_to_int(bytes) → Integer
    .int_to_bytes(n, length) → String

  Field arithmetic (mod P):
    .fmul(a, b), .fsqr(a), .fadd(a, b), .fsub(a, b)
    .finv(a), .fsqrt(a)

  Scalar arithmetic (mod N):
    .scalar_inv(a), .scalar_mul(a, b), .scalar_add(a, b)

  Point class:
    .infinity, .generator, .from_bytes(bytes)
    #x, #y, #infinity?
    #to_octet_string(:compressed / :uncompressed)
    #mul(scalar), #add(other), #negate
    #==(other)

  Internal (private):
    Jacobian point operations: jp_double, jp_add, jp_to_affine
    wNAF scalar multiplication with precomputed table caching
```

**New file:** `spec/bsv/primitives/secp256k1_spec.rb` — unit tests for:
- Constants match known secp256k1 values
- Field arithmetic (inverse, sqrt, edge cases)
- Point decompression from known compressed/uncompressed pairs
- Scalar multiplication against known vectors (1*G, 2*G, privkey*G)
- Point addition, negation, identity element
- Round-trip serialise/deserialise
- Edge cases (infinity, zero scalar, N-1)

**Reference files for porting:**
- `/opt/ruby/bsv-reference-sdks/ts-sdk/src/primitives/Point.ts` (wNAF, lines 159-212, 747-798)
- `/opt/ruby/bsv-reference-sdks/ts-sdk/src/primitives/JacobianPoint.ts` (Jacobian formulas)
- `/opt/ruby/bsv-reference-sdks/ts-sdk/src/primitives/Curve.ts` (precomputed tables)

### Phase 2: Rewire Curve + migrate all consumers (atomic)

Phases 2-4 must be a single atomic commit — changing Curve's return types from `OpenSSL::BN`/`Point` to `Integer`/`Secp256k1::Point` breaks all consumers simultaneously.

**`lib/bsv/primitives/curve.rb`** — complete rewrite:
- `N` = `Secp256k1::N` (Integer)
- `G` = `Secp256k1::Point.generator`
- `HALF_N` = `Secp256k1::HALF_N`
- `multiply_generator(scalar)` → `Secp256k1::Point`
- `multiply_point(point, scalar)` → `Secp256k1::Point`
- `add_points(a, b)` → `Secp256k1::Point`
- `point_x(point)` → `Integer`
- `point_from_bytes(bytes)` → `Secp256k1::Point`
- Remove: `GROUP`, `ec_key_from_private_bytes`, `ec_key_from_public_bytes`, Ruby 2.7 fallback
- Remove: `require 'openssl'`

### Phase 3: Migrate consumers (atomic with Phase 2)

**Files and key changes:**

| File | Refs | Key changes |
|---|---|---|
| `private_key.rb` | 12 | `@bn` stores Integer; `from_bytes`/`from_hex` use `bytes_to_int`/`.to_i(16)`; `derive_child` uses `(a + b) % N` |
| `ecdsa.rb` | 10 | All BN arithmetic → Integer; `mod_inverse` → `.pow(n-2, n)`; recovery uses `point.y.odd?` |
| `signature.rb` | 8 | `@r`, `@s` become Integer; DER encode/decode via `int_to_bytes`/`bytes_to_int` |
| `polynomial.rb` | 8 | `mod_mul`/`mod_add` → `(a*b)%m`/`(a+b)%m`; random via SecureRandom |
| `point_in_finite_field.rb` | 10 | `P` constant as Integer; coords as Integer |
| `extended_key.rb` | 4 | `bytes_to_int` for IL; `(il + key) % N` for child derivation |
| `public_key.rb` | 4 | `@point` becomes `Secp256k1::Point` |
| `schnorr.rb` | 3 | `Proof#z` becomes Integer; challenge via `bytes_to_int` |
| `bsm.rb` | 3 | `bytes_to_int` for r,s; rescue `ArgumentError` not `OpenSSL::PKey::EC::Point::Error` |
| `signed_message.rb` | 2 | `OpenSSL::BN.new(1)` → `1` |
| `key_deriver.rb` | 1 | `OpenSSL::BN.new(1)` → `1` |

### Phase 4: Update tests (atomic with Phases 2-3)

**`spec/bsv/primitives/curve_spec.rb`:**
- Remove OpenSSL type assertions (`be_a OpenSSL::PKey::EC::Group` etc.)
- Replace `OpenSSL::BN.new('2', 10)` with `2`
- Remove `ec_key_from_private_bytes`/`ec_key_from_public_bytes` examples
- Assert against `Secp256k1::Point` and `Integer`

**All other spec files** — mechanical replacement:
- `OpenSSL::BN.new(hex, 16)` → `hex.to_i(16)`
- `OpenSSL::BN.new(bytes, 2)` → `Secp256k1.bytes_to_int(bytes)`
- `be_a(OpenSSL::BN)` → `be_a(Integer)`
- `be_a(OpenSSL::PKey::EC::Point)` → `be_a(Secp256k1::Point)`

## Verification

1. **Phase 1 standalone:** `bundle exec rspec spec/bsv/primitives/secp256k1_spec.rb` — new tests pass
2. **Phase 2-4 atomic:** `bundle exec rake` — all ~462 existing tests pass unchanged in behaviour
3. **Confirm no OpenSSL EC references remain:** `grep -r 'OpenSSL::PKey::EC\|OpenSSL::BN\|OpenSSL::ASN1' lib/` should return nothing
4. **RuboCop:** `bundle exec rubocop` passes

## Performance Notes

- Scalar multiplication will be ~20-50x slower than OpenSSL (estimated 2-5ms vs 0.1ms). Acceptable for SDK usage (signing transactions, deriving keys — not mining).
- Ruby's `Integer#pow(exp, mod)` (since 2.5) uses C-level modular exponentiation, making Fermat inversions fast.
- wNAF with window=5 reduces additions to ~52 per multiplication. Generator table is cached permanently.
- If performance proves inadequate: increase wNAF window, add endomorphism splitting (Go SDK approach), or precompute larger generator tables.

## Risk Mitigation

| Risk | Mitigation |
|---|---|
| Point decompression correctness | `fsqrt` via `x^((P+1)/4)` since P ≡ 3 (mod 4); tested against known pairs |
| wNAF edge cases | Port exact logic from TS SDK; test with 0, 1, N-1, random |
| Recovery ID regression | RFC 6979 + BSM test vectors verify exact output |
| Exception handling (bsm.rb) | Replace `rescue OpenSSL::PKey::EC::Point::Error` with `rescue ArgumentError` |
| Thread safety of table cache | MRI GIL makes Hash reads safe; worst case is redundant computation |
