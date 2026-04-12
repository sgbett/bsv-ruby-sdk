# Changelog — bsv-attest

All notable changes to the `bsv-attest` gem are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this gem adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.2.0 — 2026-04-13

### Breaking Changes
- Removed `broadcaster` from `Attest::Configuration` — attestation now uses the wallet's broadcaster via `create_action`

### Added
- `BSV::Attest.publish` now uses `wallet.create_action` for transaction construction and broadcast (#414)
- `BSV::Attest::BroadcastError` class for create_action failures (#413)

### Changed
- `Attest::Response` simplified to hash + txid only (#412)

### Fixed
- Pass args as positional Hash to `create_action` for Ruby 2.7 compatibility (#414)

## 0.1.0

Initial release of `bsv-attest`.
