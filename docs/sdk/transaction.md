---
title: Transaction
nav_order: 3
parent: SDK
---

# Transaction

The `BSV::Transaction` module handles building, signing, serialising, and verifying Bitcoin transactions.

## Building a Transaction

### Inputs

Each input references a previous transaction output (UTXO) by its wire-order transaction ID and output index:

```ruby
input = BSV::Transaction::TransactionInput.new(
  prev_wtxid: BSV::Transaction::TransactionInput.wtxid_from_hex(
    '5884e5db9de218238671572340b207ee85b628074e7e467096c267266baf77a4'
  ),
  prev_tx_out_index: 0
)

# Required for sighash computation
input.source_satoshis = 100_000
input.source_locking_script = BSV::Script::Script.p2pkh_lock(pubkey_hash)
```

`wtxid_from_hex` converts a display-order hex txid to wire-order binary (the native byte order used internally). See the **[wtxid/dtxid convention](../reference/wtxid-dtxid.md)** for why.

### Outputs

Each output specifies a satoshi amount and a locking script:

```ruby
# Payment output
output = BSV::Transaction::TransactionOutput.new(
  satoshis: 50_000,
  locking_script: BSV::Script::Script.p2pkh_lock(recipient_hash)
)

# Data output
data_output = BSV::Transaction::TransactionOutput.new(
  satoshis: 0,
  locking_script: BSV::Script::Script.op_return('data'.b)
)
```

### Assembling

```ruby
tx = BSV::Transaction::Tx.new
tx.add_input(input)
tx.add_output(output)
tx.add_output(data_output)
```

Both `add_input` and `add_output` return `self`, so calls can be chained.

## Signing

### Direct Signing

Sign a specific input with a private key (P2PKH):

```ruby
tx.sign(0, private_key)
```

This computes the BIP-143 sighash, signs it, and sets the unlocking script on the input.

### Template Signing

For more flexible signing, attach unlocking script templates to inputs:

```ruby
input.unlocking_script_template = BSV::Transaction::P2PKH.new(private_key)

# Sign all unsigned inputs at once
tx.sign_all
```

Templates are the recommended approach when building transactions with multiple inputs, potentially from different keys.

### Custom Sighash Types

The default sighash type is `ALL|FORKID`. Other types are available:

```ruby
# Sign with NONE|FORKID (outputs can be modified by others)
template = BSV::Transaction::P2PKH.new(
  private_key,
  sighash_type: BSV::Transaction::Sighash::NONE_FORK_ID
)

# Available sighash types
BSV::Transaction::Sighash::ALL_FORK_ID                    # 0x41
BSV::Transaction::Sighash::NONE_FORK_ID                   # 0x42
BSV::Transaction::Sighash::SINGLE_FORK_ID                 # 0x43
BSV::Transaction::Sighash::ALL_FORK_ID_ANYONE_CAN_PAY     # 0xC1
BSV::Transaction::Sighash::NONE_FORK_ID_ANYONE_CAN_PAY    # 0xC2
BSV::Transaction::Sighash::SINGLE_FORK_ID_ANYONE_CAN_PAY  # 0xC3
```

All sighash types include the FORKID flag, as required by BSV.

## Sighash Computation

Access the raw sighash preimage and digest directly:

```ruby
# BIP-143 preimage (useful for debugging or external signers)
preimage = tx.sighash_preimage(0)

# Sighash digest (double-SHA-256 of the preimage)
hash = tx.sighash(0)

# With a custom subscript
hash = tx.sighash(0, BSV::Transaction::Sighash::ALL_FORK_ID, subscript: custom_script)
```

## Serialisation

### Binary and Hex

```ruby
hex = tx.to_hex        # hex-encoded raw transaction
binary = tx.to_binary  # raw transaction bytes
```

### Parsing

```ruby
tx = BSV::Transaction::Tx.from_hex('0100000001...')
tx = BSV::Transaction::Tx.from_binary(raw_bytes)

# Parse with offset tracking (for embedded transactions)
tx, bytes_consumed = BSV::Transaction::Tx.from_binary_with_offset(data, offset)
```

### Transaction ID

```ruby
wtxid = tx.wtxid       # 32 bytes (wire order — for computation and storage)
dtxid = tx.dtxid       # 64-char hex (display order — for JSON and UIs)
```

## Fee Estimation

The SDK estimates transaction size to calculate fees via `FeeModel` implementations:

