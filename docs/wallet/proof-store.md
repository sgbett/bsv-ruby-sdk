# Proof Store

The proof store interface defines how the wallet persists and resolves SPV merkle proofs for transactions.

## Interface

`BSV::Wallet::Interface::ProofStore` — include this module in your implementation.

| Method | Purpose |
|--------|---------|
| `store_proof(txid, merkle_path)` | Persist a merkle proof for a transaction |
| `resolve_proof(txid)` | Look up a previously stored proof, or return `nil` |

## Why it exists

BRC-100 wallets use BEEF (BRC-62) for transaction data, which requires merkle proofs for input validation. When a wallet creates a transaction, it needs to provide proofs for the inputs it's spending. The proof store is where those proofs live between when they're received and when they're needed.

The proof store is separate from the main Store because proof resolution may come from different sources — local storage, a Chaintracks service, or a combination.

## Shipped implementation

### `LocalProofStore`

Delegates to the wallet's main `Store` adapter. Proofs are stored and retrieved via `store_proof` / `find_proof` on the storage adapter.

```ruby
# Default — created automatically from the wallet's storage
wallet = BSV::Wallet::Client.new(key)
# wallet.proof_store is a LocalProofStore backed by the File store

# Explicit
proof_store = BSV::Wallet::LocalProofStore.new(store)
wallet = BSV::Wallet::Client.new(key, proof_store: proof_store)
```

## Writing a custom implementation

```ruby
class ChaintracksProofStore
  include BSV::Wallet::Interface::ProofStore

  def initialize(api_url:)
    @api_url = api_url
  end

  def store_proof(txid, merkle_path)
    # Local cache or no-op — Chaintracks is the authority
  end

  def resolve_proof(txid)
    # Fetch from Chaintracks API
    response = fetch("#{@api_url}/proof/#{txid}")
    BSV::Transaction::MerklePath.from_hex(response) if response
  end
end
```
