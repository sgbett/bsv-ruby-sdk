# secp256k1 compliance test vectors

This directory contains test vectors vendored from external sources for use in
the secp256k1 compliance suite. Specs under `spec/bsv/primitives/` that use
these vectors are `secp256k1_wycheproof_spec.rb`, `secp256k1_rfc6979_spec.rb`,
and `secp256k1_compliance_spec.rb`.

## Provenance

### Vendored files

| File | Source | Cases | SHA-256 |
|---|---|---|---|
| `wycheproof_ecdsa_secp256k1.json` | `google/wycheproof` — `testvectors_v1/ecdsa_secp256k1_sha256_test.json` | 474 | `52b22d7f9ae132325491825e6d15e09525c3eecd6e717559f99fbdf3a78664f3` |
| `wycheproof_ecdsa_secp256k1_bitcoin.json` | `C2SP/wycheproof` — `testvectors_v1/ecdsa_secp256k1_sha256_bitcoin_test.json` | 463 | `27c848b8cfa4e3f3bfbda27971542dd9b827e393842d5549fdfdf1923771c756` |

All vendored files are byte-identical to upstream. A `diff` against the source
URL below is sufficient to verify this.

#### `wycheproof_ecdsa_secp256k1.json`

- **Source:** `google/wycheproof` repository
- **Source path:** `testvectors_v1/ecdsa_secp256k1_sha256_test.json`
- **URL:** `https://raw.githubusercontent.com/google/wycheproof/master/testvectors_v1/ecdsa_secp256k1_sha256_test.json`
- **Date vendored:** 2026-04-25
- **Test cases:** 474 (166 valid, 308 invalid, 0 acceptable)
- **Modifications:** none — byte-identical to upstream
- **Schema:** `ecdsa_verify_schema_v1.json`

#### `wycheproof_ecdsa_secp256k1_bitcoin.json`

- **Source:** `C2SP/wycheproof` repository (Bitcoin-specific fork — **not** `google/wycheproof`)
- **Source path:** `testvectors_v1/ecdsa_secp256k1_sha256_bitcoin_test.json`
- **URL:** `https://raw.githubusercontent.com/C2SP/wycheproof/main/testvectors_v1/ecdsa_secp256k1_sha256_bitcoin_test.json`
- **Date vendored:** 2026-04-29
- **Test cases:** 463 (162 valid, 301 invalid, 0 acceptable)
- **Modifications:** none — byte-identical to upstream
- **Schema:** `ecdsa_bitcoin_verify_schema.json`
- **Note:** These vectors test ECDSA verification with Bitcoin's non-malleability rule (low-S
  enforcement). Cases flagged `SignatureMalleabilityBitcoin` have high-S signatures that are
  mathematically valid ECDSA but rejected by Bitcoin's protocol policy. Raw `ECDSA.verify` is
  correct to accept them; low-S enforcement belongs in the script interpreter, not the
  cryptographic primitive. See `docs/testing/wycheproof-malleability-analysis.md`.

### Inline vectors

Some vector data is defined directly in spec files rather than in separate
JSON files. These are documented here for completeness.

#### RFC 6979 deterministic ECDSA vectors (`secp256k1_rfc6979_spec.rb`)

- **Source:** Trezor/CoreBitcoin test suites, also used by the BSV Go SDK
  - Trezor: `https://github.com/trezor/trezor-crypto/blob/master/tests.c`
  - CoreBitcoin: `https://github.com/oleganza/CoreBitcoin/blob/master/CoreBitcoin/BTCKey%2BTests.m`
- **Test cases:** 6 (private key + message → expected DER signature)
- **Modifications:** none — values transcribed verbatim from the sources above

#### Known G multiples (`secp256k1_compliance_spec.rb`)

- **Source:** computed from the secp256k1 generator point using standard EC
  point arithmetic; independently verifiable using any correct secp256k1
  implementation
- **Points:** 2G, 3G, 4G, 5G, 6G, 7G, (N-1)G (affine x/y coordinates)
- **Modifications:** none

## Sync procedure

To re-vendor `wycheproof_ecdsa_secp256k1.json` from upstream:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/google/wycheproof/master/testvectors_v1/ecdsa_secp256k1_sha256_test.json \
  -o gem/bsv-sdk/spec/bsv/primitives/vectors/wycheproof_ecdsa_secp256k1.json

# Verify SHA-256 after download and update this README if it changes
shasum -a 256 gem/bsv-sdk/spec/bsv/primitives/vectors/wycheproof_ecdsa_secp256k1.json
```

To re-vendor `wycheproof_ecdsa_secp256k1_bitcoin.json` from upstream:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/C2SP/wycheproof/main/testvectors_v1/ecdsa_secp256k1_sha256_bitcoin_test.json \
  -o gem/bsv-sdk/spec/bsv/primitives/vectors/wycheproof_ecdsa_secp256k1_bitcoin.json

# Verify SHA-256 after download and update this README if it changes
shasum -a 256 gem/bsv-sdk/spec/bsv/primitives/vectors/wycheproof_ecdsa_secp256k1_bitcoin.json
```

Update the SHA-256 and date-vendored fields in this README whenever a file
is refreshed.