```ruby
# Total values
tx.total_input_satoshis    # sum of all input source_satoshis
tx.total_output_satoshis   # sum of all output satoshis

# Estimated fee at the default rate (100 sat/kB)
fee_model = BSV::Transaction::FeeModels::SatoshisPerKilobyte.new
fee = fee_model.compute_fee(tx)

# Custom fee rate (e.g. 500 sat/kB)
fee_model = BSV::Transaction::FeeModels::SatoshisPerKilobyte.new(value: 500)
fee = fee_model.compute_fee(tx)
```

Fee estimation accounts for:

- Signed inputs: actual serialised size
- Template inputs: `estimated_length` from the template
- Unsigned inputs (no template): 148 bytes (standard P2PKH estimate)

### FeeModel and FeeModels

`Transaction::FeeModel` is the abstract base class; concrete implementations live in `Transaction::FeeModels`. Two are bundled:

**`FeeModels::SatoshisPerKilobyte`** — simple static rate, suitable for most applications:

```ruby
model = BSV::Transaction::FeeModels::SatoshisPerKilobyte.new           # default: 100 sat/kB
model = BSV::Transaction::FeeModels::SatoshisPerKilobyte.new(value: 50)
fee   = model.compute_fee(tx)  #=> Integer (satoshis)
```

**`FeeModels::LivePolicy`** — fetches the current mining fee rate from an ARC `/v1/policy` endpoint. The fetched rate is cached for a configurable TTL (default `300` seconds) so repeated calls to `compute_fee` do not repeatedly query the API. On fetch failure the model falls back to the last cached rate, or to `fallback_rate` if nothing has been cached yet:

```ruby
model = BSV::Transaction::FeeModels::LivePolicy.new(
  arc_url:      'https://arc.taal.com',
  fallback_rate: 100,       # sat/kB used when fetch fails and no cached rate
  cache_ttl:     60         # override the default 300-second TTL
)
fee = model.compute_fee(tx)

BSV::Transaction::FeeModels::LivePolicy::DEFAULT_CACHE_TTL  #=> 300
```

`LivePolicy.default` returns a policy backed by TAAL's public ARC instance with a 100 sat/kB fallback. Pass `api_key:` for authenticated access.

Custom fee models implement one method: `compute_fee(transaction) -> Integer`.

## ChainTrackers

`Transaction::ChainTracker` is the data-source interface used by `Beef#verify`, `MerklePath#verify`, and `Tx#verify`. It answers one question: "is this merkle root valid for this block height?" The base class itself **does not cache** — it dispatches directly to the underlying network provider on every call. If you want caching, subclass it and implement it there.

```ruby
# Provider-backed default (GorillaPool)
tracker = BSV::Transaction::ChainTracker.default
tracker = BSV::Transaction::ChainTracker.default(testnet: true)

# WhatsOnChain-backed
tracker = BSV::Transaction::ChainTrackers::WhatsOnChain.new
tracker = BSV::Transaction::ChainTrackers::WhatsOnChain.default

# Duck-typed in-memory tracker (for testing or offline use)
class FixedTracker < BSV::Transaction::ChainTracker
  def initialize(headers)
    super()
    @headers = headers
  end

  def valid_root_for_height?(root, height)
    @headers[height]&.casecmp(root)&.zero?
  end

  def current_height
    @headers.keys.max
  end
end

tracker = FixedTracker.new(800_000 => 'abcd1234...')
mp.verify('txid_hex...', tracker)
```

Any object responding to `valid_root_for_height?` and `current_height` satisfies the interface — inheriting from `Transaction::ChainTracker` is optional.

## Script Verification

Verify that an input's unlocking script satisfies the locking script:

```ruby
valid = tx.verify_input(0)  #=> true or false
```

## BEEF (Background Evaluation Extended Format)

BEEF bundles transactions with their merkle proofs for SPV verification. The SDK supports BRC-62 (V1), BRC-96 (V2), and BRC-95 (Atomic BEEF).

### Parsing BEEF

```ruby
beef = BSV::Transaction::Beef.from_hex(beef_hex)

# Structure
beef.version         # version constant
beef.bumps           # Array<MerklePath> — merkle proofs
beef.transactions    # Array<BeefTx> — transaction entries

# Find a specific transaction
tx = beef.find_transaction(txid_bytes)
```

BEEF automatically wires source transactions: inputs that reference other transactions in the bundle will have their `source_transaction` set.

### Extracting a transaction from a BEEF

`Transaction.from_beef` returns the subject transaction with full ancestry wired, including late-bound BUMP attachment for ancestors stored as raw transactions alongside a separately-bundled merkle proof:

```ruby
tx = BSV::Transaction::Tx.from_beef(beef_bytes)

# Source data is derived from the wired ancestry — no need to set
# source_satoshis or source_locking_script explicitly.
ef_bytes = tx.to_ef_hex  # ready for ARC broadcast
```

