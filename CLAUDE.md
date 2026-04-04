# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ruby SDK for the BSV Blockchain (`bsv-sdk` gem). Part of the official BSV SDK family alongside [go-sdk](https://github.com/bsv-blockchain/go-sdk), [ts-sdk](https://github.com/bsv-blockchain/ts-sdk), and [py-sdk](https://github.com/bsv-blockchain/py-sdk). Use those as reference implementations when building features.

**Reference SDK clones** are at `/opt/ruby/bsv-reference-sdks/` (`go-sdk/`, `ts-sdk/`, `py-sdk/`). Search these when implementing new features to match behaviour across SDKs. Run `git -C /opt/ruby/bsv-reference-sdks/<sdk> pull` to update before comparing.

The [BSV Hub protocol documentation](https://hub.bsvblockchain.org/bitcoin-protocol-documentation) is available via MCP (`.mcp.json`) for verifying protocol conformance during development.

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

### Script Parser vs Interpreter

The script system has two distinct layers with different responsibilities:

- **Parser** (`Script`, `Script.from_asm`, `Script.from_binary`, `chunks`, type detection) — structural analysis. Understands what a script *is*. Protocol-version-agnostic. This is where the "recognise everything" principle applies: any valid script (including historical pre-genesis constructs) should parse, serialise, and be identifiable.

- **Interpreter** (`Interpreter.evaluate`, `Interpreter.verify`) — behavioural execution. Determines whether a script *succeeds* under current consensus rules. Always operates in post-genesis mode. Scripts that were valid pre-genesis but invalid post-genesis (e.g. multiple `OP_ELSE` per `OP_IF`) will correctly fail execution — this is consensus enforcement, not a recognition failure.

A script being parseable but failing execution is not a bug — it's the distinction between these two layers working correctly.

## Cryptography

Elliptic curve operations (secp256k1) use a pure Ruby implementation (`BSV::Primitives::Secp256k1`) ported from the TypeScript reference SDK. An OpenSSL compatibility shim (`openssl_ec_shim.rb`) replaces `OpenSSL::PKey::EC` classes so consumer code continues to use the same API. See `docs/about/secp256k1.md` for details.

OpenSSL is used for hashing (SHA-256, RIPEMD-160, SHA-512), HMAC, PBKDF2, AES encryption, and constant-time comparison — no external gems.

Custom implementations: RFC 6979 deterministic signing, Schnorr signatures, Base58Check, BIP-32/39, secp256k1 field/point arithmetic.

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
