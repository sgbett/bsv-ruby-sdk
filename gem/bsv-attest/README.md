# bsv-attest

Document attestation on the BSV Blockchain. Hash data, publish hashes
via OP_RETURN using a BRC-100 wallet, and verify attestations on chain.

Part of the [BSV Ruby SDK](https://github.com/sgbett/bsv-ruby-sdk)
monorepo.

## Installation

```ruby
# Gemfile
gem 'bsv-attest'
```

Requires `bsv-sdk` and `bsv-wallet`.

## Quick start

```ruby
require 'bsv-attest'

BSV::Attest.configure do |c|
  c.wallet = my_wallet  # BSV::Wallet::WalletClient with broadcaster
end

# Publish a document hash to the blockchain
result = BSV::Attest.publish(data: File.read('document.pdf'))
puts result.txid
```

## How it works

1. SHA-256 hashes the input data
2. Builds an OP_RETURN output containing the hash
3. Broadcasts via `wallet.create_action` (the wallet handles UTXO
   selection, signing, and ARC broadcast)
4. Returns a `Response` with the transaction ID

## Documentation

- [Full documentation](https://sgbett.github.io/bsv-ruby-sdk/)
- [Getting started guide](https://sgbett.github.io/bsv-ruby-sdk/guides/getting-started/)
- [Changelog](CHANGELOG.md)

## Licence

[Open BSV Licence Version 5](LICENSE)
