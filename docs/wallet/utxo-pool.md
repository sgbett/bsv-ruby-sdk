# UTXO Pool

The UTXO pool interface defines a pre-funded output pool for high-frequency transaction scenarios. Instead of selecting UTXOs from the general wallet balance on each transaction, a pool pre-allocates outputs that can be acquired and spent with minimal contention.

## Interface

`BSV::Wallet::Interface::UTXOPool` — include this module in your pool implementation.

| Method | Purpose |
|--------|---------|
| `acquire` | Lock and return an available output from the pool |
| `release(outpoint)` | Release a previously acquired output back to available |
| `status` | Return pool health: available count, locked count, totals |
| `shutdown` | Gracefully release all resources and stop background threads |

### State lifecycle

```
:available → :locked → :spent
                ↓
            :available  (released or expired)
```

`acquire` is expected to be safe for concurrent callers. If no output is available after `MAX_RETRIES` (3) attempts, it raises `PoolDepletedError`.

## When to use a pool

Pools are useful when:
- Your application creates many transactions per second
- UTXO selection contention is causing lock retries
- You want predictable, pre-allocated outputs for specific use cases (e.g. token issuance)

For most applications, the wallet's built-in auto-funding (which selects from the `default` basket on each transaction) is sufficient.

## Creating a pool

```ruby
wallet = BSV::Wallet::Client.new(key, broadcaster: BSV::Network::ARC.default)

pool = wallet.utxo_pool(
  name: 'tokens',           # basket will be "pool:tokens"
  target_count: 20,         # desired number of pre-funded outputs
  target_satoshis: 10_000,  # satoshis per output
  low_water_mark: 0.5       # replenish when available drops to 50%
)

# Acquire an output for use
output = pool.acquire
# => { txid: "abc...", vout: 0, satoshis: 10000, ... }

# Check pool health
pool.status
# => { pool_name: "tokens", available: 15, locked: 1, total: 20, ... }

# Release if not used
pool.release(output)

# Shut down when done
pool.shutdown
```

## Shipped implementation

### `LocalPool`

In-process pool with automatic background replenishment. When the available count drops to the low-water mark, a `ReplenishmentWorker` thread creates new funded outputs via `wallet.create_action`.

- Outputs are stored in a structured basket (`"pool:<name>"`)
- Outputs are locked with `no_send: true` (exempt from stale recovery sweeps)
- Thread-safe acquisition via Mutex
- Replenishment runs immediately on start, then on signal or interval (default 60s)

The pool requires a broadcaster — it needs to create real on-chain transactions to fund new outputs.

## Writing a custom pool

```ruby
class RedisPool
  include BSV::Wallet::Interface::UTXOPool

  def initialize(redis:, pool_name:)
    @redis = redis
    @pool_name = pool_name
  end

  def acquire
    MAX_RETRIES.times do
      outpoint = @redis.spop("pool:#{@pool_name}:available")
      if outpoint
        @redis.sadd("pool:#{@pool_name}:locked", outpoint)
        return JSON.parse(outpoint, symbolize_names: true)
      end
    end
    raise BSV::Wallet::PoolDepletedError, @pool_name
  end

  def release(outpoint)
    key = outpoint.to_json
    @redis.srem("pool:#{@pool_name}:locked", key)
    @redis.sadd("pool:#{@pool_name}:available", key)
  end

  def status
    { pool_name: @pool_name,
      available: @redis.scard("pool:#{@pool_name}:available"),
      locked: @redis.scard("pool:#{@pool_name}:locked"),
      total: available + locked }
  end

  def shutdown
    # Release all locked back to available, or flush
  end
end
```