This is the canonical flow for re-broadcasting a received BEEF (e.g. after `internalize_action`). `to_ef_hex` resolves source satoshis and locking scripts directly from `source_transaction.outputs[prev_tx_out_index]` when the explicit fields are not set on an input.

### Transaction Entries

Each entry in a BEEF bundle has a format:

```ruby
beef.transactions.each do |entry|
  case entry.format
  when BSV::Transaction::Beef::FORMAT_RAW_TX
    # Full transaction, no merkle proof
    entry.transaction
  when BSV::Transaction::Beef::FORMAT_RAW_TX_AND_BUMP
    # Full transaction with merkle proof
    entry.transaction
    entry.transaction.merkle_path  # the associated MerklePath
  when BSV::Transaction::Beef::FORMAT_TXID_ONLY
    # Just the txid (known to the recipient)
    entry.known_txid
  end
end
```

### Serialising BEEF

```ruby
# Standard V2 format
hex = beef.to_hex
binary = beef.to_binary

# Atomic BEEF (BRC-95) — wraps V2 with a subject txid
atomic = beef.to_atomic_binary(subject_txid)
```

## BeefParty: Multi-Party Exchange

`Transaction::BeefParty` extends `Transaction::Beef` to track per-party knowledge: each named counterparty is associated with the set of wtxids it is already known to hold. This avoids re-transmitting transaction data and merkle proofs that the recipient already possesses, keeping BEEF bundles compact in multi-step exchange flows.

### Why it exists

A complete `Transaction::Beef` carries every transaction it depends on, either with a merkle path proof or with all of its input transactions inlined. That's the invariant readers rely on for SPV verification without consulting a block explorer.

The cost shows up in a typical wallet-chained-creation loop:

1. Query a wallet storage provider for spendable outputs.
2. The provider returns a `Transaction::Beef` validating those outputs.
3. Construct a new transaction using some of those outputs as inputs, sending a `Transaction::Beef` that validates the inputs.
4. The provider returns the new raw transaction and a `Transaction::Beef` validating the change outputs you'll later spend.
5. Return to step 1, building on old and new spendable outputs.

As soon as transaction creation outpaces the block mining rate, the same proof tree is sent back and forth across multiple rounds — most of the bundle is data the counterparty already has. `Transaction::BeefParty` is the bookkeeping layer that lets each side track what the other has already seen and trim resends down to only the new material.

### Worked example

```ruby
require 'bsv-sdk'

# Party A starts with a BEEF received from elsewhere
party = BSV::Transaction::BeefParty.new(%w[alice bob])
party.merge_beef_from_party('alice', alice_beef_binary)

# Tell the bundle that bob already holds a specific transaction
bob_known_wtxid = BSV::Transaction::TransactionInput.wtxid_from_hex(
  'abcd1234...'  # display-order txid that bob definitely has
)
party.add_known_wtxids_for_party('bob', [bob_known_wtxid])

# Produce a trimmed Beef for bob — TXID-only entries bob already knows are removed
beef_for_bob = party.trimmed_beef_for_party('bob')

# Bob can verify the trimmed bundle
bob_party = BSV::Transaction::BeefParty.new(['bob'])
bob_party.merge_beef_from_party('bob', beef_for_bob)
```

`trimmed_beef_for_party` returns a plain `Transaction::Beef` (not a `Transaction::BeefParty`) and does not mutate the original bundle. RAW_TX and RAW_TX_AND_BUMP entries are always retained even when the party knows the txid — only TXID-only entries are candidates for removal.

### New methods on `Transaction::Beef`

Four public methods were added to support `Transaction::BeefParty`:

| Method | Purpose |
|--------|---------|
| `merge_txid_only(wtxid)` | Add a TXID-only entry if no entry for that wtxid exists yet; no-ops on stronger existing entries. |
| `clone` | Return a shallow copy with independent `@bumps` and `@transactions` arrays. |
| `trim_known_wtxids(known_wtxids)` | Return a new `Transaction::Beef` with TXID-only entries removed for the supplied set of wtxids; renumbers bump indices. |
| `valid_wtxids` | Return the wtxids of all transactions in the bundle that are proven or chain back to proven transactions. |

See `spec/bsv/transaction/beef_party_spec.rb` for a full worked example including cross-SDK conformance vectors against the TS SDK.

## Merkle Paths (BRC-74)

Merkle paths (BUMPs) prove transaction inclusion in a block. A `MerklePath` stores the minimum set of intermediate hashes needed to recompute a block's merkle root from one or more transaction IDs.

