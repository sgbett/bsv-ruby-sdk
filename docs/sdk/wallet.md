---
title: Wallet
nav_order: 5
parent: SDK
---

# Wallet

`BSV::Wallet::ProtoWallet` is the SDK's built-in cryptographic wallet. It is a concrete
implementation of the [BRC-100](https://brc.dev/100) interface — not a sample or duck type —
providing signing, encryption, HMAC, and key derivation with no transactions, storage, or
blockchain interaction.

Use `ProtoWallet` when you need BRC-100 crypto operations without a full wallet stack. For
transaction creation, UTXO management, and blockchain interaction, use the standalone
[`bsv-wallet`](https://github.com/sgbett/bsv-wallet) gem, which builds on top of ProtoWallet's crypto layer.

## When to use ProtoWallet

| Scenario | Use |
|----------|-----|
| Auth module integration (BRC-31/103) | `ProtoWallet` |
| Pure crypto operations (signing, encryption, HMAC) | `ProtoWallet` |
| Testing wallet-aware code in isolation | `ProtoWallet` |
| Transaction creation and signing | `bsv-wallet` |
| UTXO management and baskets | `bsv-wallet` |
| Blockchain queries | `bsv-wallet` |

## Constructor

```ruby
require 'bsv-sdk'

# Authenticated wallet — provide a PrivateKey
key    = BSV::Primitives::PrivateKey.generate
wallet = BSV::Wallet::ProtoWallet.new(key)

# Unauthenticated wallet — the 'anyone' root key (private key scalar = 1)
wallet = BSV::Wallet::ProtoWallet.new('anyone')
```

The `'anyone'` root key derives keys from a fixed scalar (`1`). It is not a security boundary
— anyone can reconstruct the same keys. Use it when no identity is required and the protocol
explicitly calls for unauthenticated derivation.

## Key concepts

### protocol_id

Operations are namespaced by a two-element array: `[security_level, protocol_name]`.

- `security_level` — integer `0`, `1`, or `2`
- `protocol_name` — string of lowercase letters, numbers, and spaces (5–400 characters)

Example: `[0, 'auth message']`, `[2, 'invoice payment']`.

### key_id

A per-operation string identifier (1–800 bytes). Combined with `protocol_id` and
`counterparty`, it produces a unique derived key per interaction.

### counterparty

Specifies whose public key anchors the derivation:

| Value | Meaning |
|-------|---------|
| `'self'` | Own identity key (self-directed derivation) |
| `'anyone'` | Fixed public key (no counterparty, public knowledge) |
| `"02abc..."` | A specific counterparty's compressed public key (66 hex chars) |

Counterparty defaults differ by operation — see the method tables below.

### for_self

When `true`, derives the key from your own identity looking toward the counterparty, rather
than deriving from the counterparty's perspective. Used in `get_public_key` and
`verify_signature` to retrieve your own derived signing key's public form.

## BRC-100 coverage

### Supported operations (12)

| Method | Area | Default counterparty | Notes |
|--------|------|---------------------|-------|
| `get_public_key` | Key management | `'self'` | Pass `identity_key: true` to get the root identity key |
| `encrypt` | Cryptography | `'self'` | AES-256-GCM with ECDH-derived key |
| `decrypt` | Cryptography | `'self'` | AES-256-GCM with ECDH-derived key |
| `create_hmac` | Cryptography | `'self'` | HMAC-SHA256 with derived symmetric key |
| `verify_hmac` | Cryptography | `'self'` | Raises `InvalidHmacError` on mismatch |
| `create_signature` | Cryptography | `'anyone'` | ECDSA, DER-encoded; accepts pre-computed hash |
| `verify_signature` | Cryptography | `'self'` | Raises `InvalidSignatureError` on failure |
| `reveal_counterparty_key_linkage` | Key management | — | BRC-69 Method 1; counterparty must be a hex pubkey |
| `reveal_specific_key_linkage` | Key management | — | BRC-69 Method 2; counterparty must be a hex pubkey |
| `list_certificates` | Certificates | — | Always returns `{ certificates: [] }` — no storage |
| `prove_certificate` | Certificates | — | Always raises `UnsupportedActionError` |

### Unsupported operations (17)

These methods raise `NotImplementedError`. Use `bsv-wallet` for full support.

| Method | Area |
|--------|------|
| `create_action` | Transactions |
| `sign_action` | Transactions |
| `abort_action` | Transactions |
| `list_actions` | Transactions |
| `internalize_action` | Transactions |
| `list_outputs` | Outputs |
| `relinquish_output` | Outputs |
| `acquire_certificate` | Certificates |
| `relinquish_certificate` | Certificates |
| `discover_by_identity_key` | Identity discovery |
| `discover_by_attributes` | Identity discovery |
| `authenticated?` | Authentication |
| `wait_for_authentication` | Authentication |
| `get_height` | Blockchain |
| `get_header_for_height` | Blockchain |
| `get_network` | Blockchain |
| `get_version` | Blockchain |

## Usage examples

### Identity key

```ruby
key    = BSV::Primitives::PrivateKey.generate
wallet = BSV::Wallet::ProtoWallet.new(key)

result = wallet.get_public_key(identity_key: true)
puts result[:public_key]  #=> "02abc..." (66-char compressed pubkey hex)
```

### Signing and verification

```ruby
key    = BSV::Primitives::PrivateKey.generate
wallet = BSV::Wallet::ProtoWallet.new(key)
data   = 'hello world'.bytes

# Sign (counterparty defaults to 'anyone' for signatures)
sig_result = wallet.create_signature(
  data:        data,
  protocol_id: [0, 'my protocol'],
  key_id:      'message-001'
)

# Verify — for_self: true retrieves the signer's own derived public key
wallet.verify_signature(
  signature:   sig_result[:signature],
  data:        data,
  protocol_id: [0, 'my protocol'],
  key_id:      'message-001',
  for_self:    true
)
#=> { valid: true }
```

To verify a signature produced by another party, pass their public key as `counterparty`:

```ruby
their_wallet = BSV::Wallet::ProtoWallet.new(BSV::Primitives::PrivateKey.generate)
their_pubkey = their_wallet.get_public_key(identity_key: true)[:public_key]

sig_result = their_wallet.create_signature(
  data:        data,
  protocol_id: [0, 'my protocol'],
  key_id:      'message-001',
  counterparty: wallet.get_public_key(identity_key: true)[:public_key]
)

wallet.verify_signature(
  signature:   sig_result[:signature],
  data:        data,
  protocol_id: [0, 'my protocol'],
  key_id:      'message-001',
  counterparty: their_pubkey
)
#=> { valid: true }
```

### Encryption and decryption

```ruby
alice = BSV::Wallet::ProtoWallet.new(BSV::Primitives::PrivateKey.generate)
bob   = BSV::Wallet::ProtoWallet.new(BSV::Primitives::PrivateKey.generate)

bob_pubkey   = bob.get_public_key(identity_key: true)[:public_key]
alice_pubkey = alice.get_public_key(identity_key: true)[:public_key]

# Alice encrypts for Bob
ciphertext = alice.encrypt(
  plaintext:   'secret message'.bytes,
  protocol_id: [0, 'secure chat'],
  key_id:      'msg-001',
  counterparty: bob_pubkey
)[:ciphertext]

# Bob decrypts from Alice
plaintext = bob.decrypt(
  ciphertext:  ciphertext,
  protocol_id: [0, 'secure chat'],
  key_id:      'msg-001',
  counterparty: alice_pubkey
)[:plaintext]

plaintext.pack('C*')  #=> "secret message"
```

### HMAC round-trip

```ruby
wallet = BSV::Wallet::ProtoWallet.new(BSV::Primitives::PrivateKey.generate)
data   = 'data to authenticate'.bytes

hmac = wallet.create_hmac(
  data:        data,
  protocol_id: [0, 'data integrity'],
  key_id:      'record-42'
)[:hmac]

# Returns { valid: true } or raises InvalidHmacError
wallet.verify_hmac(
  data:        data,
  hmac:        hmac,
  protocol_id: [0, 'data integrity'],
  key_id:      'record-42'
)
```

## Error handling

| Exception | Raised when |
|-----------|-------------|
| `BSV::Wallet::InvalidParameterError` | A parameter fails validation (bad `protocol_id`, `key_id`, or `counterparty`) |
| `BSV::Wallet::InvalidHmacError` | `verify_hmac` — HMAC does not match |
| `BSV::Wallet::InvalidSignatureError` | `verify_signature` — signature does not verify |
| `BSV::Wallet::UnsupportedActionError` | `prove_certificate` — always raised |
| `NotImplementedError` | Any of the 17 unsupported BRC-100 methods |

All wallet errors inherit from `BSV::Wallet::Error` and carry a machine-readable `code`
matching the BRC-100 error structure.

## Relationship to bsv-wallet

`ProtoWallet` is the cryptographic foundation. The `bsv-wallet` gem implements the remaining
17 BRC-100 methods by adding transaction construction, UTXO storage, basket management, and
blockchain queries — all built on top of ProtoWallet's key derivation and crypto operations.

```
ProtoWallet          — 12 BRC-100 methods (crypto only, in bsv-sdk)
     └── bsv-wallet  — all 28 BRC-100 methods (+ transactions, storage, blockchain)
```

If your use case only requires signing, encryption, or HMAC — for example, implementing the
Auth module or a message authentication layer — `ProtoWallet` is sufficient and keeps your
dependency footprint small.

## Wire layer

The BRC-103 wire layer lets you call any BRC-100 wallet over a binary transport. The SDK
provides client, server, and HTTP substrate classes, all in the `BSV::Wallet` namespace.

For a full walkthrough with examples, see the **[BRC-103 wire layer guide](../guides/brc-103-wire.md)**.

### WalletWire

`BSV::Wallet::WalletWire` is the transport abstraction — a module with a single method:

```
def transmit_to_wallet(message)  # binary String in, binary String out
```

Include it in any class and implement `transmit_to_wallet` to produce a concrete transport.

### WalletWireTransceiver

The client. Wraps any `WalletWire` and exposes the full BRC-100 interface as Ruby methods.
Every call serialises its keyword arguments to a binary request frame, transmits via the wire,
and deserialises the binary result frame back to a Ruby hash.

```ruby
# @param wire [#transmit_to_wallet] any WalletWire implementation
client = BSV::Wallet::WalletWireTransceiver.new(wire)
result = client.get_public_key(identity_key: true)
# result[:public_key] is a 33-byte compressed pubkey as a binary string.
# To inspect it as hex: result[:public_key].unpack1('H*')  # => "0279be..."
```

### WalletWireProcessor

The server. Wraps any `Interface::BRC100` wallet and processes binary request frames,
returning binary result frames. It also includes `WalletWire`, so it can be passed directly
to a `WalletWireTransceiver` for in-process loopback.

```ruby
# @param wallet [Interface::BRC100] any BRC-100 wallet
processor = BSV::Wallet::WalletWireProcessor.new(proto_wallet)
```

Error boundary: `NotImplementedError` → code 2 (`UnsupportedActionError`);
`BSV::Wallet::Error` subclasses → framed with their code; any other `StandardError` → code 1.

### Substrates::HTTPWalletWire

HTTP transport using binary frames (`Content-Type: application/octet-stream`).
Posts to `{base_url}/wallet`.

```ruby
# Direct construction
wire   = BSV::Wallet::Substrates::HTTPWalletWire.new(base_url: 'https://wallet.example')
client = BSV::Wallet::WalletWireTransceiver.new(wire)

# Convenience factory — returns a WalletWireTransceiver directly
client = BSV::Wallet::Substrates::HTTPWalletWire.client(base_url: 'https://wallet.example')

# With extra headers (e.g. auth)
client = BSV::Wallet::Substrates::HTTPWalletWire.client(
  base_url: 'https://wallet.example',
  headers:  { 'Authorization' => 'Bearer token' }
)
```

### Substrates::HTTPWalletJSON

JSON-over-HTTP substrate. Directly implements `Interface::BRC100` — does not use the binary
frame codec. Posts to `{base_url}/v1/wallet/{camelCaseMethodName}` with
`Content-Type: application/json`. Request and response hashes are automatically converted
between Ruby snake_case and camelCase.

```ruby
client = BSV::Wallet::Substrates::HTTPWalletJSON.new(
  base_url: 'https://wallet.example.com'
)
client.get_network  # => { network: 'mainnet' }
```

### Wire layer errors

All wallet errors inherit from `BSV::Wallet::Error` and carry a numeric `code`. When the server
returns an error frame, the client raises the matching subclass automatically.

| Class | Code | Raised when |
|-------|------|-------------|
| `BSV::Wallet::Error` | 1 | Generic operation failure; network errors on the client side |
| `BSV::Wallet::UnsupportedActionError` | 2 | Method not supported by this wallet implementation (`NotImplementedError`) |
| `BSV::Wallet::InvalidHmacError` | 3 | `verify_hmac` — HMAC does not match |
| `BSV::Wallet::InvalidSignatureError` | 4 | `verify_signature` — signature does not verify |
| `BSV::Wallet::InsufficientFundsError` | 5 | Wallet has insufficient funds for the operation |
| `BSV::Wallet::InvalidParameterError` | 6 | A required parameter is missing or invalid |
| `BSV::Wallet::ReviewActionsError` | 7 | Actions require user review before processing |

Use `BSV::Wallet.error_from_wire(code, message, stack)` to manually rehydrate an error frame into
the correct subclass. The transceiver calls this automatically when it reads an error frame.

```ruby
begin
  client.create_action(description: 'pay invoice', outputs: [])
rescue BSV::Wallet::InsufficientFundsError => e
  # e.code == 5, e.message is the original server message
rescue BSV::Wallet::Error => e
  # catch-all for codes 1–7
end
```
