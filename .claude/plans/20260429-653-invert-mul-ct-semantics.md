# Plan: Invert mul/mul_ct semantics — make CT the default

## Context

The SDK's `Point#mul` is variable-time wNAF, while `Point#mul_ct` is constant-time Montgomery ladder. This is backwards from OpenSSL convention where `EC_POINT_mul` is always constant-time. The secp256k1-native C extension gem is independently making the same change. We need to align the pure-Ruby `Point` class, the OpenSSL shim, the `Curve` module, and all callers.

**Bonus fix:** `schnorr.rb:76` currently uses variable-time multiplication with a secret nonce — a timing side-channel bug. After this change, `multiply_point` becomes CT by default, fixing it automatically.

## Target API

| Method | Behaviour | Purpose |
|--------|-----------|---------|
| `mul` | Constant-time Montgomery ladder | Safe default (matches OpenSSL) |
| `mul_vt` | Variable-time wNAF | Explicit opt-in for public scalars |
| `mul_ct` | Alias for `mul` | Expressiveness / backward compat |

---

## Step 1 — Point class (`secp256k1.rb`)

**File:** `gem/bsv-sdk/lib/bsv/primitives/secp256k1.rb`

- **`Point#mul` (line 520):** Change body from `scalar_multiply_wnaf` to `scalar_multiply_ct`. Update docstring.
- **New `Point#mul_vt`:** Insert after `mul`. Takes the old `mul` body (calls `scalar_multiply_wnaf`). Docstring warns "variable-time, public scalars only".
- **`Point#mul_ct` (line 541):** Replace body with `alias mul_ct mul`. Keep docstring noting alias.

Module-level `scalar_multiply_wnaf` and `scalar_multiply_ct` implementations: **no changes**. Native delegation list (`scalar_multiply_ct` on line ~619): **no changes** — still valid.

## Step 2 — OpenSSL shim (`openssl_ec_shim.rb`)

**File:** `gem/bsv-sdk/lib/bsv/primitives/openssl_ec_shim.rb`

- **`BSVShimECPoint#mul` (line 69):** No code change (delegates to `@secp_point.mul` which is now CT). Update docstring.
- **`BSVShimECPoint#mul_ct` (line 95):** No code change (delegates to alias). Update docstring.
- **New `BSVShimECPoint#mul_vt`:** Delegates to `@secp_point.mul_vt(scalar)`.
- Multi-scalar form in `mul` (lines 74-82): becomes CT — acceptable, only used by `add_points` Ruby 2.7 fallback with scalar=1.

## Step 3 — Curve module (`curve.rb`)

**File:** `gem/bsv-sdk/lib/bsv/primitives/curve.rb`

- **`multiply_generator` (line 35):** Now CT via `G.mul`. Update docstring.
- **`multiply_generator_ct` (line 46):** Still CT via `G.mul_ct` alias. Update docstring to note alias.
- **New `multiply_generator_vt`:** Calls `G.mul_vt(scalar_bn)`.
- **`multiply_point` (line 58):** Now CT via `point.mul`. Update docstring.
- **`multiply_point_ct` (line 70):** Still CT via alias. Update docstring.
- **New `multiply_point_vt`:** Calls `point.mul_vt(scalar_bn)`.

## Step 4 — ECDSA callers (`ecdsa.rb`)

**File:** `gem/bsv-sdk/lib/bsv/primitives/ecdsa.rb`

Switch verification/recovery paths to explicit VT (public scalars, performance):

- Line 85: `Curve.multiply_generator(u1)` → `Curve.multiply_generator_vt(u1)`
- Line 86: `Curve.multiply_point(r_point, u2)` → `Curve.multiply_point_vt(r_point, u2)`
- Line 115: `Curve.multiply_generator(u1)` → `Curve.multiply_generator_vt(u1)`
- Line 116: `Curve.multiply_point(public_key_point, u2)` → `Curve.multiply_point_vt(public_key_point, u2)`
- Line 134: `Curve.multiply_generator_ct(k)` → **no change** (secret nonce, CT correct)

## Step 5 — Schnorr callers (`schnorr.rb`)

**File:** `gem/bsv-sdk/lib/bsv/primitives/schnorr.rb`

- Line 76: `Curve.multiply_point(public_key_b.point, nonce.bn)` → **no code change needed** (now CT by default, fixing the secret-nonce timing bug). Leave as `multiply_point` since the default is now safe.
- Line 100: `Curve.multiply_generator(proof.z)` → `Curve.multiply_generator_vt(proof.z)`
- Line 101: `Curve.multiply_point(public_key_a.point, e)` → `Curve.multiply_point_vt(public_key_a.point, e)`
- Line 107: `Curve.multiply_point(public_key_b.point, proof.z)` → `Curve.multiply_point_vt(public_key_b.point, proof.z)`
- Line 108: `Curve.multiply_point(shared_secret.point, e)` → `Curve.multiply_point_vt(shared_secret.point, e)`

## Step 6 — No-change files (verify only)

These already use `_ct` variants, which still work via alias:
- `private_key.rb:132` — `multiply_generator_ct` (secret key)
- `private_key.rb:151` — `multiply_point_ct` (ECDH)
- `public_key.rb:118` — `multiply_point_ct` (ECDH)
- `public_key.rb:136` — `multiply_generator_ct` (BRC-42 derivation)
- `extended_key.rb:187` — `multiply_generator_ct` (BIP-32)
- `extended_key.rb:299` — `multiply_generator_ct` (pubkey from privkey)

## Step 7 — Tests

### secp256k1_spec.rb
- `describe '#mul'` tests (line ~246): update descriptions to say "constant-time". All math assertions unchanged.
- `describe '#mul_ct'` tests (line ~296): update descriptions to note alias. Equivalence tests (`mul_ct` vs `mul`) now compare alias to itself — still valid but update descriptions.
- **New** `describe '#mul_vt'`: mirror old `mul` test structure. Include equivalence test `mul_vt(k) == mul(k)`.

### secp256k1_compliance_spec.rb
- Update descriptions for `mul` / `mul_ct` sections.
- **New** `mul_vt` compliance tests (matches mul for known multiples).

### secp256k1_native_spec.rb
- Line 576 (`g.mul(k)`): now tests CT path. Update description.
- Line 684 (`g.mul(5)`): change to `g.mul_vt(5)` to test wNAF through native delegation. Add `g.mul(5)` CT test alongside.
- Line 692 (`g.mul_ct(3)`): still valid via alias.
- **New** test for `g.mul_vt` through native delegation.

### curve_spec.rb
- **New** `describe '.multiply_generator_vt'` and `describe '.multiply_point_vt'`.

### OpenSSL shim compliance (spec/conformance/)
- Existing `point_mul_spec.rb` / `point_mul_multi_spec.rb`: all pass unchanged.
- **New** `mul_vt` shim tests.

## Step 8 — Full regression

```bash
cd gem/bsv-sdk && bundle exec rspec
```

## Verification

1. All existing tests pass (mathematical results identical regardless of CT vs VT)
2. New `mul_vt` tests cover the variable-time path
3. ECDSA sign/verify round-trip works
4. Schnorr proof generate/verify round-trip works
5. BIP-32 key derivation works
6. ECIES encrypt/decrypt works
