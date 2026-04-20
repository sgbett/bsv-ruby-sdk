# Broadcast Queue

The broadcast queue interface defines how transactions are dispatched to the network and how UTXO state is promoted after successful broadcast.

## Interface

`BSV::Wallet::Interface::BroadcastQueue` — include this module in your adapter class.

| Method | Purpose |
|--------|---------|
| `enqueue(payload)` | Dispatch a transaction for broadcast and state promotion |
| `async?` | Whether execution is deferred to a background worker (default: `false`) |
| `broadcast_enabled?` | Whether the adapter can actually broadcast on-chain (default: `false`) |
| `status(txid)` | Query the broadcast status of a previously enqueued transaction |

### Payload contract

The `enqueue` method receives a Hash:

```ruby
{
  tx:                       BSV::Transaction,  # signed transaction object
  txid:                     String,            # hex txid
  beef_binary:              String,            # raw BEEF bytes
  input_outpoints:          Array<String>,     # locked input outpoints (nil on finalise path)
  change_outpoints:         Array<String>,     # change outpoints (nil on finalise path)
  fund_ref:                 String,            # fund reference for rollback (nil on finalise path)
  accept_delayed_broadcast: Boolean            # from caller options
}
```

When `input_outpoints` is `nil`, the caller is on the finalise path (signing a previously created transaction) and the adapter must skip UTXO state transitions.

## Shipped implementation

### `BroadcastQueue::Inline`

Synchronous execution — broadcasts immediately and returns the result. This is the default when no `broadcast_queue:` argument is provided.

```ruby
# With a broadcaster: broadcasts on-chain, promotes UTXO state
wallet = BSV::Wallet::Client.new(key, broadcaster: BSV::Network::ARC.default)

# Without a broadcaster: promotes state only (delayed broadcast path)
wallet = BSV::Wallet::Client.new(key)
```

On broadcast failure, `Inline` rolls back: releases locked inputs, deletes phantom change outputs, and marks the action as failed.

### `bsv-wallet-postgres` gem

The `bsv-wallet-postgres` gem provides `SolidQueueAdapter` — an async adapter that persists broadcast jobs to a database queue. Jobs are processed by a background worker thread, with automatic retry on transient failures.

## Writing a custom adapter

```ruby
class SidekiqBroadcastQueue
  include BSV::Wallet::Interface::BroadcastQueue

  def initialize(broadcaster:)
    @broadcaster = broadcaster
  end

  def async?
    true
  end

  def broadcast_enabled?
    true
  end

  def enqueue(payload)
    BroadcastWorker.perform_async(payload[:beef_binary], payload[:txid])
    { txid: payload[:txid] }
  end

  def status(txid)
    BroadcastWorker.status_for(txid)
  end
end
```

### Shared helper

`BSV::Wallet::BroadcastQueue.status_for_error(error)` maps broadcast exceptions to status strings (`'doubleSpend'`, `'invalidTx'`, `'serviceError'`). Use this in custom adapters to produce consistent status values.
