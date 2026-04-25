# Getting Started

## Installation

Add the gem to your `Gemfile`:

```ruby
gem 'bsv-sdk'
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install bsv-sdk
```

The SDK has **no required external dependencies** — it uses only Ruby's standard library. Elliptic curve operations use a pure Ruby implementation with an optional native C extension for acceleration (see [secp256k1](../general/secp256k1.md)). OpenSSL is used for hashing, HMAC, PBKDF2, and symmetric encryption.

## Quick Start

```ruby
require 'bsv-sdk'
```

The SDK is organised into four modules:

| Module | Purpose |
|--------|---------|
| `BSV::Primitives` | Keys, signing, hashing, encryption, HD keys |
| `BSV::Script` | Script parsing, construction, templates |
| `BSV::Transaction` | Building, signing, serialisation, BEEF |
| `BSV::Network` | Broadcasting, chain tracking, SPV verification |

## Generate a Key Pair

```ruby
# Generate a new random private key
private_key = BSV::Primitives::PrivateKey.generate

# Export as WIF (Wallet Import Format)
wif = private_key.to_wif
#=> "L2huFnhCerfX..."

# Derive the public key and address
public_key = private_key.public_key
address = public_key.address
#=> "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
```

## Build a Simple Transaction

This example builds a P2PKH transaction that spends one input and creates two outputs: an OP_RETURN data carrier and a change output.

```ruby
# Set up keys
private_key = BSV::Primitives::PrivateKey.generate
pubkey_hash = private_key.public_key.hash160
locking_script = BSV::Script::Script.p2pkh_lock(pubkey_hash)

# Create the transaction
tx = BSV::Transaction::Transaction.new

# Add an input (referencing a previous UTXO)
input = BSV::Transaction::TransactionInput.new(
  prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(
    'a477af6b2667c29670467e4e0728b685ee07b240235771862318e29ddbe58458'
  ),
  prev_tx_out_index: 0
)
input.source_satoshis = 1_000_000
input.source_locking_script = locking_script
tx.add_input(input)

# Add an OP_RETURN output (data carrier, zero satoshis)
tx.add_output(BSV::Transaction::TransactionOutput.new(
  satoshis: 0,
  locking_script: BSV::Script::Script.op_return('hello world'.b)
))

# Add a change output (send remaining funds back)
fee = tx.estimated_fee
tx.add_output(BSV::Transaction::TransactionOutput.new(
  satoshis: 1_000_000 - fee,
  locking_script: locking_script
))

# Sign the input
tx.sign(0, private_key)

# Broadcast via Arcade (GorillaPool)
arc = BSV::Network::ARC.default
response = arc.broadcast(tx)
puts response.txid
```

## Using Templates for Signing

For transactions with multiple inputs, use unlocking script templates. This lets `sign_all` handle each input automatically:

```ruby
tx = BSV::Transaction::Transaction.new

# Create inputs with templates
input = BSV::Transaction::TransactionInput.new(
  prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(utxo_txid),
  prev_tx_out_index: 0
)
input.source_satoshis = 50_000
input.source_locking_script = locking_script
input.unlocking_script_template = BSV::Transaction::P2PKH.new(private_key)
tx.add_input(input)

# Add outputs...

# Sign all inputs at once
tx.sign_all
```

## Coming from TS or Go?

If you already know the TypeScript or Go BSV SDKs, most of the API is a direct translation to Ruby idioms. The common cases:

| TS / Go | Ruby | Notes |
|---|---|---|
| `key.toPublicKey()` | `key.public_key` | Derived properties are bare nouns, not `to_*` methods |
| `tx.getTxid()` | `tx.txid_hex` | No `get_` prefix (use `txid` for raw bytes) |
| `input.setSourceSatoshis(5000)` | `input.source_satoshis = 5000` | Setters use assignment syntax |
| `tx.toHex()` | `tx.to_hex` | Format conversions keep `to_` |
| `Transaction.fromBinary(data)` | `Transaction.from_binary(data)` | Constructors use `from_` |
| `script.isP2PKH()` | `script.p2pkh?` | Boolean methods end in `?`, drop `is`/`has` prefix |
| `createAction({ description, inputs })` | `create_action(description:, inputs:)` | Options objects become keyword arguments |

**BRC-100 wire protocol methods are the exception** — `get_public_key`, `get_height`, `is_authenticated`, `list_outputs` keep their protocol names because they *are* the protocol names. Don't try to rename them.

For the full picture including edge cases and rationale, see **[Naming Conventions](../general/naming-conventions.md)**.

## What's Next

- **[Primitives Guide](../sdk/primitives.md)** — key management, signing, encryption, HD keys
- **[Script Guide](../sdk/script.md)** — script construction, templates, detection
- **[Transaction Guide](../sdk/transaction.md)** — building, signing, fee estimation, BEEF
- **[Network Guide](../sdk/network.md)** — broadcasting, chain tracking, SPV verification
- **[Wallet Guide](../gems/wallet.md)** — BRC-100 wallet interface, storage, broadcasting
- **[MCP Server Guide](../general/mcp.md)** — use BSV operations as AI assistant tools via Claude Code
- **[Naming Conventions](../general/naming-conventions.md)** — Ruby naming idioms for developers coming from other SDKs
