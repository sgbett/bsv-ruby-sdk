# Store

The Store interface defines how the wallet persists actions (transactions), outputs (UTXOs), certificates, proofs, and settings.

## Interface

`BSV::Wallet::Interface::Store` — include this module in your adapter class and implement all methods.

The interface covers five data domains:

| Domain | Methods |
|--------|---------|
| Actions | `store_action`, `find_actions`, `count_actions`, `update_action_status`, `delete_action` |
| Outputs | `store_output`, `find_outputs`, `count_outputs`, `delete_output`, `update_output_state`, `update_output_basket`, `lock_utxos`, `find_spendable_outputs`, `release_stale_pending!` |
| Certificates | `store_certificate`, `find_certificates`, `count_certificates`, `delete_certificate` |
| Proofs & Transactions | `store_proof`, `find_proof`, `store_transaction`, `find_transaction` |
| Settings | `store_setting`, `find_setting` |

## Shipped implementations

### `Store::Memory`

**Testing only.** In-memory store backed by Ruby hashes. All data is lost when the process exits. If a wallet holds real funds and the process restarts, those funds are irrecoverable.

`Store::Memory` emits a loud stderr warning at instantiation and will refuse to operate silently as a production store. Suppress the warning with `BSV_MEMORY_STORE_OK=1` — but only in test suites.

```ruby
# In specs
wallet = BSV::Wallet::Client.new(key, storage: BSV::Wallet::Store::Memory.new)
```

Do not use `Store::Memory` with real keys or real funds.

### `Store::File`

JSON file persistence. Extends `Store::Memory` — inherits all query logic, adds atomic file writes (temp + rename) for durability. This is the default storage when no `storage:` argument is provided.

```ruby
wallet = BSV::Wallet::Client.new(key)  # uses Store::File by default
```

Writes to `~/.bsv-wallet/` (or `BSV_WALLET_DIR` env var). Directory mode `0700`, file mode `0600`.

**Important:** FileStore is only as durable as its underlying volume. If the wallet runs inside a Docker container with an ephemeral filesystem, data (and funds) will be lost when the container is removed. Mount a persistent volume or use `PostgresStore` for containerised deployments.

### `bsv-wallet-postgres` gem

For production deployments, the `bsv-wallet-postgres` gem provides `PostgresStore` — a Sequel-backed adapter with proper migrations, JSONB columns, and connection pooling.

```ruby
require 'bsv-wallet-postgres'

db = Sequel.connect(ENV['DATABASE_URL'])
store = BSV::WalletPostgres::PostgresStore.new(db)
wallet = BSV::Wallet::Client.new(key, storage: store, broadcaster: arc)
```

## Writing a custom adapter

```ruby
class RedisStore
  include BSV::Wallet::Interface::Store

  def initialize(redis)
    @redis = redis
  end

  def store_action(action_data)
    @redis.hset("actions:#{action_data[:txid]}", action_data.to_json)
    action_data
  end

  # ... implement all methods from Interface::Store
end
```

### Output state lifecycle

Outputs transition through these states:

```
:spendable → :pending → :spent
                ↓
            :spendable  (rollback or stale recovery)
```

- `lock_utxos` atomically moves outputs from `:spendable` to `:pending` — this prevents two threads selecting the same UTXO.
- `release_stale_pending!` recovers outputs stuck in `:pending` longer than the timeout.
- Outputs locked with `no_send: true` (UTXO pool pre-allocations) are exempt from stale recovery.
