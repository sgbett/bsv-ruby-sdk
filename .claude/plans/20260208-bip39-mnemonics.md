# BIP-39 Mnemonic Generation & Seed Derivation — Task #13

## Context

Issue #13, sub-task of HLR #4. BIP-32 (`ExtendedKey`) is already merged. This adds `BSV::Primitives::Mnemonic` and a `pbkdf2_hmac_sha512` utility to the `Digest` module.

Standard BIP-39 — no BSV-specific differences. The mnemonic produces a seed that feeds directly into `ExtendedKey.from_seed`.

---

## File Structure

```
lib/bsv/primitives/mnemonic.rb              # NEW — class definition
lib/bsv/primitives/mnemonic/wordlist.rb      # NEW — 2048-word English wordlist
lib/bsv/primitives/digest.rb                 # MODIFIED — add pbkdf2_hmac_sha512
lib/bsv/primitives.rb                        # MODIFIED — add autoload :Mnemonic
spec/bsv/primitives/mnemonic_spec.rb         # NEW — specs with BIP-39 test vectors
spec/bsv/primitives/digest_spec.rb           # MODIFIED — add pbkdf2 spec
```

---

## Implementation

### `Digest.pbkdf2_hmac_sha512` addition

Add to `lib/bsv/primitives/digest.rb`:

```ruby
def pbkdf2_hmac_sha512(password, salt, iterations: 2048, key_length: 64)
  OpenSSL::PKCS5.pbkdf2_hmac(password, salt, iterations, key_length, 'sha512')
end
```

Available in Ruby 2.7+ stdlib. Keyword args with BIP-39 defaults.

### `BSV::Primitives::Mnemonic`

**Constants:**

```ruby
VALID_STRENGTHS = [128, 160, 192, 224, 256].freeze
PBKDF2_ITERATIONS = 2048
PBKDF2_KEY_LENGTH = 64
```

**Attributes (read-only):**

- `phrase` — the mnemonic string (space-separated words)
- `words` — frozen array of individual words

**Constructor methods:**

| Method | Description |
|--------|-------------|
| `.generate(strength: 128)` | Random mnemonic. Strength in bits (128/160/192/224/256). Uses `SecureRandom`. |
| `.from_entropy(entropy)` | Mnemonic from raw entropy bytes. Validates length (16/20/24/28/32). |
| `.from_phrase(phrase)` | Parse and validate existing phrase. Checks word count, wordlist membership, checksum. |

**Instance methods:**

| Method | Description |
|--------|-------------|
| `#to_seed(passphrase: '')` | 64-byte seed via PBKDF2-HMAC-SHA512. Password = NFKD(phrase), salt = "mnemonic" + NFKD(passphrase). |
| `#to_extended_key(passphrase: '', network: :mainnet)` | Convenience: `ExtendedKey.from_seed(to_seed(...), network:)`. |
| `#to_entropy` | Reverse mnemonic back to raw entropy bytes. |
| `#to_s` | Returns the phrase string. |
| `#valid?` | True if checksum is valid. |
| `#==(other)` | Equality by phrase. |

**Key algorithms:**

1. **Entropy → mnemonic:** `checksum = SHA256(entropy)`. Append `entropy_bits / 32` checksum bits. Split into 11-bit groups. Map each to `ENGLISH_WORDLIST[index]`.

2. **Mnemonic → seed:** `PBKDF2-HMAC-SHA512(password: NFKD(phrase), salt: "mnemonic" + NFKD(passphrase), iterations: 2048, key_length: 64)`.

3. **Mnemonic → entropy (validation):** Reverse: words → indices → concatenated bits → split entropy + checksum → verify `SHA256(entropy)` matches checksum bits.

4. **NFKD normalisation:** `String#unicode_normalize(:nfkd)` — available since Ruby 2.2. No-op for ASCII but required for correctness.

### Wordlist

`lib/bsv/primitives/mnemonic/wordlist.rb` — 2048 English words from the BIP-39 spec as a frozen `%w[]` array. Plus a reverse lookup hash:

```ruby
ENGLISH_WORDLIST = %w[abandon ability able ... zoo].freeze
ENGLISH_WORD_MAP = ENGLISH_WORDLIST.each_with_index.to_h.freeze
```

Loaded via `require_relative 'mnemonic/wordlist'` from the main class file.

---

## Existing Code to Reuse

| Need | Code | File |
|------|------|------|
| SHA-256 | `Digest.sha256(data)` | `lib/bsv/primitives/digest.rb` |
| ExtendedKey | `ExtendedKey.from_seed(seed, network:)` | `lib/bsv/primitives/extended_key.rb` |
| SecureRandom | `SecureRandom.random_bytes(n)` | Ruby stdlib |
| PBKDF2 | `OpenSSL::PKCS5.pbkdf2_hmac(...)` | Ruby OpenSSL stdlib |

---

## Test Vectors (from trezor/python-mnemonic)

All 12 official English vectors tested with passphrase `"TREZOR"`. Each vector tests:
- `.from_entropy(entropy)` → phrase matches expected mnemonic
- `#to_seed(passphrase: 'TREZOR')` → seed matches expected hex
- `#to_entropy` → round-trips back to original entropy

Vectors cover all valid entropy sizes (128, 160, 192, 224, 256 bits) with boundary patterns (all-zero, all-0x7f, all-0x80, all-0xff).

**Additional spec coverage:**
- `.generate` — default produces 12 words, `strength: 256` produces 24 words
- `.generate` — invalid strength raises
- `.from_entropy` — rejects wrong-length entropy
- `.from_phrase` — rejects wrong word count, unknown words, bad checksum
- `.from_phrase` — normalises whitespace
- `#to_seed` — returns 64 bytes, ASCII-8BIT encoding
- `#to_seed` — different passphrases produce different seeds
- `#to_extended_key` — returns private `ExtendedKey`, matches manual derivation
- `#valid?` / `#==` — basic behaviour
- PBKDF2 spec added to `digest_spec.rb`

---

## Wiring

Add to `lib/bsv/primitives.rb`:
```ruby
autoload :Mnemonic, 'bsv/primitives/mnemonic'
```

---

## Commit

Single commit: `feat(primitives): add BIP-39 mnemonic support`

---

## Verification

```bash
bundle exec rspec spec/bsv/primitives/mnemonic_spec.rb
bundle exec rspec spec/bsv/primitives/digest_spec.rb
bundle exec rubocop lib/bsv/primitives/mnemonic.rb lib/bsv/primitives/mnemonic/wordlist.rb lib/bsv/primitives/digest.rb
bundle exec rake
```
