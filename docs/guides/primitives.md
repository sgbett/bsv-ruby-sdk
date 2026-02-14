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
key.to_wif                          # mainnet, compressed
key.to_wif(compressed: false)       # mainnet, uncompressed
key.to_wif(network: :testnet)       # testnet

key.to_hex                          # 64-char hex string
key.to_bytes                        # 32-byte binary
```

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
