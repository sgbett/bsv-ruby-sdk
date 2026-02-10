# Bitcoin Signed Message (BSM) — Task #15

## Context

Issue #15, sub-task of HLR #4. Adds traditional Bitcoin Signed Message sign/verify (compact 65-byte signature with public key recovery). This is the legacy BSM format (`\x18Bitcoin Signed Message:\n` prefix), NOT BRC-77 SignedMessage.

The Go SDK implements this in `compat/bsm/`.

---

## File Structure

```
lib/bsv/primitives/ecdsa.rb           # MODIFIED — add sign_recoverable + recover_public_key
lib/bsv/primitives/bsm.rb             # NEW — BSM sign/verify module
lib/bsv/primitives.rb                  # MODIFIED — add autoload :BSM
spec/bsv/primitives/ecdsa_spec.rb      # MODIFIED — add recovery specs
spec/bsv/primitives/bsm_spec.rb        # NEW — BSM specs with Go SDK test vectors
```

---

## Implementation

### 1. ECDSA Recovery Operations (`lib/bsv/primitives/ecdsa.rb`)

Add two new `module_function` methods.

#### `sign_recoverable(hash, private_key_bn)` → `[Signature, recovery_id]`

Refactor: extract shared signing logic into a private `sign_raw` method that returns `[Signature, recovery_id]`. Then:
- `sign` calls `sign_raw` and returns just the signature (preserving existing API)
- `sign_recoverable` calls `sign_raw` and returns both

```ruby
def sign(hash, private_key_bn)
  sig, _recovery_id = sign_raw(hash, private_key_bn)
  sig
end

def sign_recoverable(hash, private_key_bn)
  sign_raw(hash, private_key_bn)
end
```

Private `sign_raw`:
```ruby
def sign_raw(hash, private_key_bn)
  k = nonce_rfc6979(private_key_bn, hash)
  k_inv = k.mod_inverse(Curve::N)
  r_point = Curve.multiply_generator(k)
  r = Curve.point_x(r_point) % Curve::N
  raise 'calculated R is zero' if r.zero?

  e = OpenSSL::BN.new(hash, 2)
  s = (k_inv * ((e + (private_key_bn * r)) % Curve::N)) % Curve::N
  raise 'calculated S is zero' if s.zero?

  # Recovery ID: bit 0 = R.y parity, bit 1 = R.x overflow (≥ N)
  r_y_odd = r_point.to_octet_string(:compressed).getbyte(0) == 0x03
  r_overflow = Curve.point_x(r_point) >= Curve::N
  recovery_id = (r_y_odd ? 1 : 0) + (r_overflow ? 2 : 0)

  sig = Signature.new(r, s)
  unless sig.low_s?
    sig = sig.to_low_s
    recovery_id ^= 1  # Flipping s negates R.y, toggling parity
  end

  [sig, recovery_id]
end
```

#### `recover_public_key(hash, signature, recovery_id)` → `PublicKey`

```ruby
def recover_public_key(hash, signature, recovery_id)
  r = signature.r
  s = signature.s
  n = Curve::N

  # Reconstruct R.x (may include overflow)
  x = recovery_id >= 2 ? r + n : r

  # Decompress R from x-coordinate and y-parity
  prefix = (recovery_id & 1).odd? ? "\x03".b : "\x02".b
  x_bytes = x.to_s(2)
  x_bytes = ("\x00".b * (32 - x_bytes.length)) + x_bytes if x_bytes.length < 32
  r_point = Curve.point_from_bytes(prefix + x_bytes)

  # Q = r^(-1) * (s*R - e*G)
  r_inv = r.mod_inverse(n)
  e = OpenSSL::BN.new(hash, 2)
  u1 = ((n - e) * r_inv) % n
  u2 = (s * r_inv) % n

  p1 = Curve.multiply_generator(u1)
  p2 = Curve.multiply_point(r_point, u2)
  q = Curve.add_points(p1, p2)

  raise ArgumentError, 'recovered point is at infinity' if q.infinity?

  PublicKey.new(q)
end
```

### 2. BSM Module (`lib/bsv/primitives/bsm.rb`)

Follows the `module_function` pattern. Stateless operations.

#### API

| Method | Description |
|--------|-------------|
| `.sign(message, private_key)` | Sign message, return base64 compact signature |
| `.verify(message, signature, address)` | Verify signature against address, return boolean |
| `.magic_hash(message)` | Compute the BSM double-SHA256 hash (exposed for testing) |

#### Algorithm: `sign`

1. `hash = magic_hash(message)`
2. `sig, recovery_id = ECDSA.sign_recoverable(hash, private_key.bn)`
3. `flag = 31 + recovery_id` (31–34 = compressed P2PKH per BIP-137)
4. `compact = [flag].pack('C') + bn_to_bytes(sig.r) + bn_to_bytes(sig.s)` (65 bytes)
5. Return `[compact].pack('m0')` (base64, no line breaks)

Always uses compressed keys (the SDK only supports compressed public keys).

#### Algorithm: `verify`

1. Decode: `compact = signature.unpack1('m0')` — validate 65 bytes
2. Parse: `flag = compact.getbyte(0)`, `r = compact[1, 32]`, `s = compact[33, 32]`
3. Validate flag in range 27–34
4. `recovery_id = (flag - 27) & 3`
5. `compressed = flag >= 31`
6. `hash = magic_hash(message)`
7. `sig = Signature.new(r_bn, s_bn)`
8. `pub = ECDSA.recover_public_key(hash, sig, recovery_id)`
9. Derive address from recovered key (respecting compressed/uncompressed)
10. Return `derived_address == address`

