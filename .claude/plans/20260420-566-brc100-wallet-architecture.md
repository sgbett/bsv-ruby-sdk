# Plan: BRC-100-Driven Wallet Architecture (#566)

## Context

The current wallet grew bottom-up. `WalletClient` (1,825 lines) inherits `ProtoWallet`, which exists only to support an inheritance model ("a wallet that can do crypto but not transactions") that has no basis in BRC-100. The `Interface` module is a flat 28-method stub with no structural relationship to BRC-100's six functional areas. Implementation concerns (storage, broadcast, pools) sit in the same namespace as the contract surface.

**Goal:** Restructure so BRC-100's Interface Structure drives the architecture. ProtoWallet is deleted. A new `Client` class uses composition only. The six BRC-100 functional areas become explicit modules.

## Design Decisions

**Rename `wallet_interface` → `wallet` in file paths.** The module is `BSV::Wallet`, so files belong under `lib/bsv/wallet/`, not `lib/bsv/wallet_interface/`. The gem entry point (`lib/bsv-wallet.rb`) and autoload hub (`lib/bsv/wallet.rb`) are updated accordingly.

**Abstract contract modules, not implementation mixins.** The 6 BRC-100 sub-modules contain abstract stubs (raise `UnsupportedActionError`), not implementation. Reasons:
- Wire substrates (`HTTPWalletJSON`, `WalletWireTransceiver`) also include the contract — if it carried implementation, they'd inherit unwanted dependencies
- Matches the existing `Interface`, `StorageAdapter`, `BroadcastQueue` pattern
- Composition over inheritance: Client implements, contract declares

**No backward compatibility shims.** We are pre-1.0. `WalletClient` and `ProtoWallet` are deleted outright, not shimmed. `Client` is the only wallet class. Downstream gems update their references in the same release cycle.

**ProtoWallet is deleted.** Its crypto logic (9 methods + 4 private helpers) is absorbed into `Client` using `@key_deriver` directly. The 9 `super`-delegating overrides in WalletClient (lines 654-706) collapse — Client handles substrate delegation and local crypto in a single method.

**Collaborator interface renames deferred.** Renaming `StorageAdapter` → `BSV::Wallet::Store` etc. can happen independently. This plan focuses on the BRC-100 contract structure and the path cleanup.

---

## Phase 1: Path Rename + BRC-100 Contract Modules

**One PR. Rename all paths, create BRC-100 modules, bridge Interface.**

### Step 1: Rename `wallet_interface` → `wallet`

`git mv` every file under `lib/bsv/wallet_interface/` to `lib/bsv/wallet/`. Update the autoload hub path from `lib/bsv/wallet_interface.rb` to `lib/bsv/wallet.rb`. Update all `require` and `autoload` path strings. Update `lib/bsv-wallet.rb` entry point if needed.

### Step 2: Create BRC-100 sub-modules

```
lib/bsv/wallet/brc100.rb                    — autoload hub
lib/bsv/wallet/brc100/transaction.rb         — codes 1-7 (7 abstract stubs)
lib/bsv/wallet/brc100/key_management.rb      — codes 8-10 (3 abstract stubs)
lib/bsv/wallet/brc100/crypto.rb              — codes 11-16 (6 abstract stubs)
lib/bsv/wallet/brc100/identity.rb            — codes 17-22 (6 abstract stubs)
lib/bsv/wallet/brc100/network.rb             — codes 25-28 (4 abstract stubs)
lib/bsv/wallet/brc100/authentication.rb      — codes 23-24 (2 abstract stubs)
lib/bsv/wallet/brc100/interface.rb           — includes all 6 sub-modules
```

### Step 3: Bridge Interface

- `lib/bsv/wallet/interface.rb` — replace 28 inline method definitions with `include BRC100::Interface`
- `lib/bsv/wallet.rb` — add `autoload :BRC100, 'bsv/wallet/brc100'`

### Specs

- Update all `require` paths in spec files for the rename
- New specs verifying each sub-module and composed `BRC100::Interface`

### Acceptance

- All existing wallet specs pass (with updated paths)
- `BSV::Wallet::Interface` and `BSV::Wallet::BRC100::Interface` are equivalent
- Gem builds

---

## Phase 2: Create Client, Delete ProtoWallet and WalletClient

**One PR. The core structural change.**

### Files to create

```
lib/bsv/wallet/client.rb
spec/bsv/wallet/client_spec.rb
```

