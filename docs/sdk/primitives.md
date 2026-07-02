---
title: Primitives
nav_order: 1
parent: SDK
---

# Primitives

The `BSV::Primitives` module provides cryptographic building blocks: keys, signatures, hashing, encryption, and HD key derivation.

## Private Keys

### Generating and Importing

```ruby
# Generate a new random key
key = BSV::Primitives::PrivateKey.generate

# Import from WIF
key = BSV::Primitives::PrivateKey.from_wif('L56Q9sRtBaL...')

# Import from hex (32-byte scalar)
key = BSV::Primitives::PrivateKey.from_hex('eaf02ca348c524e6...')

# Import from raw bytes
key = BSV::Primitives::PrivateKey.from_bytes(bytes)
```

### Exporting

```ruby
key.to_wif                          # mainnet, compressed (always)
key.to_wif(network: :testnet)       # testnet

key.to_hex                          # 64-char hex string
key.to_bytes                        # 32-byte binary
```

{: .note }
> **Compressed only**
>
> `to_wif` always produces compressed WIF. BSV exclusively uses compressed
> public keys, so exporting uncompressed WIF is not supported. `from_wif`
> still accepts both formats for import compatibility with legacy wallets.

## Public Keys

Public keys are derived from private keys. They're cached — calling `private_key.public_key` multiple times returns the same object.

```ruby
pubkey = private_key.public_key

# Serialisation
pubkey.compressed           # 33 bytes (02/03 prefix)
pubkey.uncompressed         # 65 bytes (04 prefix)
pubkey.to_hex               # compressed hex (default)
pubkey.to_hex(compressed: false)

# Hash160 (RIPEMD-160 of SHA-256)
pubkey.hash160              # 20 bytes

# Address (Base58Check-encoded Hash160)
pubkey.address              # mainnet
pubkey.address(network: :testnet)
```

### Importing Public Keys

```ruby
pubkey = BSV::Primitives::PublicKey.from_hex('025ceeba2ab4a635...')
pubkey = BSV::Primitives::PublicKey.from_bytes(bytes)
```

## Signing and Verification

Signatures use deterministic ECDSA (RFC 6979) on the secp256k1 curve.

```ruby
# Sign a 32-byte hash
hash = BSV::Primitives::Digest.sha256('message')
signature = private_key.sign(hash)

# DER-encoded signature
der = signature.to_der

# Verify
valid = private_key.public_key.verify(hash, signature)
```

### Low-Level ECDSA

For recoverable signatures and public key recovery:

```ruby
# Sign with recovery ID
sig, recovery_id = BSV::Primitives::ECDSA.sign_recoverable(hash, private_key)

# Recover public key from signature
pubkey = BSV::Primitives::ECDSA.recover_public_key(hash, signature, recovery_id)
```

## Bitcoin Signed Messages (BSM)

Sign and verify messages with the standard Bitcoin message format:

```ruby
# Sign — returns base64-encoded 65-byte compact signature
sig_b64 = BSV::Primitives::BSM.sign('Hello BSV', private_key)

# Verify — recovers the public key and checks against the address
address = private_key.public_key.address
valid = BSV::Primitives::BSM.verify('Hello BSV', sig_b64, address)
```

## ECIES Encryption

Encrypt data to a recipient's public key using the BIE1 (Electrum-compatible ECIES) format:

```ruby
recipient = BSV::Primitives::PrivateKey.generate

# Encrypt (ephemeral sender key)
ciphertext = BSV::Primitives::ECIES.encrypt(
  'secret data',
  recipient.public_key
)

# Encrypt with known sender (deterministic shared secret)
ciphertext = BSV::Primitives::ECIES.encrypt(
  'secret data',
  recipient.public_key,
  private_key: sender_key
)

# Decrypt
plaintext = BSV::Primitives::ECIES.decrypt(ciphertext, recipient)
```

The ciphertext format is: `BIE1` magic (4 bytes) + ephemeral public key (33 bytes) + AES-256-CBC encrypted data + HMAC-SHA256 (32 bytes).

### Bitcore variant

Use `Primitives::ECIES.bitcore_encrypt` / `bitcore_decrypt` when interoperating with legacy BSV tooling built on the Bitcore library (e.g. Paymail implementations, older BSV wallets). The Bitcore variant differs from the Electrum/BIE1 format in three ways: there is no `BIE1` magic prefix; it uses AES-256-CBC (not AES-128); and the ECDH shared secret is derived from the raw X-coordinate of the shared point rather than the compressed public key. The wire format is `ephemeral_pub(33) + IV(16) + ciphertext + HMAC(32)`.