Rescue recovery errors (infinity, invalid point) → return `false`.

#### `magic_hash(message)`

```ruby
MAGIC_PREFIX = "\x18Bitcoin Signed Message:\n".b.freeze

def magic_hash(message)
  message = message.encode('UTF-8') if message.encoding != Encoding::UTF_8
  msg_bytes = message.b
  buf = encode_varint(MAGIC_PREFIX.bytesize) + MAGIC_PREFIX +
        encode_varint(msg_bytes.bytesize) + msg_bytes
  Digest.sha256d(buf)
end
```

VarInt encoding is implemented locally (6 lines) to avoid cross-module dependency on `BSV::Transaction::VarInt`:

```ruby
def encode_varint(len)
  if len < 0xFD
    [len].pack('C')
  elsif len <= 0xFFFF
    "\xFD".b + [len].pack('v')
  else
    "\xFE".b + [len].pack('V')
  end
end
```

---

## Existing Code to Reuse

| Need | Code | File |
|------|------|------|
| ECDSA signing | `ECDSA.sign` / RFC 6979 nonce | `lib/bsv/primitives/ecdsa.rb` |
| Signature r/s model | `Signature.new(r, s)`, `#low_s?`, `#to_low_s` | `lib/bsv/primitives/signature.rb` |
| Point operations | `Curve.multiply_generator`, `Curve.multiply_point`, `Curve.add_points` | `lib/bsv/primitives/curve.rb` |
| Point decompression | `Curve.point_from_bytes(bytes)` | `lib/bsv/primitives/curve.rb` |
| Double SHA-256 | `Digest.sha256d(data)` | `lib/bsv/primitives/digest.rb` |
| Address derivation | `PublicKey#address(network:)` | `lib/bsv/primitives/public_key.rb` |
| Key management | `PrivateKey#bn`, `PrivateKey#public_key` | `lib/bsv/primitives/private_key.rb` |

---

## Test Vectors

### Go SDK — Compressed Key Signatures (primary)

```
Key hex: 0499f8239bfe10eb0f5e53d543635a423c96529dd85fa4bad42049a0b435ebdd
Message: "test message"
Expected: "IFxPx8JHsCiivB+DW/RgNpCLT6yG3j436cUNWKekV3ORBrHNChIjeVReyAco7PVmmDtVD3POs9FhDlm/nk5I6O8="

Key hex: ef0b8bad0be285099534277fde328f8f19b3be9cadcd4c08e6ac0b5f863745ac
Message: "This is a test message"
Expected: "H+zZagsyz7ioC/ZOa5EwsaKice0vs2BvZ0ljgkFHxD3vGsMlGeD4sXHEcfbI4h8lP29VitSBdf4A+nHXih7svf4="

Key hex: 93596babb564cbbdc84f2370c710b9bcc94333495b60af719b5fcf9ba00ba82c
Message: "This is a test message"
Expected: "IIuDw09ffPgEDuxEw5yHVp1+mi4QpuhAwLyQdpMTfsHCOkMqTKXuP7dSNWMEJqZsiQ8eKMDRvf2wZ4e5bxcu4O0="

Key hex: 50381cf8f52936faae4a05a073a03d688a9fa206d005e87a39da436c75476d78
Message: "This is a test message"
Expected: "ILBmbjCY2Z7eSXGXZoBI3x2ZRaYUYOGtEaDjXetaY+zNDtMOvagsOGEHnVT3f5kXlEbuvmPydHqLnyvZP3cDOWk="

Key hex: c7726663147afd1add392d129086e57c0b05aa66a6ded564433c04bd55741434
Message: "This is a test message"
Expected: "IOI207QUnTLr2Ll+s4kUxNgLgorkc/Z5Pc+XNvUBYLy2TxaU6oHEJ2TTJ1mZVrtUyHm6e315v1tIjeosW3Odfqw="

Key hex: c7726663147afd1add392d129086e57c0b05aa66a6ded564433c04bd55741434
Message: "1"
Expected: "IMcRFG1VNN9TDGXpCU+9CqKLNOuhwQiXI5hZpkTOuYHKBDOWayNuAABofYLqUHYTMiMf9mYFQ0sPgFJZz3F7ELQ="
```

### Spec Coverage

**Deterministic vectors (Go SDK cross-compatibility):**
- Sign each Go SDK vector, compare base64 output
- Verify each Go SDK vector against derived address
- Verify returns false for wrong address
- Verify returns false for wrong message

**ECDSA recovery unit tests:**
- `sign_recoverable` returns `[Signature, Integer]`
- `sign_recoverable` signature matches `sign` output
- `recover_public_key` recovers the correct public key
- Recovery round-trip: sign → recover → compare pubkey
- Multiple key/message combinations

**Round-trip:**
- Sign then verify with various messages
- Empty message
- Unicode message
- Long message (>252 bytes, exercises 3-byte varint)

**Error handling:**
- Invalid base64 → `ArgumentError`
- Signature wrong length → `ArgumentError`
- Flag byte out of range → `ArgumentError`
- Wrong address → returns `false`
- Tampered signature → returns `false`

---

## Wiring

Add to `lib/bsv/primitives.rb` after the `ECIES` line:

```ruby
autoload :BSM, 'bsv/primitives/bsm'
```

---

## Commit

Single commit: `feat(primitives): add Bitcoin Signed Message (BSM) sign/verify`

---

## Verification

```bash
bundle exec rspec spec/bsv/primitives/ecdsa_spec.rb
bundle exec rspec spec/bsv/primitives/bsm_spec.rb
bundle exec rubocop lib/bsv/primitives/ecdsa.rb lib/bsv/primitives/bsm.rb
bundle exec rake
```
