# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-03-07

### Added

#### Primitives

- ECDH shared secret derivation (`PrivateKey#derive_shared_secret`, `PublicKey#derive_shared_secret`)
- BRC-42 key derivation (`PrivateKey#derive_child`, `PublicKey#derive_child`) with official spec test vectors

#### Transaction

- Chain tracker interface (`ChainTracker` base class) with WhatsOnChain implementation
- Fee model interface (`FeeModel` base class) with `SatoshisPerKilobyte` implementation
- `Transaction#fee` with change output distribution across multiple change outputs
- `Transaction#verify` for full SPV verification (merkle path, script execution, recursive ancestry)
- `TransactionOutput#change` flag for identifying change outputs
- `MerklePath#verify` for SPV chain tracker integration
- BEEF completion: `Beef#merge`, `Beef#valid?`, lookup methods (`find_bump`, `find_transaction_for_signing`)
- `Transaction#to_beef` / `Transaction.from_beef` convenience methods
- Extended Format (EF) transaction serialisation (`to_ef`, `to_ef_hex`, `from_ef`, `from_ef_hex`)
- `VerificationError` with typed error codes for SPV verification failures

### Changed

- ECIES refactored to use `PrivateKey#derive_shared_secret` internally (no API change)
- `Transaction#estimated_size` made public for fee model access

### Fixed

- Nil `source_satoshis` now raises instead of silently coercing to zero in fee distribution and verification
- Script chunk round-trips preserve original push encoding
- `OP_RETURN` inside conditionals correctly checked for conditional balance
- Point x-coordinate extraction preserves leading zeros via octet string
- `Integer#nobits?` replaced with Ruby 2.7-compatible bitwise check
- Defensive parsing with descriptive errors for truncated binary input

### Testing

- BRC-42 conformance specs with 9 official specification test vectors
- ECDH conformance specs (commutativity, cross-method, pinned known-key vector)
- SPV verification conformance specs (merkle path, script execution, ancestry)
- Fee model conformance specs (formula validation, default rate, change distribution)
- Chain tracker conformance specs
- BEEF cross-SDK conformance vectors
- Schnorr (BRC-94) cross-SDK interoperability vectors
- 6 exact-match RFC 6979 vectors from Trezor/CoreBitcoin
- VarInt boundary tests at size-prefix transitions
- Script vectors converted to tracked known-failures system

## [0.1.0] - 2026-02-14

Initial release of the BSV Ruby SDK.

### Added

#### Primitives

- secp256k1 elliptic curve operations (point arithmetic, scalar multiplication)
- ECDSA signing and verification with RFC 6979 deterministic nonces
- Public and private key handling (WIF import/export, compressed/uncompressed formats)
- Base58Check encoding and decoding
- Hash functions: SHA-256, RIPEMD-160, Hash160 (SHA-256 + RIPEMD-160), SHA-512, HMAC
- BIP-32 hierarchical deterministic key derivation (extended keys, hardened/normal child paths)
- BIP-39 mnemonic phrase generation and seed derivation
- ECIES encryption and decryption (BIE1 format)
- Bitcoin Signed Message (BSM) signing and verification

#### Script

- Opcode constants (full set)
- Script chunk representation and parsing
- Script serialisation and deserialisation
- Script templates: P2PKH, P2PK, P2MS (multisig), OP_RETURN data
- Script type detection (including read-only recognition of P2SH and other legacy types)
- Script builder API for programmatic construction
- Script interpreter with stack operations, arithmetic, crypto, flow control, splice, and bitwise ops

#### Transaction

- Transaction construction and serialisation (raw format)
- BIP-143 sighash computation (all hash types with FORKID)
- Transaction signing with configurable sighash flags
- BEEF serialisation (BRC-95/BRC-96)
- Merkle path representation and verification
- Fee estimation
- Script verification during signing
- Unlocking script templates for common script types

#### Network

- ARC broadcaster for transaction submission
- WhatsOnChain chain data provider
- Basic wallet functionality

#### Testing

- Cross-SDK test vectors from Go, TypeScript, and Python reference implementations
- NIST and RFC hash function test vectors
- Bitcoin Core script interpreter test suite
- Protocol conformance specs for opcodes, sighash flags, and transaction templates
