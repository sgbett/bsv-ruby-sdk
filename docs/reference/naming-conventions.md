---
title: Naming Conventions
nav_order: 1
parent: Reference
---

# Naming Conventions

This SDK follows idiomatic Ruby naming, which differs in several ways from the TypeScript and Go BSV SDKs. If you're familiar with those SDKs, the patterns here will translate directly once you know the rules.

The guiding principle: **Ruby reads like English**. Methods that return values behave like nouns (`key.public_key`), methods that ask questions end with a question mark (`valid?`), and conversions are explicit (`to_hex`, `from_hex`).

## The nine rules

### 1. camelCase → snake_case

Every method and parameter name uses snake_case. This applies universally — no exceptions.

```ruby
# TS:   tx.lockTime
# Ruby: tx.lock_time

# TS:   createAction({ outputDescription: "..." })
# Ruby: create_action(output_description: "...")
```

### 2. Predicates end in `?`, drop `is`/`has` prefix

Boolean-returning methods end in `?`. The `is` prefix is dropped entirely; `has` is usually dropped too (kept only when the method would be ambiguous without it).

```ruby
# TS:   script.isP2PKH()      → Ruby: script.p2pkh?
# TS:   script.isOpReturn()   → Ruby: script.op_return?
# TS:   beef.isValid()        → Ruby: beef.valid?
```

The `?` is part of the method name and cannot be omitted.

### 3. Getters drop the `get_` prefix

Ruby treats attribute access and method calls identically, so `get_` is redundant noise. A bare noun is already a method call.

```ruby
# TS:   tx.getVersion()     → Ruby: tx.version
# TS:   tx.getLockTime()    → Ruby: tx.lock_time
# TS:   beef.getBumps()     → Ruby: beef.bumps
```

Note: `tx.wtxid` returns the transaction ID as **wire-order binary** (for computation and storage). Use `tx.dtxid` for the display-order hex that most TS/Go APIs return from `getTxid()`. See the **[wtxid/dtxid convention](wtxid-dtxid.md)** for the full rule.

### 4. Setters use assignment syntax

Ruby has first-class support for assignment methods. `obj.foo = bar` calls `foo=(bar)` on the object.

```ruby
# TS:   input.setSourceSatoshis(5000)    → Ruby: input.source_satoshis = 5000
# TS:   input.setUnlockingScript(script) → Ruby: input.unlocking_script = script
```

Combined with rule 3, this gives you Ruby's attribute-like API:

```ruby
input.source_satoshis          # getter
input.source_satoshis = 5000   # setter
```

Note: not every attribute is writable. The SDK exposes setters (`attr_accessor`) only where mutation after construction is part of the intended workflow — e.g. wiring source data onto inputs before signing. Immutable attributes are read-only (`attr_reader`).

### 5. Conversions use `to_*`

Methods that convert an object to a different format or type use the `to_` prefix. This is the same pattern as Ruby's built-ins (`to_s`, `to_i`, `to_a`).

```ruby
# TS:   tx.toHex()       → Ruby: tx.to_hex
# TS:   tx.toBinary()    → Ruby: tx.to_binary
# TS:   key.toWIF()      → Ruby: key.to_wif
# TS:   script.toASM()   → Ruby: script.to_asm
```

### 6. Constructors use `from_*`

Class methods that build an instance from external data use the `from_` prefix. This mirrors `to_*` in the opposite direction.

```ruby
# TS:   Transaction.fromBinary(data)    → Ruby: Transaction.from_binary(data)
# TS:   PublicKey.fromHex(hex)          → Ruby: PublicKey.from_hex(hex)
# TS:   PrivateKey.fromWIF(wif)         → Ruby: PrivateKey.from_wif(wif)
```

For generating new instances (not from data), use `new` or `generate`:

```ruby
BSV::Primitives::PrivateKey.generate      # random new key
BSV::Transaction::Tx.new                  # empty transaction
```

### 7. Options objects become keyword arguments

TypeScript APIs commonly pass a single options object. Ruby uses keyword arguments directly. Every option becomes a keyword, with the same names (in snake_case).

```ruby
# illustrative — the TS block is not valid Ruby; the Ruby block uses `[...]`
# ellipsis placeholders. Compare the shape of the two calls, not the literal syntax.

# TS:
wallet.createAction({
  description: 'Payment',
  inputs: [...],
  outputs: [...],
  lockTime: 0
})

# Ruby:
wallet.create_action(
  description: 'Payment',
  inputs: [...],
  outputs: [...],
  lock_time: 0
)
```

