# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ruby SDK for the BSV Blockchain (`bsv-sdk` gem). Part of the official BSV SDK family alongside [go-sdk](https://github.com/bitcoin-sv/go-sdk), [ts-sdk](https://github.com/bitcoin-sv/ts-sdk), and [py-sdk](https://github.com/bitcoin-sv/py-sdk). Use those as reference implementations when building features.

Licence: Open BSV License Version 5.

## Commands

```bash
bundle exec rake              # run all specs (default task)
bundle exec rspec spec/bsv_spec.rb          # run a single spec file
bundle exec rspec spec/bsv_spec.rb:4        # run a single example by line
bundle exec rubocop                          # lint
bundle exec rubocop -A                       # lint with autocorrect
gem build bsv-sdk.gemspec                    # build gem
```

## Ruby Version Compatibility

- **Development:** Ruby 3.4.2 (`.ruby-version`)
- **Gem minimum:** `required_ruby_version >= 2.7` (gemspec)
- **Constraint:** Do not use Ruby 3.0+ features (pattern matching, `Hash#except`, `Data.define`, endless methods). The gem must run on Ruby 2.7. CI should test against 2.7.

## Architecture

Gem name: `bsv-sdk`. Namespace: `BSV::`. Entry point: `lib/bsv-sdk.rb`.

Three top-level modules loaded via `autoload`:

- **`BSV::Primitives`** — keys, curves, hashing, encryption
- **`BSV::Script`** — script parsing, opcodes, templates
- **`BSV::Transaction`** — building, signing, BEEF, merkle proofs

Build order follows the same dependency chain as the other SDKs: primitives → script → transaction → everything else.

## Cryptography

Use Ruby's stdlib `openssl` for all cryptography — no external gems. `OpenSSL::PKey::EC` supports secp256k1 natively, covering ECDSA, SHA-256, RIPEMD-160, AES, HMAC, and ECDH.

Items needing custom implementation: RFC 6979 deterministic signing, Schnorr signatures, Base58Check, BIP-32/39.

## Conventions

- `Gemfile.lock` is **not committed** (standard for gems; consumers resolve their own dependency tree)
- Dev dependencies go in `Gemfile`, not in gemspec `add_development_dependency`
- No `ruby` directive in Gemfile (hard Bundler constraint inappropriate for libraries)
- All files use `# frozen_string_literal: true`
- RuboCop targets Ruby 2.7; single-quoted strings preferred
