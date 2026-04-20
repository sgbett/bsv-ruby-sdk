# BSV Ruby SDK

Ruby SDK for the BSV Blockchain. Part of the official BSV SDK family alongside
[Go](https://github.com/bitcoin-sv/go-sdk),
[TypeScript](https://github.com/bitcoin-sv/ts-sdk), and
[Python](https://github.com/bitcoin-sv/py-sdk).

## Installation

Add to your Gemfile:

```ruby
gem 'bsv-sdk'
```

Or install directly:

```bash
gem install bsv-sdk
```

## Modules

The SDK is organised into three top-level modules:

- **[Primitives](sdk/primitives.md)** — keys, curves, hashing, encryption, HD keys, mnemonics
- **[Script](sdk/script.md)** — script parsing, opcodes, templates, interpreter
- **[Transaction](sdk/transaction.md)** — building, signing, BEEF serialisation, merkle proofs

## Companion gems

- **[bsv-wallet](gems/wallet.md)** — BRC-100 wallet interface with `BSV::Wallet::Client`, storage adapters, and broadcast queue
- **[bsv-wallet-postgres](gems/wallet-postgres.md)** — PostgreSQL storage adapter and async broadcast queue for production deployments
- **[bsv-attest](https://rubygems.org/gems/bsv-attest)** — document attestation via OP_RETURN on the BSV blockchain

## Quick Links

- [Getting Started](guides/getting-started.md) — first steps with the SDK
- [API Reference](reference/) — auto-generated from source
- [GitHub](https://github.com/sgbett/bsv-ruby-sdk) — source code and issues
- Changelogs: [sdk](https://github.com/sgbett/bsv-ruby-sdk/blob/master/gem/bsv-sdk/CHANGELOG.md) · [wallet](https://github.com/sgbett/bsv-ruby-sdk/blob/master/gem/bsv-wallet/CHANGELOG.md) · [wallet-postgres](https://github.com/sgbett/bsv-ruby-sdk/blob/master/gem/bsv-wallet-postgres/CHANGELOG.md) · [attest](https://github.com/sgbett/bsv-ruby-sdk/blob/master/gem/bsv-attest/CHANGELOG.md)
