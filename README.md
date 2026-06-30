# BSV Ruby SDK

[![CI](https://github.com/sgbett/bsv-ruby-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/sgbett/bsv-ruby-sdk/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/sgbett/bsv-ruby-sdk/branch/master/graph/badge.svg)](https://codecov.io/gh/sgbett/bsv-ruby-sdk)
[![Gem Version](https://img.shields.io/gem/v/bsv-sdk)](https://rubygems.org/gems/bsv-sdk)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.3-red)](https://rubygems.org/gems/bsv-sdk)

A comprehensive Ruby SDK for the BSV Blockchain, built with faithful adherence to the [BRC specifications](https://github.com/bsv-blockchain/BRCs) and cross-SDK compatibility with the official [TypeScript](https://github.com/bsv-blockchain/ts-stack), [Go](https://github.com/bsv-blockchain/go-sdk), and [Python](https://github.com/bsv-blockchain/py-sdk) implementations. The Ruby SDK strives to be a complete, correct, and well-tested implementation that serves the Ruby community — one that developers can rely on as a reference-quality foundation for BSV application development.

The project is grounded in the principles that make Ruby and Rails productive: [convention over configuration](https://rubyonrails.org/doctrine#convention-over-configuration), sensible defaults, and [the principle of least surprise](https://en.wikipedia.org/wiki/Principle_of_least_astonishment). Every component ships with a sane default that works out of the box, while exposing a pluggable composition interface for teams that need more. A `WalletClient` created with a single private key and no configuration gives you a fully functional BRC-100 wallet backed by local file storage. The same `WalletClient` interface — the same `create_action`, `list_outputs`, `internalize_action` calls — works identically when composed with PostgreSQL storage, SolidQueue background workers, UTXO pools with pre-warmed transaction caches, overlay-service chain providers, and asynchronous ARC broadcast behind a load balancer. The interface stays the same; the architecture underneath scales with you.

## Table of Contents

1. [Acknowledgements](#acknowledgements)
2. [Objective](#objective)
3. [Getting Started](#getting-started)
4. [Features & Deliverables](#features--deliverables)
5. [Documentation](#documentation)
6. [Contribution Guidelines](#contribution-guidelines)
7. [Support & Contacts](#support--contacts)
8. [Licence](#licence)

## Acknowledgements

This Ruby SDK is a port of the official BSV Blockchain SDKs, which serve as its reference implementations. Primitives, script handling, and transaction logic are directly translated from them, adapted for Ruby idioms and conventions.

The reference SDKs:

- [TypeScript SDK](https://github.com/bsv-blockchain/ts-stack)
- [Go SDK](https://github.com/bsv-blockchain/go-sdk)
- [Python SDK](https://github.com/bsv-blockchain/py-sdk)

These are maintained under the BSV Blockchain organisation and backed by the Bitcoin Association. The debt to their contributors is substantial — their clear, robust code made this port both feasible and consistent.

## Objective

The BSV Blockchain Libraries Project aims to structure and maintain a middleware layer of the BSV Blockchain technology stack. By facilitating the development and maintenance of core libraries, it serves as an essential toolkit for developers looking to build on the BSV Blockchain.

This Ruby SDK brings maximum compatibility with the official SDK family to the Ruby ecosystem. It was born from a practical need: building an attestation gem ([bsv-attest](https://rubygems.org/gems/bsv-attest)) required a complete, idiomatic Ruby implementation of BSV primitives, script handling, and transaction construction. Rather than wrapping FFI bindings or shelling out to other languages, the SDK implements everything in pure Ruby. Elliptic curve operations (secp256k1) use a native Ruby implementation ported from the TypeScript reference SDK; OpenSSL is used only for hashing, HMAC, and symmetric encryption.

<!-- TODO: Update bsv-attest link once gem documentation is published (see #48) -->

## Getting Started

### Requirements

- Ruby >= 3.3
- No external dependencies beyond Ruby's standard library (`openssl` for hashing, HMAC, PBKDF2, and AES)

### Installation

Add to your Gemfile:

```ruby
gem 'bsv-sdk'
```

Or install directly:

```bash
gem install bsv-sdk
```

### Basic Usage

Create and sign a P2PKH transaction:

```ruby
require 'bsv-sdk'

# Generate a new private key (or load from WIF)
priv_key = BSV::Primitives::PrivateKey.generate

# Derive the public key hash for locking scripts
pubkey_hash = priv_key.public_key.hash160
locking_script = BSV::Script::Script.p2pkh_lock(pubkey_hash)

# Create a transaction spending a UTXO
tx = BSV::Transaction::Tx.new

# Add an input referencing a previous transaction output
# wtxid_from_hex converts a display-order hex txid to wire-order binary
utxo_txid = '5884e5db9de218238671572340b207ee85b628074e7e467096c267266baf77a4'
input = BSV::Transaction::TransactionInput.new(
  prev_wtxid: BSV::Transaction::TransactionInput.wtxid_from_hex(utxo_txid),
  prev_tx_out_index: 0
)
input.source_satoshis = 100_000
input.source_locking_script = locking_script
tx.add_input(input)

# Add an output sending to the same address (for demonstration)
tx.add_output(BSV::Transaction::TransactionOutput.new(
  satoshis: 90_000,
  locking_script: locking_script
))

# Sign the input using the P2PKH template
template = BSV::Transaction::P2PKH.new(priv_key)
tx.inputs[0].unlocking_script = template.sign(tx, 0)

# The signed transaction is ready to broadcast
puts tx.to_hex
```

## Features & Deliverables

- **Cryptographic Primitives** — ECDSA signing with RFC 6979 deterministic nonces, Schnorr signatures, ECIES encryption/decryption, Bitcoin Signed Messages. Elliptic curve operations are provided by the [`secp256k1-native`](https://github.com/sgbett/secp256k1-native) gem — a pure Ruby secp256k1 implementation with an optional C extension (~22× speedup).
- **Key Management** — BIP-32 HD key derivation, BIP-39 mnemonic generation (12/24-word phrases), WIF import/export, Base58Check encoding/decoding.
- **Script Layer** — Complete opcode set, script parsing and serialisation, type detection and predicates (`p2pkh?`, `p2pk?`, `p2sh?`, `multisig?`, `op_return?`), data extraction (pubkey hashes, script hashes, addresses), and a fluent builder API.
- **Script Templates** — Ready-made locking and unlocking script generators for P2PKH, P2PK, P2MS (multisig), and OP_RETURN.
- **Transaction Construction** — Input/output building, BIP-143 sighash computation (all SIGHASH types with FORKID), P2PKH signing, fee estimation.
- **SPV Structures** — Merkle path construction and verification, BEEF (Background Evaluation Extended Format) serialisation and deserialisation.
- **Network Integration** — ARC broadcaster for transaction submission, WhatsOnChain chain provider for UTXO queries and fee rates.
- **ProtoWallet** — Minimal BRC-100 cryptographic wallet for signing, encryption, HMAC, and key derivation. Full wallet functionality is provided by the standalone `bsv-wallet` gem.

## Documentation

Full documentation is available at **[sgbett.github.io/bsv-ruby-sdk](https://sgbett.github.io/bsv-ruby-sdk/)**.

**Guides:**

- [Getting Started](https://sgbett.github.io/bsv-ruby-sdk/guides/getting-started/) — installation, first transaction
- [Primitives](https://sgbett.github.io/bsv-ruby-sdk/sdk/primitives/) — keys, signing, encryption, HD keys
- [Script](https://sgbett.github.io/bsv-ruby-sdk/sdk/script/) — construction, templates, detection
- [Transaction](https://sgbett.github.io/bsv-ruby-sdk/sdk/transaction/) — building, signing, BEEF
**Additional resources:**

- [API Reference](https://sgbett.github.io/bsv-ruby-sdk/reference/api/) — auto-generated from YARD annotations
- [Sighash & Wire Cache](https://sgbett.github.io/bsv-ruby-sdk/reference/sighash-cache/) — Russian-doll memo cache, invalidation contract, escape hatch
- [spec/ directory](https://github.com/sgbett/bsv-ruby-sdk/tree/master/spec) — runnable usage examples
- Changelogs: [sdk](gem/bsv-sdk/CHANGELOG.md) · [attest](gem/bsv-attest/CHANGELOG.md)

**Protocol reference:**

The [BSV Protocol Documentation](https://hub.bsvblockchain.org/bitcoin-protocol-documentation) on the BSV Hub is the canonical protocol reference — covering transaction format, script opcodes, sighash flags, BEEF/SPV structures, and BRC specifications. The project includes an [MCP](https://modelcontextprotocol.io/) configuration (`.mcp.json`) that connects [Claude Code](https://docs.anthropic.com/en/docs/claude-code) to the hub's search endpoint, giving AI-assisted development sessions direct access to protocol specs during implementation.

## Contribution Guidelines

See [CONTRIBUTING.md](CONTRIBUTING.md) for branching, commits, docs conventions, and the security disclosure flow.

## Support & Contacts

Maintainer: Simon Bettison

For questions, bug reports, or feature requests, please [open an issue](https://github.com/sgbett/bsv-ruby-sdk/issues) on GitHub.

## Licence

[Open BSV Licence Version 5](LICENCE)

Thank you for being a part of the BSV Blockchain Libraries Project. Let's build the future of BSV Blockchain together!