This is a structural difference, not just naming — there is no wrapping hash. The arguments are passed directly as keyword parameters.

When a method takes a hash that represents structured data (e.g. an input spec, an output spec), that hash itself still uses symbol keys with snake_case:

```ruby
wallet.create_action(
  inputs: [
    { outpoint: "abc.0", unlocking_script: template, input_description: "..." }
  ],
  outputs: [
    { locking_script: "76a914...88ac", satoshis: 1000, output_description: "..." }
  ]
)
```

### 8. Derived properties vs format conversions

This is the subtlest distinction. TypeScript uses `toX()` for both *derived properties* (things the object has or computes about itself) and *format conversions* (encoding the object in a different representation). Ruby splits them:

- **Derived property** — bare noun: `key.public_key`, `key.address`, `tx.wtxid`
- **Format conversion** — `to_` prefix: `key.to_wif`, `tx.to_hex`, `script.to_asm`

The rule of thumb: if the return value is another *object* in the domain model, it's a property. If the return value is a *serialised representation* of the same object, it's a conversion.

```ruby
private_key.public_key    # a PublicKey object — property
private_key.to_wif        # a WIF string representation — conversion
private_key.to_hex        # a hex string representation — conversion

public_key.address        # an address string — property (it's a derived domain concept)
public_key.hash160        # the hash160 bytes — property
public_key.to_hex         # hex-encoded representation — conversion
```

This distinction makes reading code clearer: `tx.inputs.first.source_transaction.outputs.first.locking_script` is a chain of properties, whereas `tx.to_hex` is clearly a one-way transformation to a string.

### 9. BRC-100 wire protocol methods are verbatim

The one set of methods that doesn't follow the above rules: **BRC-100 wallet interface methods**. These implement the BSV wire protocol, and their names are part of the protocol specification. Renaming them would break interoperability with the TS, Go, and other SDKs.

Keep their protocol names exactly:

```ruby
wallet.get_public_key(protocol_id:, key_id:, counterparty:)   # not public_key
wallet.get_height                                              # not height
wallet.is_authenticated                                        # not authenticated?
wallet.list_outputs(basket:, tags:)                            # not outputs
wallet.create_action(description:, inputs:, outputs:)
wallet.internalize_action(tx:, outputs:, description:)
```

This is enforced in the project's RuboCop configuration. Methods in `lib/bsv/wallet/interface/brc100.rb` and `lib/bsv/wallet/client/brc100/` are exempt from the `Naming/AccessorMethodName` and `Naming/PredicatePrefix` cops for this reason.

If you see `get_`, `set_`, or `is_` on a method *outside* the wallet interface, that's a bug — report it.

## Other Ruby idioms worth knowing

These aren't naming conventions strictly, but they affect how the SDK feels compared to TS/Go.

### Immutability by default? No.

Unlike some functional-style APIs, Ruby objects are generally mutable. `tx.add_input(input)` mutates `tx`. There's no "return a new transaction" pattern — you modify in place and chain methods if you want fluency.

### No method overloading

Ruby doesn't support method overloading by type. Where TS might have `fromHex(string)` and `fromBuffer(buffer)`, Ruby has separate methods: `from_hex` and `from_binary`. This is why you'll see multiple `from_*` constructors on many classes.

### `nil` vs `undefined`

Ruby has only `nil`. There's no distinction between "undefined" and "null". Optional parameters default to `nil` unless specified otherwise.

### Constants

Constants are `SCREAMING_SNAKE_CASE` and stored in modules or classes. They're accessed with `::`:

```ruby
BSV::Transaction::Beef::BEEF_V1
BSV::Primitives::Curve::N
```

This matches Ruby convention and roughly matches TS/Go constant naming, just with `::` instead of `.`.

## Quick reference card

| Pattern | TS / Go | Ruby |
|---|---|---|
| Case | `camelCase` | `snake_case` |
| Getter | `tx.getVersion()` | `tx.version` |
| Setter | `input.setSourceSatoshis(5000)` | `input.source_satoshis = 5000` |
| Predicate | `script.isP2PKH()` | `script.p2pkh?` |
| Conversion | `tx.toHex()` | `tx.to_hex` |
| Constructor | `Transaction.fromBinary(data)` | `Transaction.from_binary(data)` |
| Options object | `createAction({ description, inputs })` | `create_action(description:, inputs:)` |
| Derived property | `key.toPublicKey()` | `key.public_key` |
| BRC-100 method | `wallet.getPublicKey()` | `wallet.get_public_key` (verbatim) |

If you remember these nine rules, you can predict nearly every method name in the SDK without looking it up.
