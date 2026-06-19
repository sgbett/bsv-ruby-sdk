# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ruby SDK for the BSV Blockchain (`bsv-sdk` gem). Part of the official BSV SDK family alongside [go-sdk](https://github.com/bsv-blockchain/go-sdk), [ts-stack](https://github.com/bsv-blockchain/ts-stack) (the TS SDK lives at `packages/sdk/` inside this monorepo), and [py-sdk](https://github.com/bsv-blockchain/py-sdk). Use those as reference implementations when building features.

**Reference SDK clones** are kept under language-appropriate locations:

- **TypeScript (now a monorepo)** — `/opt/js/ts-stack/` (the `bsv-blockchain/ts-stack` repo). The SDK lives at `packages/sdk/`; wallet-toolbox at `packages/wallet/wallet-toolbox/`.
- **Go** — `/opt/go/go-sdk/` and `/opt/go/wallet-toolbox/`.
- **Python** — `/opt/python/py-sdk/` and `/opt/python/wallet-toolbox/`.

Search these when implementing new features to match behaviour across SDKs. Run `git -C <clone-path> pull` to update before comparing. The previous `/opt/ruby/bsv-reference-sdks/` location is gone — none of these are Ruby, so they don't belong under `/opt/ruby/`.

The [BSV Hub protocol documentation](https://hub.bsvblockchain.org/bitcoin-protocol-documentation) is available via MCP (`.mcp.json`) for verifying protocol conformance during development.

Licence: Open BSV License Version 5.

## Commands

```bash
bundle exec rake              # run all specs (default task)
bundle exec rake spec:sdk     # run only bsv-sdk specs
bundle exec rake spec:attest  # run only bsv-attest specs
cd gem/bsv-sdk && bundle exec rspec spec/bsv_spec.rb      # run a single spec file
cd gem/bsv-sdk && bundle exec rspec spec/bsv_spec.rb:4    # run a single example by line
bundle exec rubocop                          # lint
bundle exec rubocop -A                       # lint with autocorrect
cd gem/bsv-sdk && gem build bsv-sdk.gemspec  # build gem (must run from inside gem/<name>/)
```

## Ruby Version Compatibility

- **Development:** Ruby 3.4.2 (`.ruby-version`)
- **Gem minimum:** `required_ruby_version >= 3.3` (gemspec)
- **Constraint:** Do not use Ruby 3.4+ features (e.g. `it` block parameter). The gem must run on Ruby 3.3. CI tests against 3.3, 3.4, and 4.0.
- **Available:** Pattern matching, `Hash#except`, `Data.define`, endless methods, and all Ruby 3.0–3.3 features are available and encouraged where they improve clarity.

## Architecture

Gem name: `bsv-sdk`. Namespace: `BSV::`. Entry point: `lib/bsv-sdk.rb`.

Three top-level modules loaded via `autoload`:

- **`BSV::Primitives`** — keys, curves, hashing, encryption
- **`BSV::Script`** — script parsing, opcodes, templates
- **`BSV::Transaction`** — building, signing, BEEF, merkle proofs

Build order follows the same dependency chain as the other SDKs: primitives → script → transaction → everything else.

### Declarative vs Imperative Split

The SDK (`bsv-sdk`) is **declarative** — it defines what things *are*: data structures, serialisation formats, cryptographic algorithms, protocol rules. It answers questions like "what is a transaction?", "how do you derive an HD key?", "how is a script encoded?".

The declarative/imperative split applies **only to the SDK itself**. The SDK should not contain workflows, use-cases, or orchestration logic — those belong in companion gems.

Companion gems (e.g. `bsv-attest`) are free to mix declarative and imperative code as their scope of responsibility demands. Each gem owns its domain and organises code by responsibility, not by declarative/imperative taxonomy.

The SDK includes `BSV::Wallet::ProtoWallet` — a minimal cryptographic wallet providing BRC-100 crypto operations (signing, encryption, HMAC, key derivation) without transactions, storage, or blockchain interaction. Full wallet functionality lives in the standalone `bsv-wallet` gem.

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

### Transaction ID Convention

Transaction IDs use an explicit naming convention to prevent byte-order bugs:

- **`wtxid`** — wire-order binary (32 bytes). Used internally, in storage, and across all Ruby interfaces.
- **`dtxid` / `dtxid_hex`** — display-order hex (64 chars). Used only at JSON and UI boundaries.
- **`txid`** — reserved for spec-mandated names (BRC-100, BRC-74, ARC API), always with a boundary comment.

Any method that accepts a txid parameter must validate the format using `BSV::Primitives::Hex.validate_wtxid!` or `BSV::Primitives::Hex.validate_dtxid_hex!`. This catches byte-order mismatches at call time rather than producing silent corruption. See `docs/guides/wtxid-dtxid.md` for the full rationale.

### Transaction Class Convention: `Transaction::Tx` in prose

A transaction is an abstract entity with several representations: bytes on the wire, a BEEF bundle, a Ruby `Transaction::Tx` instance. The English word and the Ruby class are not interchangeable.

In prose, comments, YARD tags, and spec descriptions:

- **`Transaction::Tx`** names the Ruby class or its instances. Use this whenever the meaning is "the class instance specifically". The `BSV::` prefix is redundant for the audience — gem consumers read `Namespace::Class` instinctively.
- **`transaction`** (lowercase) is the English noun for the abstract entity. Use this when the representation doesn't matter, or when several representations are in play.
- **`Tx`** bare is for Ruby code where the `BSV::Transaction` namespace is already in lexical scope (inside a `module BSV::Transaction` block, a sibling file in that namespace, or after `include BSV::Transaction`). It does not resolve in unrelated namespaces — use `BSV::Transaction::Tx` there. Outside Ruby code, bare `Tx` reads as an alien identifier.

The same shape extends to peer classes (`Transaction::Beef`, `Transaction::TransactionInput`, `Transaction::TransactionOutput`, `Transaction::ChainTracker`, etc.).

#### Examples

| Reads | Means |
|-------|-------|
| "the cached `Transaction::Tx`" | Ruby instance, fully hydrated |
| "`Transaction::Tx#verify` walks via `input.source_transaction`" | Class method reference |
| "the transaction is rejected at broadcast time" | The abstract entity at any stage |
| "atomic BEEF carries the transaction graph" | Abstract entity, multi-representation |

#### Runnable code blocks keep `BSV::`

This convention applies to prose. **Runnable Ruby code blocks in `docs/` keep the fully-qualified `BSV::Foo::Bar` form** because they have to compile when copy-pasted. The orthogonal rule:

- **Where text is parsed by humans** (prose, comments, YARD tags, headings) — drop `BSV::`.
- **Where text is parsed by Ruby** (code blocks meant to be run, method bodies) — keep `BSV::`.

#### Source

Mirrored from the `bsv-wallet` gem's `CLAUDE.md`, where the convention was settled in PR sgbett/bsv-wallet#304 during the SDK 0.24.0 rename migration. HLR sgbett/bsv-ruby-sdk#825 extends it here to keep the two gems aligned.

## Cryptography

Elliptic curve operations (secp256k1) are provided by the [`secp256k1-native`](https://github.com/sgbett/secp256k1-native) gem — a pure Ruby implementation ported from the TypeScript reference SDK, with an optional native C extension that accelerates field, scalar, and Jacobian point operations (~22× speedup). The `bsv-sdk` exposes these as `BSV::Primitives::Secp256k1` and `BSV::Primitives::Secp256k1Native`. An OpenSSL compatibility shim (`openssl_ec_shim.rb`) replaces `OpenSSL::PKey::EC` classes so consumer code continues to use the same API. See the [secp256k1-native documentation](https://github.com/sgbett/secp256k1-native/blob/master/docs/secp256k1.md) for implementation details.

OpenSSL is used for hashing (SHA-256, RIPEMD-160, SHA-512), HMAC, PBKDF2, AES encryption, and constant-time comparison — no external gems.

Custom implementations: RFC 6979 deterministic signing, Schnorr signatures, Base58Check, BIP-32/39, secp256k1 field/point arithmetic.

## Conventions

- `Gemfile.lock` is **not committed** (standard for gems; consumers resolve their own dependency tree)
- Dev dependencies go in `Gemfile`, not in gemspec `add_development_dependency`
- No `ruby` directive in Gemfile (hard Bundler constraint inappropriate for libraries)
- All files use `# frozen_string_literal: true`
- RuboCop targets Ruby 3.3; single-quoted strings preferred
## Releasing Gems

Use `/release <key>` as the canonical release mechanism. The skill guides you through pre-flight checks, version bumping, changelog generation, tagging, pushing, gem build, RubyGems push, and GitHub release creation — one gem at a time.

The repo ships two gems:

```
bsv-sdk → bsv-attest
```

### Tag Prefix Conventions

| Gem | Key | Tag prefix | Example |
|-----|-----|-----------|---------|
| `bsv-sdk` | `sdk` | `v` | `v0.10.0` |
| `bsv-attest` | `attest` | `attest-v` | `attest-v0.1.0` |

### RubyGems

The `/release` skill builds the gem and instructs you to push manually — RubyGems credentials are yours to control. The skill cannot push to RubyGems on your behalf.

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
