# BSV Ruby SDK

Ruby SDK for the BSV Blockchain. Part of the official BSV SDK family alongside
[Go](https://github.com/bsv-blockchain/go-sdk),
[TypeScript](https://github.com/bsv-blockchain/ts-stack), and
[Python](https://github.com/bsv-blockchain/py-sdk).

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

## Ecosystem Clients

Higher-level overlay clients for working with on-chain services:

- **[Storage](sdk/storage.md)** — UHRP URL utilities and content download with hash verification
- **[KVStore](sdk/kvstore.md)** — read from the global key-value store overlay
- **[Ecosystem Clients](sdk/ecosystem-clients.md)** — Registry typed resolves, Overlay Historian

## Overlay services

End-user facing explanations of the overlay protocols the SDK supports,
including how each one fits with the `bsv-wallet` write paths:

- **[Overlay services overview](overlays.md)** — what overlays are, BRC-22/24 architecture, SDK vs wallet split
- **[UHRP Storage](overlays/uhrp-storage.md)** — content-addressed file storage (BRC-26)
- **[Historian](overlays/historian.md)** — walk on-chain state through transaction ancestry
- **[KVStore](overlays/kvstore.md)** — overlay-backed signed key-value entries
- **[Registries](overlays/registries.md)** — typed basket / protocol / certificate definitions

## Companion gems

- **[bsv-wallet](https://github.com/sgbett/bsv-wallet)** — BRC-100 wallet interface with `BSV::Wallet::Client`, storage adapters, and broadcast queue
- **[bsv-wallet-postgres](https://github.com/sgbett/bsv-wallet)** — PostgreSQL storage adapter and async broadcast queue for production deployments
- **[bsv-attest](https://rubygems.org/gems/bsv-attest)** — document attestation via OP_RETURN on the BSV blockchain

## Quick Links

- [Getting Started](guides/getting-started.md) — first steps with the SDK
- [API Reference](reference/api/) — auto-generated from source
- [GitHub](https://github.com/sgbett/bsv-ruby-sdk) — source code and issues
- Changelogs: [sdk](https://github.com/sgbett/bsv-ruby-sdk/blob/master/gem/bsv-sdk/CHANGELOG.md) · [wallet](https://github.com/sgbett/bsv-ruby-sdk/blob/master/gem/bsv-wallet/CHANGELOG.md) · [wallet-postgres](https://github.com/sgbett/bsv-ruby-sdk/blob/master/gem/bsv-wallet-postgres/CHANGELOG.md) · [attest](https://github.com/sgbett/bsv-ruby-sdk/blob/master/gem/bsv-attest/CHANGELOG.md)
