# Schnorr ZKP (BRC-94) — Task #16

## Context

Issue #16, last sub-task of HLR #4. Implements the BRC-94 Schnorr zero-knowledge proof protocol for verifiable revelation of shared secrets. This proves correct ECDH shared secret computation without revealing the private key.

**Not** BIP-340 Schnorr signatures — this is a specialised ZKP used in the BRC-42/BRC-69 key derivation ecosystem.

Go SDK: `primitives/schnorr/schnorr.go`
TS SDK: `src/primitives/Schnorr.ts`

---

## File Structure

```
lib/bsv/primitives/schnorr.rb          # NEW — Schnorr ZKP module
lib/bsv/primitives.rb                  # MODIFIED — add autoload :Schnorr
spec/bsv/primitives/schnorr_spec.rb    # NEW — Schnorr specs
```

---

## Implementation

### Data Structure: `Proof`

Simple value object holding the three proof components:

```ruby
class Proof
  attr_reader :r, :s_prime, :z

  def initialize(r, s_prime, z)
    @r = r           # PublicKey — nonce public key (r·G)
    @s_prime = s_prime # PublicKey — nonce shared secret (r·B)
    @z = z           # OpenSSL::BN — response scalar (r + e·a mod n)
  end
end
```

### Module: `BSV::Primitives::Schnorr`

Follows the `module_function` pattern.

#### `generate_proof(private_key, public_key_a, public_key_b, shared_secret)` → `Proof`

1. Generate random nonce `r` (using `PrivateKey.generate`)
2. `R = r·G` (nonce public key)
3. `S' = r·B` (nonce shared secret via `Curve.multiply_point(B.point, r.bn)`)
4. `e = compute_challenge(A, B, S, S', R)`
5. `z = (r.bn + e * private_key.bn) % N`
6. Return `Proof.new(R, S', z)`

Parameters:
- `private_key` — `PrivateKey` (the prover's private key `a`)
- `public_key_a` — `PublicKey` (prover's public key, should equal `a·G`)
- `public_key_b` — `PublicKey` (counterparty's public key)
- `shared_secret` — `PublicKey` (the shared secret point `a·B`)

#### `verify_proof(public_key_a, public_key_b, shared_secret, proof)` → `Boolean`

1. `e = compute_challenge(A, B, S, proof.s_prime, proof.r)`
2. Check equation 1: `z·G == R + e·A`
3. Check equation 2: `z·B == S' + e·S`
4. Return `true` only if both hold

Point comparison uses compressed encoding (`point.to_octet_string(:compressed)`).

#### Private: `compute_challenge(a, b, s, s_prime, r)` → `OpenSSL::BN`

```ruby
def compute_challenge(a, b, s, s_prime, r)
  message = a.compressed + b.compressed +
            s.compressed + s_prime.compressed + r.compressed
  hash = Digest.sha256(message)
  OpenSSL::BN.new(hash, 2) % Curve::N
end
```

Concatenates 5 compressed public keys (33 bytes each = 165 bytes total), SHA-256 hashes, reduces mod N.

---

## Existing Code to Reuse

| Need | Code | File |
|------|------|------|
| Point multiplication (generator) | `Curve.multiply_generator(bn)` | `lib/bsv/primitives/curve.rb` |
| Point multiplication (arbitrary) | `Curve.multiply_point(point, bn)` | `lib/bsv/primitives/curve.rb` |
| Point addition | `Curve.add_points(p1, p2)` | `lib/bsv/primitives/curve.rb` |
| SHA-256 | `Digest.sha256(data)` | `lib/bsv/primitives/digest.rb` |
| Random key generation | `PrivateKey.generate` | `lib/bsv/primitives/private_key.rb` |
| Compressed encoding | `PublicKey#compressed` | `lib/bsv/primitives/public_key.rb` |

---

## Test Coverage

**No deterministic cross-SDK vectors** — the Go and TS SDKs both use random nonces, so proof outputs differ each run. Tests focus on correctness properties.

**Round-trip:**
- Generate proof with fixed keys, verify succeeds
- Generate proof with random keys, verify succeeds
- Multiple key pairs round-trip

**Tamper detection (verify returns false):**
- Tampered R (different point)
- Tampered z (modified scalar)
- Tampered S' (different point)
- Wrong public key A
- Wrong public key B
- Wrong shared secret S

**Proof structure:**
- `generate_proof` returns a `Proof` with correct types
- `proof.r` and `proof.s_prime` are `PublicKey` instances
- `proof.z` is an `OpenSSL::BN`

**Challenge computation (deterministic, testable):**
- Same inputs produce same challenge
- Different inputs produce different challenges

**Edge cases:**
- Proof generated with wrong private key (a doesn't match A) — verify fails

---

## Wiring

Add to `lib/bsv/primitives.rb` after the `BSM` line:

```ruby
autoload :Schnorr, 'bsv/primitives/schnorr'
```

---

## Commit

Single commit: `feat(primitives): add Schnorr ZKP (BRC-94) for shared secret verification`

---

## Verification

```bash
bundle exec rspec spec/bsv/primitives/schnorr_spec.rb
bundle exec rubocop lib/bsv/primitives/schnorr.rb
bundle exec rake
```
