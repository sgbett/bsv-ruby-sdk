# Technical Analyst Memory

## Project Structure
- Gem: `bsv-sdk`, namespace: `BSV::`, entry: `lib/bsv-sdk.rb`
- Three modules: `BSV::Primitives`, `BSV::Script`, `BSV::Transaction`
- Reference SDKs at `/opt/ruby/bsv-reference-sdks/` (go-sdk, ts-sdk, py-sdk)
- Ruby 2.7 minimum compatibility required

## Existing Primitives (verified)
- `PointInFiniteField` at `lib/bsv/primitives/point_in_finite_field.rb` - uses OpenSSL::BN, Base58 dot-separated format
- `Base58.encode/decode` at `lib/bsv/primitives/base58.rb` - handles leading zeros
- `Digest.hmac_sha512(key, data)` at `lib/bsv/primitives/digest.rb`
- `Digest.hash160(data)` at `lib/bsv/primitives/digest.rb`
- `PublicKey#hash160` and `PublicKey#compressed` at `lib/bsv/primitives/public_key.rb`
- `PrivateKey` at `lib/bsv/primitives/private_key.rb` - OpenSSL::BN based, from_bytes/from_wif/to_wif
- `Curve` at `lib/bsv/primitives/curve.rb` - GROUP, N, G, HALF_N constants

## SSS Implementation Notes (HLR #155)
- All SDKs use secp256k1 field prime P (not curve order N) for SSS arithmetic
- P is defined in PointInFiniteField::P
- OpenSSL::BN#mod handles negative values correctly (returns non-negative for positive modulus)
- OpenSSL::BN#mod_inverse available for Lagrange interpolation
- HMAC-SHA-512: seed (64 bytes) is key, counter is message
- Go SDK counter encoding (4-byte uint32) differs from TS/Python (1-byte) -- follow TS/Python
- Backup format: "base58(x).base58(y).threshold.integrity" (4 dot-separated parts)
- Integrity = HASH160(compressed_pubkey).hex[0..7] (first 8 hex chars)
- Cross-SDK test vector WIF: L1vTr2wRMZoXWBM3u1Mvbzk9bfoJE5PT34t52HYGt9jzZMyavWrk (hex: 8c507a209d082d9db947bea9ffb248bbb977e59953405dacf5ea8c4be3a11a2f)
- Sample backup shares with integrity 2f804d43 available in TS/Python tests

## Benford's Law Change Distribution (HLR #156)
- Only TS SDK implements random change distribution; Go SDK has "not-implemented"
- TS algorithm: reserve 1 sat/output, iterate 0..n-2 taking Benford portions, last gets remainder
- `benfordNumber(min, max)`: d in [1..9], floor(min + (max-min) * log10(1+1/d))
- TS remainder goes to last *transaction* output (potential bug) -- recommended: last *change* output
- Ruby `fee` method at `lib/bsv/transaction/transaction.rb` line 609, `distribute_change` at line 712
- Existing fee specs at `spec/bsv/transaction/transaction_fee_spec.rb`

## Reference SDK File Locations
- TS Polynomial: `ts-sdk/src/primitives/Polynomial.ts`
- TS PrivateKey SSS: `ts-sdk/src/primitives/PrivateKey.ts` (lines 431-550)
- TS Change Distribution: `ts-sdk/src/transaction/Transaction.ts` (lines 502-541)
- Go SSS: `go-sdk/primitives/ec/shamir.go`
- Go keyshares: `go-sdk/primitives/keyshares/`
- Go tests: `go-sdk/primitives/ec/shamir_test.go`
- Python SSS: `py-sdk/bsv/polynomial.py` and `py-sdk/bsv/keys.py`
