# Electrum ECIES (BIE1) Encryption — Task #14

## Context

Issue #14, sub-task of HLR #4. Adds `BSV::Primitives::ECIES` module implementing Electrum-compatible ECIES encryption/decryption (BIE1 format).

BRC-78 `EncryptedMessage` (AES-256-GCM + BRC-42 key derivation) will be a separate follow-up task — it requires BRC-42 child key derivation which the SDK doesn't have yet.

---

## File Structure

```
lib/bsv/primitives/ecies.rb          # NEW — module with encrypt/decrypt
lib/bsv/primitives.rb                # MODIFIED — add autoload :ECIES
spec/bsv/primitives/ecies_spec.rb    # NEW — specs with cross-SDK test vectors
```

---

## Implementation

### `BSV::Primitives::ECIES`

Follows the `module_function` pattern used by `ECDSA` and `Digest` — stateless cryptographic operations.

**Constants:**

```ruby
MAGIC = "BIE1".b.freeze
```

**Error class:**

```ruby
class DecryptionError < StandardError; end
```

Distinguishes "structurally invalid" (`ArgumentError`) from "valid structure but wrong key / tampered" (`DecryptionError`).

**API:**

| Method | Description |
|--------|-------------|
| `.encrypt(message, public_key, private_key: nil)` | Encrypt message for recipient. Optional `private_key:` for deterministic sender (ephemeral if nil). Returns binary. |
| `.decrypt(data, private_key)` | Decrypt BIE1 payload. Returns plaintext binary. Raises `DecryptionError` on HMAC/padding failure. |

### Algorithm: `encrypt`

1. Ephemeral key: use `private_key` if provided, otherwise `PrivateKey.generate`
2. ECDH: `shared_point = Curve.multiply_point(public_key.point, ephemeral.bn)`
3. `ecdh_key = shared_point.to_octet_string(:compressed)` (33 bytes)
4. `derived = Digest.sha512(ecdh_key)` → 64 bytes
5. Split: `iv = derived[0,16]`, `key_e = derived[16,16]`, `key_m = derived[32,32]`
6. `ciphertext = AES-128-CBC(key_e, iv, message)` with PKCS7 padding (OpenSSL default)
7. `payload = MAGIC + ephemeral_pub_compressed + ciphertext`
8. `mac = Digest.hmac_sha256(key_m, payload)`
9. Return: `payload + mac`

### Algorithm: `decrypt`

1. Validate minimum length: 4 + 33 + 16 + 32 = 85 bytes
2. Parse: `magic(4) + ephemeral_pub(33) + ciphertext(variable) + mac(32)`
3. Verify magic == `"BIE1"`
4. Parse ephemeral public key via `PublicKey.from_bytes` (validates point on curve)
5. ECDH + SHA-512 key derivation (same as encrypt)
6. **Verify HMAC first** (Encrypt-then-MAC — must check before decrypting to prevent padding oracle)
7. Use `OpenSSL.fixed_length_secure_compare` for constant-time MAC comparison
8. AES-128-CBC decrypt, catch `OpenSSL::Cipher::CipherError` → re-raise as `DecryptionError`

### Wire Format

```
| "BIE1" (4) | ephemeral pubkey (33) | AES-CBC ciphertext (variable, PKCS7) | HMAC-SHA-256 (32) |
```

---

## Existing Code to Reuse

| Need | Code | File |
|------|------|------|
| ECDH point multiplication | `Curve.multiply_point(point, bn)` | `lib/bsv/primitives/curve.rb` |
| SHA-512 | `Digest.sha512(data)` | `lib/bsv/primitives/digest.rb` |
| HMAC-SHA-256 | `Digest.hmac_sha256(key, data)` | `lib/bsv/primitives/digest.rb` |
| Key generation | `PrivateKey.generate` | `lib/bsv/primitives/private_key.rb` |
| Point parsing | `PublicKey.from_bytes(bytes)` | `lib/bsv/primitives/public_key.rb` |
| Compressed pubkey | `PublicKey#compressed` | `lib/bsv/primitives/public_key.rb` |
| AES-128-CBC | `OpenSSL::Cipher.new('aes-128-cbc')` | Ruby OpenSSL stdlib |
| Constant-time compare | `OpenSSL.fixed_length_secure_compare` | Ruby 2.7+ OpenSSL stdlib |

