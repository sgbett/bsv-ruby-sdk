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

### Declarative vs Imperative Split

The SDK is **declarative** — it defines what things *are*: data structures, serialisation formats, cryptographic algorithms, protocol rules. It answers questions like "what is a transaction?", "how do you derive an HD key?", "how is a script encoded?".

Companion gems (e.g. `bsv-attest`, a future `bsv-wallet`) are **imperative** — they define what to *do*: workflows, use-cases, and orchestration. They answer questions like "attest a document", "set up a wallet from a mnemonic", "broadcast and track a payment".

The SDK should be substantially complete before building new companion gems. Early gem development tends to collide with missing SDK primitives. When the SDK covers the declarative layer thoroughly, gems become thin orchestration layers that pick and choose the SDK capabilities they need. Every companion gem pulls in `bsv-sdk` as its core dependency.

There will be grey areas — the existing `BSV::Wallet` and `BSV::Network` modules live in the SDK but lean imperative. The principle is directional, not absolute.

## Protocol Philosophy

BSV preserves the original Bitcoin protocol design. The SDK reflects this: it implements what the BSV network supports today.

**Recognise everything, construct only what's valid.** The SDK provides full parsing and detection of all script types (including legacy and historical outputs), but does not provide constructors for protocol features BSV has removed or never adopted. For example:

- `p2sh?` detection and `script_hash` extraction are supported (read-only)
- `p2sh_lock` / `p2sh_unlock` constructors are not provided (P2SH is not valid on BSV)
- SegWit, Taproot (BIP-340), Replace-by-Fee, and bech32 addresses are not implemented

When reference SDKs (Go, TS, Python) include features that conflict with this principle, this principle takes precedence.

## Cryptography

Use Ruby's stdlib `openssl` for all cryptography — no external gems. `OpenSSL::PKey::EC` supports secp256k1 natively, covering ECDSA, SHA-256, RIPEMD-160, AES, HMAC, and ECDH.

Items needing custom implementation: RFC 6979 deterministic signing, Schnorr signatures, Base58Check, BIP-32/39.

## Conventions

- `Gemfile.lock` is **not committed** (standard for gems; consumers resolve their own dependency tree)
- Dev dependencies go in `Gemfile`, not in gemspec `add_development_dependency`
- No `ruby` directive in Gemfile (hard Bundler constraint inappropriate for libraries)
- All files use `# frozen_string_literal: true`
- RuboCop targets Ruby 2.7; single-quoted strings preferred

## AI Software Architect Framework

This project uses the AI Software Architect framework for architectural decision tracking and reviews.

### Available Commands

- **Create ADR**: "Create ADR for [decision]"
- **Architecture Review**: "Start architecture review for version X.Y.Z"
- **Specialist Review**: "Ask [specialist role] to review [target]"
- **List Members**: "List architecture members"
- **Status**: "What's our architecture status?"

### Documentation

All architecture documentation is in `.architecture/`:
- **ADRs**: `.architecture/decisions/adrs/`
- **Reviews**: `.architecture/reviews/`
- **Principles**: `.architecture/principles.md`
- **Team**: `.architecture/members.yml`