```ruby
recipient = BSV::Primitives::PrivateKey.generate
sender    = BSV::Primitives::PrivateKey.generate

# Encrypt
ciphertext = BSV::Primitives::ECIES.bitcore_encrypt(
  'secret data',
  recipient.public_key,
  private_key: sender   # omit for a random ephemeral key
)

# Decrypt
plaintext = BSV::Primitives::ECIES.bitcore_decrypt(ciphertext, recipient)
```

The `iv:` keyword argument accepts a 16-byte binary string to override the randomly-generated IV. **Supply a fixed IV only when producing deterministic test vectors — using a fixed IV in production breaks confidentiality.**

```ruby
fixed_iv = "\x00" * 16
ciphertext = BSV::Primitives::ECIES.bitcore_encrypt(
  plaintext,
  recipient.public_key,
  private_key: sender,
  iv: fixed_iv
)
```

See `spec/bsv/primitives/ecies_bitcore_conformance_spec.rb` for cross-SDK conformance vectors against the TS SDK.

## Hashing

The `Digest` module provides all hash functions used in Bitcoin:

```ruby
BSV::Primitives::Digest.sha256(data)        # SHA-256
BSV::Primitives::Digest.sha256d(data)       # double SHA-256
BSV::Primitives::Digest.ripemd160(data)     # RIPEMD-160
BSV::Primitives::Digest.hash160(data)       # RIPEMD-160(SHA-256(data))
BSV::Primitives::Digest.sha1(data)          # SHA-1
BSV::Primitives::Digest.sha512(data)        # SHA-512

# HMAC variants
BSV::Primitives::Digest.hmac_sha256(key, data)
BSV::Primitives::Digest.hmac_sha512(key, data)

# PBKDF2 (used by BIP-39)
BSV::Primitives::Digest.pbkdf2_hmac_sha512(password, salt, iterations, length)
```

## HD Keys (BIP-32)

Hierarchical Deterministic keys allow deriving an entire tree of key pairs from a single seed.

### From Seed

```ruby
seed = ['000102030405060708090a0b0c0d0e0f'].pack('H*')
master = BSV::Primitives::ExtendedKey.from_seed(seed)
master = BSV::Primitives::ExtendedKey.from_seed(seed, network: :testnet)
```

### Derivation

```ruby
# Single child
child = master.child(0)                           # normal child 0
hardened = master.child(0x80000000)                # hardened child 0'

# Path derivation (m/44'/0'/0'/0/0)
key = master.derive_path("m/44'/0'/0'/0/0")
# Alternate syntax: H instead of '
key = master.derive_path("m/44H/0H/0H/0/0")
```

### Public vs Private Extended Keys

```ruby
# Convert to public-only (neutering)
xpub = master.neuter

# Check type
master.private?   #=> true
xpub.private?     #=> false

# Access underlying keys
master.private_key  #=> BSV::Primitives::PrivateKey
xpub.public_key     #=> BSV::Primitives::PublicKey
```

### Serialisation

```ruby
# Extended key strings (xprv/xpub/tprv/tpub)
master.to_s     #=> "xprv9s21ZrQH143K..."
xpub.to_s       #=> "xpub661MyMwAqRbc..."

# Import
key = BSV::Primitives::ExtendedKey.from_string('xprv9s21ZrQH143K...')
```

### Key Metadata

```ruby
key.depth                # derivation depth (0 for master)
key.child_number         # child index
key.fingerprint          # 4-byte key fingerprint
key.parent_fingerprint   # 4-byte parent fingerprint
key.identifier           # 20-byte key identifier (Hash160 of public key)
```

## Schnorr ZKP (BRC-94)