---

## Test Vectors

### TypeScript SDK — bidirectional (primary vector)

```
Alice privkey: 77e06abc52bf065cb5164c5deca839d0276911991a2730be4d8d0a0307de7ceb
Bob privkey:   2b57c7c5e408ce927eef5e2efb49cfdadde77961d342daa72284bb3d6590862d
Plaintext:     "this is my test message"

Alice→Bob: QklFMQM55QTWSSsILaluEejwOXlrBs1IVcEB4kkqbxDz4Fap53XHOt6L3tKmrXho6yj6phfoiMkBOhUldRPnEI4fSZXbvZJHgyAzxA6SoujduvJXv+A9ri3po9veilrmc8p6dwo=
Bob→Alice: QklFMQOGFyMXLo9Qv047K3BYJhmnJgt58EC8skYP/R2QU/U0yXXHOt6L3tKmrXho6yj6phfoiMkBOhUldRPnEI4fSZXbiaH4FsxKIOOvzolIFVAS0FplUmib2HnlAM1yP/iiPsU=
```

### Go SDK — self-encryption

```
WIF: L211enC224G1kV8pyyq7bjVd9SxZebnRYEzzM3i7ZHCc1c5E7dQu
Plaintext: "hello world"
Ciphertext: QklFMQO7zpX/GS4XpthCy6/hT38ZKsBGbn8JKMGHOY5ifmaoT890Krt9cIRk/ULXaB5uC08owRICzenFbm31pZGu0gCM2uOxpofwHacKidwZ0Q7aEw==
```

### Spec Coverage

**Deterministic vectors:**
- TS SDK vector: Alice→Bob encrypt matches expected base64
- TS SDK vector: Bob→Alice encrypt matches expected base64
- Go SDK vector: self-encrypt matches expected base64
- Decrypt all three vectors, verify plaintext

**Round-trip:**
- Ephemeral key (no `private_key:` arg): encrypt then decrypt
- Various message sizes: 0, 1, 15, 16, 17, 31, 32, 33, 1000 bytes
- Binary data round-trip
- Self-encryption (encrypt to own pubkey)

**Error handling:**
- Data too short (< 85 bytes) → `ArgumentError`
- Wrong magic bytes → `ArgumentError`
- Invalid ephemeral pubkey bytes → error
- Wrong private key → `DecryptionError` (HMAC failure)
- Tampered ciphertext → `DecryptionError`
- Tampered MAC → `DecryptionError`

**Output format:**
- Starts with "BIE1"
- Compressed pubkey at offset 4 (33 bytes)
- Ends with 32-byte MAC
- Return encoding is ASCII-8BIT

---

## Security Notes

- **Constant-time MAC comparison**: `OpenSSL.fixed_length_secure_compare` (Ruby 2.7+), not `==`
- **Encrypt-then-MAC order**: HMAC verified before AES decryption (prevents padding oracle)
- **No `base64` gem**: specs use `Array#pack('m0')` / `String#unpack1('m0')` (core Ruby, no gem needed)

---

## Wiring

Add to `lib/bsv/primitives.rb` after the `ECDSA` line:

```ruby
autoload :ECIES, 'bsv/primitives/ecies'
```

---

## Commit

Single commit: `feat(primitives): add Electrum ECIES (BIE1) encryption`

---

## Verification

```bash
bundle exec rspec spec/bsv/primitives/ecies_spec.rb
bundle exec rubocop lib/bsv/primitives/ecies.rb
bundle exec rake
```
