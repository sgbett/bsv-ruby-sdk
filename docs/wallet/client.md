# Client (BRC-100)

`BSV::Wallet::Client` is the wallet. Give it a key, get a fully functional BRC-100 implementation.

```ruby
wallet = BSV::Wallet::Client.new(
  BSV::Primitives::PrivateKey.from_wif(ENV['SERVER_WIF']),
  broadcaster: BSV::Network::ARC.default
)
```

## What BRC-100 defines

[BRC-100](https://bsv.brc.dev/wallet/0100) is the standard wallet-to-application interface for BSV. It specifies 28 methods across six functional areas:

| Area | Methods | What it covers |
|------|---------|----------------|
| Transaction | `create_action`, `sign_action`, `abort_action`, `list_actions`, `internalize_action`, `list_outputs`, `relinquish_output` | Building, signing, broadcasting, and querying transactions |
| Key Management | `get_public_key`, `reveal_counterparty_key_linkage`, `reveal_specific_key_linkage` | BRC-42 key derivation and BRC-69 auditability |
| Cryptography | `encrypt`, `decrypt`, `create_hmac`, `verify_hmac`, `create_signature`, `verify_signature` | BRC-2 encryption and BRC-3 digital signatures |
| Identity | `acquire_certificate`, `list_certificates`, `prove_certificate`, `relinquish_certificate`, `discover_by_identity_key`, `discover_by_attributes` | BRC-52 identity certificates |
| Network | `get_height`, `get_header_for_height`, `get_network`, `get_version` | Blockchain state queries |
| Authentication | `is_authenticated`, `wait_for_authentication` | Wallet readiness |

BRC-100 specifies *what* a wallet must do. Everything else — how it stores data, how it broadcasts, how it manages UTXOs — is left to the implementation.

## Constructor

```ruby
BSV::Wallet::Client.new(
  key,                          # PrivateKey, WIF string, or KeyDeriver
  storage: Store::File.new,     # where to persist (see Store docs)
  network: 'mainnet',           # 'mainnet' or 'testnet'
  broadcaster: nil,             # responds to #broadcast(tx) — e.g. ARC.default
  broadcast_queue: nil,         # defaults to BroadcastQueue::Inline
  proof_store: nil,             # defaults to LocalProofStore backed by storage
  fee_estimator: nil,           # defaults to FeeEstimator (100 sat/kB)
  coin_selector: nil,           # defaults to CoinSelector (:standard strategy)
  change_generator: nil,        # defaults to ChangeGenerator
  substrate: nil                # remote wallet — delegates all 28 methods
)
```

Every collaborator has a sensible default. For a lightweight local wallet, `Client.new(key)` is sufficient. For production with broadcasting:

```ruby
wallet = BSV::Wallet::Client.new(
  key,
  broadcaster: BSV::Network::ARC.default
)
```

## Interface contract

`Client` includes `Interface::BRC100` — the abstract contract module. Any object that includes this module and implements the 28 methods is a valid BRC-100 wallet. The remote substrates (`Substrates::HTTPWalletJSON`, `Substrates::WalletWireTransceiver`) also include this interface.

```ruby
wallet.is_a?(BSV::Wallet::Interface::BRC100)  # => true
```

## Auto-funding

When you call `create_action` with outputs but no inputs, and pass `options: { auto_fund: true }`, the wallet automatically selects UTXOs, estimates fees, generates change, and returns a complete signed transaction.

```ruby
result = wallet.create_action(
  description: 'Pay invoice',
  outputs: [{ locking_script: script, satoshis: 1000,
              output_description: 'Payment' }],
  labels: ['payments'],
  options: { auto_fund: true }
)

result[:txid]  # => "a1b2c3..."
result[:tx]    # => BEEF bytes
```

## Substrate delegation

If `substrate:` is provided, all 28 methods delegate to it instead of using local storage and key derivation. This turns Client into a thin proxy for a remote wallet.

```ruby
remote = BSV::Wallet::Substrates::HTTPWalletJSON.new('https://wallet.example.com')
wallet = BSV::Wallet::Client.new(key, substrate: remote)
```

## Architecture

Client is a thin composition root (~180 lines). The 28 BRC-100 methods are implemented in five concern modules under `Client::`:

- `Client::Transaction` — codes 1-7
- `Client::Crypto` — codes 8-16
- `Client::Identity` — codes 17-22
- `Client::Network` — codes 25-28
- `Client::Authentication` — codes 23-24

Each concern module matches a functional area from the BRC-100 specification.
