# Transaction IDs: wtxid and dtxid

## Why two representations?

A transaction ID is a SHA-256d hash — 32 bytes. Those bytes have a natural order, the order the hash function produces them. This is the **wire order**: the byte sequence you find inside serialised transactions, block headers, and merkle trees. Every time Bitcoin's binary protocol references a transaction, it uses this order.

But early Bitcoin had a cosmetic quirk. When Satoshi wrote the RPC code to display transaction and block hashes as hex strings, the bytes were reversed. The likely reason: SHA-256d hashes used as proof-of-work targets have leading zero bytes, and reversing puts those zeros at the front of the displayed string, making difficulty visually obvious. A block hash like `000000000019d6689c...` reads naturally as "many leading zeros = hard to find".

This reversed representation became the **display order** — the format shown by block explorers, returned by JSON-RPC calls, and copy-pasted by developers. It stuck, and every Bitcoin-derived system has inherited it.

The consequence is that Bitcoin has always had two ways to express the same 32-byte hash, with no reliable way to tell which one you're holding. The variable name `txid` could mean either. This ambiguity has caused an extraordinary number of bugs across every Bitcoin implementation over the past 15+ years, from double-counted transactions to malformed merkle proofs.

## The SDK's naming convention

This SDK eliminates the ambiguity by making the byte order explicit in every name:

| Name | Type | Byte order | When to use |
|------|------|-----------|-------------|
| `wtxid` | Binary string (32 bytes) | Wire order | Internal computation, storage, binary protocols |
| `dtxid` / `dtxid_hex` | Hex string (64 chars) | Display order | JSON APIs, user interfaces, logs, block explorers |
| `txid` | Varies | Spec-mandated | Only where an external specification requires this exact name |

**`wtxid`** — wire-order transaction ID. The raw bytes as SHA-256d produces them, and as they appear in serialised Bitcoin data. This is what you store, compare, and compute with.

**`dtxid`** — display-order transaction ID. The bytes reversed and hex-encoded. This is what you show to humans and send over JSON interfaces.

**`txid`** — reserved for cases where an external specification (BRC-100, BRC-74, ARC API) mandates this exact field name. These always appear with a boundary comment explaining which spec requires them and what byte order is expected.

### Examples

```ruby
tx = BSV::Transaction::Transaction.from_hex(raw_hex)

# Wire order — for computation, storage, binary protocols
tx.wtxid            # => 32-byte binary string
tx.inputs.first.prev_wtxid  # => 32 bytes referencing the previous output

# Display order — for JSON, UIs, logs
tx.dtxid            # => "a1b2c3d4..." (64-char hex, reversed bytes)
tx.dtxid_hex        # => same as dtxid

# Conversion at input boundaries
BSV::Transaction::TransactionInput.wtxid_from_hex("a1b2c3d4...")
# => 32-byte binary (reverses the hex back to wire order)

# Display conversion on inputs
tx.inputs.first.dtxid_hex   # => display-order hex of the referenced tx
```

## Wire order by default

The SDK's internal principle is straightforward: **use wire order everywhere, convert only when forced to**.

Transaction IDs are born in wire order — `SHA256d(serialised_tx)` produces wire-order bytes. Reversing them to display order and back again is wasted work and a source of bugs. So the SDK keeps everything in wire order internally and only converts to display order at the boundaries where an external system demands it.

This means:

- **All internal variables** hold `wtxid` (wire-order binary)
- **All method parameters** that accept transaction IDs expect wire-order binary
- **Cross-gem interfaces** (SDK → wallet, SDK → attest) pass wire-order binary
- **Storage** uses wire-order binary (bytea columns, binary fields)
- **Merkle computations** use wire-order throughout — no reversals inside the tree
- **Beef serialisation** uses wire-order throughout — transaction references, dedup keys, sorting

No conversion happens until you reach a boundary that requires display order.

### The boundaries

Conversion to display order (`dtxid`) happens at exactly two kinds of boundary:

**1. JSON interfaces**

Any API that serialises data as JSON. JSON has no binary type, so transaction IDs must be hex-encoded. By convention (inherited from Bitcoin's RPC layer), JSON APIs use display-order hex.

```ruby
# ARC broadcast response
{ "txid" => "a1b2c3d4..." }  # display-order hex — ARC API spec

# BRC-100 create_action return value
{ txid: tx.dtxid }            # display-order hex — BRC-100 spec

# WhatsOnChain REST API
"/tx/#{tx.dtxid}"             # display-order hex in URL path
```

**2. User interfaces**

Any context where a human reads a transaction ID: HTML pages, CLI output, log messages, error messages, block explorer links.

```ruby
# Log message
logger.info("Broadcast #{tx.dtxid}")

# Error message
raise "Input #{input.dtxid_hex} not found"

# Link to block explorer
"https://whatsonchain.com/tx/#{tx.dtxid}"
```

### What is NOT a boundary

These are internal interfaces — they stay in wire order:

- **Ruby method calls** between SDK classes (Transaction, Beef, MerklePath)
- **Ruby method calls** between gems (bsv-sdk, bsv-wallet, bsv-attest)
- **Database storage** (PostgreSQL bytea, binary columns)
- **Binary serialisation** (transaction format, BEEF format, merkle paths)
- **Hash table keys** for deduplication or indexing
- **Comparisons** between transaction IDs

```ruby
# Internal — always wire order
beef.find_transaction(tx.wtxid)
merkle_path.compute_root(tx.wtxid)
seen[tx.wtxid] = true
input.prev_wtxid == source_tx.wtxid
```

### The conversion rule

If you're writing code that touches transaction IDs, the decision is simple:

1. Am I producing JSON output or displaying text to a human? → Use `dtxid`
2. Everything else → Use `wtxid`

There is no third case. If you find yourself reaching for `txid` without either prefix, stop and determine which of the two you actually need.

## Format constants

The SDK defines two constants for downstream consumers that need to make byte order explicit in API responses:

```ruby
BSV::TXID_FORMAT_WIRE    # => 'wire'
BSV::TXID_FORMAT_DISPLAY # => 'display'
```

These are available for inclusion in API response metadata, configuration, or documentation. They make the byte order self-describing rather than assumed:

```ruby
{
  txid: tx.dtxid,
  txid_format: BSV::TXID_FORMAT_DISPLAY
}
```

## BRC-74 note

`MerklePath::PathElement` has a `txid` boolean attribute. This is **not** a transaction ID value — it's a BRC-74 spec field that flags whether a given leaf in the merkle path is a transaction (as opposed to a provided hash). The name comes from the specification and is not subject to the wtxid/dtxid convention.
