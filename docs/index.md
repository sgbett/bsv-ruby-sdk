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

## Quick Links

- [Getting Started](guides/getting-started.md) — first steps with the SDK
- [API Reference](reference/) — auto-generated from source
- [GitHub](https://github.com/sgbett/bsv-ruby-sdk) — source code and issues
- [Changelog](https://github.com/sgbett/bsv-ruby-sdk/blob/master/CHANGELOG.md) — release history