`BSV::Primitives::Schnorr` is **not** BIP-340 (Taproot) signatures, not a general-purpose signature primitive, and not used for transaction signing — BSV transaction signatures use deterministic ECDSA (RFC 6979). `BSV::Primitives::Schnorr` implements the **BRC-94 Schnorr zero-knowledge proof of ECDH shared-secret knowledge**: given public keys A and B and a shared secret S = a·B (where a is A's private key), the prover demonstrates knowledge of the discrete log relationship without revealing the private key. The proof is used in Auth and certificate flows where one party needs to prove they computed the correct shared secret without transmitting the private key. See [BRC-94](https://github.com/bitcoin-sv/BRCs/blob/master/peer-to-peer/0094.md) for the specification.

The two verification equations are `z·G = R + e·A` and `z·B = S' + e·S`, where R is the commitment point, S' is the blinded shared secret, z is the response scalar, and e is the challenge hash.

```ruby
alice = BSV::Primitives::PrivateKey.generate
bob   = BSV::Primitives::PrivateKey.generate

# Alice computes the ECDH shared secret: alice_private * bob_public
shared = BSV::Primitives::PublicKey.new(
  BSV::Primitives::Curve.multiply_point(bob.public_key.point, alice.bn)
)

# Alice generates a ZK proof that she knows the private key yielding `shared`
proof = BSV::Primitives::Schnorr.generate_proof(
  alice, alice.public_key, bob.public_key, shared
)

# Bob (or any verifier) checks the proof without learning Alice's private key
valid = BSV::Primitives::Schnorr.verify_proof(
  alice.public_key, bob.public_key, shared, proof
)
#=> true
```

The `Proof` struct carries three fields: `r` (commitment point, `PublicKey`), `s_prime` (blinded shared secret, `PublicKey`), and `z` (response scalar, `OpenSSL::BN`). Binary serialisation is `R(33 B) + S'(33 B) + z(variable)` — the variable-length z accommodates both this SDK's fixed 32-byte encoding and the TS SDK's minimal encoding.

## Key Shares (Shamir backup)

`BSV::Primitives::KeyShares` implements **Shamir's Secret Sharing over the secp256k1 scalar field** as a backup and recovery mechanism. It is **not** threshold signatures, **not** MuSig, FROST, or 2P-ECDSA, and does **not** permit distributed signing — reconstruction yields the original private key in plaintext at a single location.

The use case is offline backup: split a private key into n shares and store them separately (paper wallets, hardware tokens, trusted parties). Any threshold-many shares reconstruct the key; fewer than threshold shares reveal nothing.

### Cross-SDK format compatibility

The backup format — `Base58(x).Base58(y).threshold.integrity` per share — is byte-compatible with the TypeScript and Go SDKs. The integrity tag is the first 8 hex characters of Hash160(compressed public key), **not an HMAC tag**. It acts as a lightweight sanity check that reconstruction produced the correct key.

```ruby
original = BSV::Primitives::PrivateKey.generate

# Split into 3 shares; any 2 reconstruct the key (threshold=2, total=3)
shares = original.to_key_shares(2, 3)
shares.threshold    #=> 2
shares.integrity    #=> e.g. "7a58deb5" (first 8 hex chars of Hash160(pubkey))

# Serialise for storage — one human-readable string per share
backup = shares.to_backup_format
# e.g. ["7RWw...2.7a58deb5", "...", "..."]

# Later: reconstruct from any 2 of the 3 shares
rebuilt       = BSV::Primitives::KeyShares.from_backup_format(backup[0..1])
reconstructed = BSV::Primitives::PrivateKey.from_key_shares(rebuilt)
reconstructed.to_hex == original.to_hex  #=> true
```

`PrivateKey#to_key_shares_backup` is a one-call shortcut that combines `to_key_shares` and `to_backup_format`. `PrivateKey.from_key_shares_backup` accepts the backup strings directly and returns the reconstructed private key.

## secp256k1-native acceleration

The `secp256k1-native` gem provides the secp256k1 curve implementation used throughout `BSV::Primitives`. When the gem's optional C extension compiles successfully, it replaces the pure-Ruby field, scalar, and Jacobian point operations with native C implementations — approximately a 22× speedup. If the extension fails to build (e.g. Alpine Linux without `build-base` installed), the gem falls back to pure Ruby automatically, printing a warning to stderr.

To check which is active at runtime:

```ruby
BSV::Primitives::Secp256k1.native?  #=> true if C extension is loaded, false for pure Ruby
```

The speedup applies wherever secp256k1 arithmetic is used — key generation, ECDSA signing and verification, and ECDH. Batch signing (e.g. `tx.sign_all` across many inputs) inherits the full speedup automatically.

## BIP-39 Mnemonics

Generate human-readable seed phrases:

```ruby
# Generate a 12-word mnemonic
mnemonic = BSV::Primitives::Mnemonic.generate

# 24-word mnemonic
mnemonic = BSV::Primitives::Mnemonic.generate(strength: 256)

# Import existing phrase
mnemonic = BSV::Primitives::Mnemonic.from_phrase('abandon abandon ... about')

# Derive seed (64 bytes)
seed = mnemonic.to_seed
seed = mnemonic.to_seed(passphrase: 'optional passphrase')

# Derive HD master key directly
master = mnemonic.to_extended_key
```
