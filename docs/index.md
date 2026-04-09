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

- **[Primitives](guides/primitives.md)** — keys, curves, hashing, encryption, HD keys, mnemonics
- **[Script](guides/script.md)** — script parsing, opcodes, templates, interpreter
- **[Transaction](guides/transaction.md)** — building, signing, BEEF serialisation, merkle proofs

## Companion gems

- **[bsv-wallet-postgres](guides/wallet-postgres.md)** — persistent PostgreSQL storage adapter for `bsv-wallet`, for production deployments that need state to survive restarts

## Quick Links

- [Getting Started](guides/getting-started.md) — first steps with the SDK
- [API Reference](reference/) — auto-generated from source
- [GitHub](https://github.com/sgbett/bsv-ruby-sdk) — source code and issues
- Changelogs: [sdk](https://github.com/sgbett/bsv-ruby-sdk/blob/master/CHANGELOG-sdk.md) · [wallet](https://github.com/sgbett/bsv-ruby-sdk/blob/master/CHANGELOG-wallet.md) · [wallet-postgres](https://github.com/sgbett/bsv-ruby-sdk/blob/master/CHANGELOG-wallet-postgres.md) · [attest](https://github.com/sgbett/bsv-ruby-sdk/blob/master/CHANGELOG-attest.md)
