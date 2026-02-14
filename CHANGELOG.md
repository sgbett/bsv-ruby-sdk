# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
