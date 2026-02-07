# BSV Ruby SDK — Primitives Layer Build-out

## Goal

Implement `BSV::Primitives` — the cryptographic foundation for the SDK. This is the first layer in the dependency chain (primitives → script → transaction), matching the architecture of the Go and TypeScript reference SDKs.

## Key Technical Decisions

- **OpenSSL for point math, custom ECDSA signing.** Ruby's `dsa_sign_asn1` uses random `k`; RFC 6979 deterministic signing requires computing `k` ourselves, then doing the ECDSA math via OpenSSL's `BN` and `Point` operations. Verification delegates to OpenSSL's `dsa_verify_asn1`.
- **ASN1 DER key construction** for cross-version compatibility (OpenSSL 1.x on Ruby 2.7 and OpenSSL 3.x on Ruby 3.4).
- **All hashing via OpenSSL stdlib** — SHA-256, SHA-512, RIPEMD-160, HMAC all available natively.
- **No external gems.** Everything uses Ruby's `openssl` stdlib.

## File Structure

```
lib/bsv/
  primitives.rb                    # autoload hub (update existing stub)
  primitives/
    curve.rb                       # secp256k1 constants & OpenSSL point helpers
    digest.rb                      # SHA-256, SHA-256d, RIPEMD-160, Hash160, HMACs
    base58.rb                      # Base58 & Base58Check encoding
    signature.rb                   # Signature class (r, s, DER codec, low-S)
    ecdsa.rb                       # RFC 6979 deterministic signing & verify
    public_key.rb                  # PublicKey (compressed/uncompressed, address, verify)
    private_key.rb                 # PrivateKey (generate, WIF, sign)

spec/bsv/primitives/
    curve_spec.rb
    digest_spec.rb
    base58_spec.rb
    signature_spec.rb
    ecdsa_spec.rb
    public_key_spec.rb
    private_key_spec.rb
```

## Build Order (8 steps, each independently testable)

### 1. `Curve` — secp256k1 constants and point helpers
- Constants: `GROUP`, `N` (order), `G` (generator), `HALF_N`
- Helpers: `multiply_generator`, `multiply_point`, `add_points`, `point_x`, `point_from_bytes`
- Key construction: `ec_key_from_private_bytes`, `ec_key_from_public_bytes` (ASN1 DER approach)

### 2. `Digest` — hash functions
- `sha256`, `sha256d`, `sha512`, `ripemd160`, `hash160`
- `hmac_sha256`, `hmac_sha512`
- All accept/return binary strings (`ASCII-8BIT`)

### 3. `Base58` — Base58 and Base58Check encoding
- `encode`, `decode`, `check_encode`, `check_decode`
- `ChecksumError` for failed checksum verification

### 4. `Signature` — ECDSA signature container
- `r`, `s` as `OpenSSL::BN`
- `from_der` / `to_der` (strict BIP-66 DER)
- `to_low_s` / `low_s?` (BIP-62 canonical)
- `from_hex` / `to_hex`

### 5. `ECDSA` — RFC 6979 deterministic signing
- `sign(hash, private_key_bn)` → `Signature` (low-S enforced)
- `verify(hash, signature, public_key_ec)` → `Boolean`
- Private: `nonce_rfc6979` — port from Go SDK's `nonceRFC6979`

### 6. `PublicKey` — public key operations
- `from_bytes`, `from_hex`, `from_private_key`
- `compressed`, `uncompressed`, `to_hex`
- `hash160`, `address(network:)`
- `verify(hash, signature)`

### 7. `PrivateKey` — private key operations
- `generate`, `from_bytes`, `from_hex`, `from_wif`
- `to_bytes`, `to_hex`, `to_wif(network:, compressed:)`
- `public_key`, `sign(hash)`

### 8. Wire up autoloads in `primitives.rb`

## Test Strategy

- **Known vectors:** RFC 6979 A.2.5 (secp256k1/SHA-256), Bitcoin wiki, Go SDK test data
- **Round-trips:** hex ↔ bytes, WIF ↔ hex, DER ↔ Signature, Base58Check encode ↔ decode
- **Cross-SDK validation:** same private key + message → identical deterministic signature as Go SDK
- **Key test values:**
  - Private key `eaf02ca348c524e6392655ba4d29603cd1a7347d9d65cfe93ce1ebffdca22694`
  - WIF `L4o1GXuUSHauk19f9Cfpm1qfSXZuGLBUAC2VZM6vdmfMxRxAYkWq`
  - SHA-256 of "abc": `ba7816bf...`
  - RIPEMD-160 of "": `9c1185a5...`

## Commit Sequence

1. `feat(primitives): add Curve module with secp256k1 constants and point helpers`
2. `feat(primitives): add Digest module with hash functions`
3. `feat(primitives): add Base58 and Base58Check encoding`
4. `feat(primitives): add Signature class with DER encoding and low-S normalisation`
5. `feat(primitives): add ECDSA module with RFC 6979 deterministic signing`
6. `feat(primitives): add PublicKey class`
7. `feat(primitives): add PrivateKey class with WIF and key generation`
8. `chore(primitives): wire up autoloads`

## Verification

```bash
bundle exec rspec spec/bsv/primitives/   # all primitives specs pass
bundle exec rubocop                       # no lint violations
bundle exec rake                          # full suite green
```