`Client` class structure:
```ruby
class BSV::Wallet::Client
  include BRC100::Interface

  attr_reader :key_deriver, :storage, :network, :proof_store,
              :broadcaster, :broadcast_queue, :substrate

  def initialize(key, storage: FileStore.new, network: 'mainnet', ...)
    @key_deriver = key.is_a?(KeyDeriver) ? key : KeyDeriver.new(key)
    @substrate = substrate
    @storage = storage
    # ... (same wiring as current WalletClient#initialize, minus super(key))
  end

  # All 28 BRC-100 method implementations (from WalletClient)
  # 9 crypto methods (from ProtoWallet, with substrate delegation inlined)
  # 4 private crypto helpers (derive_sym_key, bytes_to_string, etc.)
  # All private transaction/auto-fund/certificate helpers
  # Non-BRC-100 methods: balance, spendable_balance, set_wallet_change_params, etc.
end
```

The 9 crypto method overrides in WalletClient (lines 654-706) that did `return @substrate.X if @substrate; super` collapse into Client's own methods which do `return @substrate.X if @substrate; <ProtoWallet's implementation>`.

### Files to delete

- `lib/bsv/wallet/proto_wallet.rb`
- `lib/bsv/wallet/wallet_client.rb`

### Files to modify

- `lib/bsv/wallet/certificate_signature.rb` — change `verifier: ProtoWallet.new('anyone')` to `verifier: Client.new('anyone', storage: MemoryStore.new)`
- `lib/bsv/wallet.rb` — remove `ProtoWallet` and `WalletClient` autoloads, add `Client`

### Spec changes

- **Delete** `spec/bsv/wallet/proto_wallet_spec.rb` — crypto method coverage moves to `client_spec.rb`
- **Delete** `spec/bsv/wallet/wallet_client_spec.rb` — all coverage moves to `client_spec.rb`
- `spec/bsv/wallet/certificate_spec.rb` — change `ProtoWallet.new(key)` to `Client.new(key, storage: MemoryStore.new)`
- All other specs: replace `WalletClient.new(...)` with `Client.new(...)`

### Critical detail: `super` chain elimination

Current: `WalletClient#encrypt` → `super` → `ProtoWallet#encrypt` (uses `@key_deriver`)
After: `Client#encrypt` uses `@key_deriver` directly — no inheritance, no `super`

### Acceptance

- All specs pass (rewritten for Client)
- `BSV::Wallet::Client.new(key)` returns a working wallet
- `ProtoWallet` and `WalletClient` are gone — no files, no autoloads, no references
- No inheritance — Client includes `BRC100::Interface` directly

---

## Phase 3: Substrates + Documentation

**One PR. Cleanup.**

### Files to modify

- `lib/bsv/wallet/substrates/http_wallet_json.rb` — change `include BSV::Wallet::Interface` to `include BSV::Wallet::BRC100::Interface`
- `lib/bsv/wallet/substrates/wallet_wire_transceiver.rb` — same change
- `docs/wallet/brc-100.md` — update "Implications for bsv-wallet" section to reflect new structure
- `docs/wallet/brc-100-sdk-implementation.md` — update to reflect completed work

### Acceptance

- All specs pass
- Substrate specs pass
- Gem builds

---

## Out of Scope (Future Work)

- **Collaborator interface renames** (`StorageAdapter` → `BSV::Wallet::Store`, etc.) — separate HLR
- **Client internal decomposition** — extracting the 70+ private methods into concern modules. Client inherits the current complexity; future work can decompose by BRC-100 functional area
- **BRCs for collaborator interfaces** — research whether BRCs exist that define storage/broadcaster/proof contracts (noted in user's implementation doc)

---

## Critical Files

| File | Phase | Role |
|------|-------|------|
| `lib/bsv/wallet_interface/` → `lib/bsv/wallet/` | 1 | Full directory rename |
| `lib/bsv/wallet/interface.rb` | 1 | Bridge to BRC100::Interface |
| `lib/bsv/wallet/brc100/` | 1 | New: 6 abstract contract modules |
| `lib/bsv/wallet/client.rb` | 2 | New: composition-based wallet |
| `lib/bsv/wallet/wallet_client.rb` | 2 | Deleted |
| `lib/bsv/wallet/proto_wallet.rb` | 2 | Deleted |
| `lib/bsv/wallet/certificate_signature.rb` | 2 | ProtoWallet ref → Client |
| `lib/bsv/wallet.rb` | 1,2 | Autoload hub (renamed from wallet_interface.rb) |

## Verification

After each phase:
1. `cd gem/bsv-wallet && bundle exec rspec` — all specs pass
2. `cd gem/bsv-wallet-postgres && bundle exec rspec` — downstream specs pass
3. `bundle exec rubocop` — clean
4. `cd gem/bsv-wallet && gem build bsv-wallet.gemspec` — gem builds
