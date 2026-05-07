# BeefTx Polymorphic Subclasses (#692)

## Context

`BeefTx` uses a `@format` integer flag with `case` statements to handle three distinct behaviours: TXID-only entries (just a hash), raw transaction entries, and proven transaction entries (raw tx + BUMP). This is a type system implemented with integers. Two silent-failure bugs caused by this design were found and fixed in #691.

## Class Hierarchy

All three classes remain inner classes of `BSV::Transaction::Beef`.

```
BeefTx (abstract base)
  ├── RawTxEntry        (FORMAT_RAW_TX = 0)
  ├── ProvenTxEntry     (FORMAT_RAW_TX_AND_BUMP = 1)
  └── TxidOnlyEntry     (FORMAT_TXID_ONLY = 2)
```

### Base class: `BeefTx`

Abstract base providing:
- `#wtxid` — abstract, subclasses implement
- `#dtxid` — concrete, delegates to `#wtxid` (shared)
- `#transaction` — returns `nil` by default (TxidOnlyEntry inherits this)
- `#bump_index` — returns `nil` by default (only ProvenTxEntry overrides)
- `#known_wtxid` — returns `nil` by default (only TxidOnlyEntry overrides)
- `#format_flag` — abstract, each subclass returns its wire format integer for serialisation

`FORMAT_*` constants stay on `Beef` — they are wire-protocol values, not type metadata.

### `RawTxEntry` (FORMAT_RAW_TX)

Has `@transaction`. Returns `transaction.wtxid` for `#wtxid`. `format_flag` returns `0`.

### `ProvenTxEntry` (FORMAT_RAW_TX_AND_BUMP)

Has `@transaction` and `@bump_index`. Raises if `bump_index` is nil. `format_flag` returns `1`.

### `TxidOnlyEntry` (FORMAT_TXID_ONLY)

Has `@known_wtxid` (validated). Returns `@known_wtxid` for `#wtxid`. No `.transaction` method override — inherits `nil` from base. `format_flag` returns `2`.

## Design Decisions

**`#transaction` returns nil, doesn't raise, on TxidOnlyEntry.** Many call sites guard with `bt.transaction&.method` or `next unless bt.transaction`. Raising would break those patterns without benefit. The nil return is the correct "does not have a transaction" signal in Ruby.

**No `BeefTx.new` factory.** Pre-1.0; breaking changes are acceptable. The `format` parameter disappears from the public API entirely.

**`#format` accessor removed.** Replaced by `#format_flag` for serialisation only. Type checks use `is_a?` or `case bt when SubclassX`.

## Tasks

### Task 1: Create subclass hierarchy in `beef.rb`

Define the four classes (base + three subclasses) as inner classes of `Beef`. Keep `FORMAT_*` constants on `Beef` unchanged.

### Task 2: Update all construction sites inside `beef.rb`

Replace every `BeefTx.new(format: ...)` with the appropriate subclass constructor:
- `read_v1_transactions` — `RawTxEntry` / `ProvenTxEntry`
- `read_v2_transactions` — all three subclasses
- `merge_bump` retroactive linking — `ProvenTxEntry`
- `merge_transaction` — `RawTxEntry` / `ProvenTxEntry`
- `merge_raw_tx` — `RawTxEntry` / `ProvenTxEntry`
- `make_txid_only` — `TxidOnlyEntry`
- `merge` — all three subclasses
- `upgrade_beef_tx` — `RawTxEntry` / `ProvenTxEntry`

### Task 3: Replace all `case @format` / `.format ==` with polymorphic dispatch

7 `case`/`when FORMAT_*` blocks and 15+ `.format ==` checks transform to either:
- `bt.is_a?(SubclassX)` for guards
- `case bt when SubclassX` for dispatch (Ruby 2.7 compatible — uses `===`)

Key sites: `to_binary` V1 guard, `find_bump`, `merge_bump` filter, `merge` dispatch, `valid?`, `build_known_wtxids`, `write_v1_tx`, `write_v2_tx`, `upgrade_beef_tx`.

### Task 4: Update `transaction.rb`

`to_beef` — replace `Beef::BeefTx.new(format: ...)` with `Beef::ProvenTxEntry.new(...)` / `Beef::RawTxEntry.new(...)`.

`from_beef` — no change needed. `find(&:transaction)` still works because `TxidOnlyEntry#transaction` returns `nil` (falsy).

### Task 5: Update specs

- `beef_spec.rb` — ~30 constructor calls, ~18 format assertions (`expect(x.format).to eq(...)` → `expect(x).to be_a(...)`), ~10 format filters
- `conformance/beef_spec.rb` — ~3 format filters
- `transaction_spec.rb` — 1 format assertion
- `identity/client_spec.rb` — 1 `instance_double`
- `registry/client_spec.rb` — 2 `instance_double`s

### Task 6: Verify

- `bundle exec rake` — all specs pass
- `bundle exec rubocop` — no offences

## Risks

| Risk | Mitigation |
|------|-----------|
| `instance_double` specs break | Update double to reference concrete subclass |
| `find(&:transaction)` in `from_beef` breaks | Works — `TxidOnlyEntry#transaction` returns nil (falsy) |
| Serialisation round-trip breaks | Conformance specs with Go SDK vectors catch this |
| RuboCop `Lint/MissingSuper` | Base `initialize` is a no-op; subclasses don't need `super` |
| `valid?` line 553 guards with `bt.transaction` | `TxidOnlyEntry#transaction` returns nil — correctly excluded |

## Files Modified

| File | Change |
|------|--------|
| `gem/bsv-sdk/lib/bsv/transaction/beef.rb` | Subclass hierarchy, all construction/dispatch sites |
| `gem/bsv-sdk/lib/bsv/transaction/transaction.rb` | `to_beef` constructor calls |
| `gem/bsv-sdk/spec/bsv/transaction/beef_spec.rb` | Constructors, format assertions, format filters |
| `gem/bsv-sdk/spec/conformance/beef_spec.rb` | Format filters |
| `gem/bsv-sdk/spec/bsv/transaction/transaction_spec.rb` | 1 format assertion |
| `gem/bsv-sdk/spec/bsv/identity/client_spec.rb` | 1 instance_double |
| `gem/bsv-sdk/spec/bsv/registry/client_spec.rb` | 2 instance_doubles |
