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
sha256sum gem/bsv-sdk/spec/bsv/primitives/vectors/wycheproof_ecdsa_secp256k1.json
```

Update the SHA-256 and date-vendored fields in this README whenever the file
is refreshed.