### Parsing

```ruby
mp = BSV::Transaction::MerklePath.from_hex(bump_hex)
mp = BSV::Transaction::MerklePath.from_binary(raw_bytes).first  # returns [path, bytes_consumed]

mp.block_height  # Integer — the block height
mp.path          # Array<Array<PathElement>> — tree levels; level 0 holds the leaf(es)
```

### Construction

```ruby
mp = BSV::Transaction::MerklePath.new(
  block_height: 800_000,
  path: [
    [
      BSV::Transaction::MerklePath::PathElement.new(offset: 0, hash: tx_wtxid,      txid: true),
      BSV::Transaction::MerklePath::PathElement.new(offset: 1, hash: sibling_wtxid)
    ]
    # upper levels follow; omit when the sibling is a duplicate (set duplicate: true)
  ]
)
```

Hashes are stored in **wire order** (32-byte binary, reversed from display order). Level 0 must contain at least one `txid: true` leaf — that flag marks the transaction being proved, not a txid value.

### Computing the Merkle Root

```ruby
# Pass a display-order (reversed) hex txid; returns display-order hex root
root_hex = mp.compute_root_hex('aabb...')   # 64-char hex

# Auto-detect: uses the txid-flagged leaf in level 0
root_hex = mp.compute_root_hex
```

### Verification

```ruby
# Verify against a chain tracker — checks root matches the block at block_height
valid = mp.verify('aabb...', tracker)  #=> true / false
```

### Combining Paths

Merge two paths for the same block (e.g. proving two transactions from the same block):

```ruby
mp1.combine(mp2)
# mp1 now contains the union of both paths; trim compresses the result
mp1.trim  # remove redundant intermediate nodes
```

### Caching and Performance

`Transaction::Tx` memoises the bytes and digests that sighash computation reads across many inputs. The cache is a three-layer Russian-doll structure (L1 per-struct binaries → L2 wire format → L3 sighash component hashes). Most mutations are handled automatically:

| Mutation | Result |
|---|---|
| `input.sequence=` | Invalidates `hash_sequence`, L1, L2 |
| `input.unlocking_script=` | Invalidates L1, L2 (not sighash components) |
| `output.satoshis=` | Invalidates `hash_outputs_*`, L1, L2 |
| `output.locking_script=` | Invalidates `hash_outputs_*`, L1, L2 |
| `tx.add_input` / `tx.add_output` | Invalidates all cache layers |
| Direct `tx.inputs <<` / `pop` | **Not auto-invalidated** — call `invalidate_caches` |

```ruby
tx.inputs.pop         # bypasses the setter surface
tx.invalidate_caches  # clears all cache layers; returns self
```

**One-owner constraint:** `add_input` and `add_output` bind an input or output to the owning transaction by setting a private `@owning_tx` backref. Passing the same object to a *different* `Transaction::Tx` raises `ArgumentError`. Construct a fresh `TransactionInput` / `TransactionOutput` per transaction.

See [Sighash & Wire Cache](../reference/sighash-cache.md) for the full invalidation contract, thread-safety notes, and the "build → sign/verify" idiom.

## Complete Example

Putting it all together — build, sign, and serialise a transaction:

```ruby
require 'bsv-sdk'

# Keys
sender = BSV::Primitives::PrivateKey.generate
recipient = BSV::Primitives::PrivateKey.generate

sender_lock = BSV::Script::Script.p2pkh_lock(sender.public_key.hash160)
recipient_lock = BSV::Script::Script.p2pkh_lock(recipient.public_key.hash160)

# Build
tx = BSV::Transaction::Tx.new

input = BSV::Transaction::TransactionInput.new(
  prev_wtxid: BSV::Transaction::TransactionInput.wtxid_from_hex(utxo_txid),
  prev_tx_out_index: 0
)
input.source_satoshis = 1_000_000
input.source_locking_script = sender_lock
input.unlocking_script_template = BSV::Transaction::P2PKH.new(sender)
tx.add_input(input)

# Payment
tx.add_output(BSV::Transaction::TransactionOutput.new(
  satoshis: 500_000,
  locking_script: recipient_lock
))

# Change
fee = BSV::Transaction::FeeModels::SatoshisPerKilobyte.new.compute_fee(tx)
tx.add_output(BSV::Transaction::TransactionOutput.new(
  satoshis: 1_000_000 - 500_000 - fee,
  locking_script: sender_lock
))

# Sign and serialise
tx.sign_all
puts tx.to_hex
puts "txid: #{tx.dtxid}"
```
