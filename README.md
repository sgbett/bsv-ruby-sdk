# BSV Ruby SDK

[![CI](https://github.com/sgbett/bsv-ruby-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/sgbett/bsv-ruby-sdk/actions/workflows/ci.yml)

Ruby implementation of the BSV Blockchain SDK.

## Acknowledgements

This Ruby SDK is a port of the official BSV Blockchain SDKs, which serve as its reference implementations. Primitives, script handling, and transaction logic are directly translated from them, adapted for Ruby idioms and conventions.

The reference SDKs:

- [TypeScript SDK](https://github.com/bsv-blockchain/ts-sdk)
- [Go SDK](https://github.com/bsv-blockchain/go-sdk)
- [Python SDK](https://github.com/bsv-blockchain/py-sdk)

These are maintained under the BSV Blockchain organisation and backed by the Bitcoin Association. The debt to their contributors is substantial — their clear, robust code made this port both feasible and consistent.

## Installation

Add to your Gemfile:

```ruby
gem "bsv-sdk"
```

Or install directly:

```bash
gem install bsv-sdk
```

## Development

```bash
git clone https://github.com/sgbett/bsv-ruby-sdk.git
cd bsv-ruby-sdk
bundle install
bundle exec rake        # run specs
bundle exec rubocop     # run linter
```

Requires Ruby >= 2.7.

## Licence

[Open BSV Licence Version 5](LICENCE)
