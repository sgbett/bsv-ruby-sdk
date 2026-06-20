# Cross-SDK conformance vectors

This directory contains canonical test vectors vendored verbatim from the
BSV reference SDKs. They are used by specs under `spec/conformance/` to
cross-validate the Ruby SDK's behaviour against the Go and TypeScript
reference implementations.

See [`docs/testing/conformance-vectors.md`](../../../docs/testing/conformance-vectors.md)
for the sync procedure and guidance on adding new families.

Tracking issue: [sgbett/bsv-ruby-sdk#307](https://github.com/sgbett/bsv-ruby-sdk/issues/307)

## Provenance

Every vector file below has been copied byte-for-byte from the listed source
so that a `diff` against upstream makes drift trivially visible.

| File | Source SDK | Source path | Commit SHA |
|---|---|---|---|
| `SymmetricKey.vectors.json` | go-sdk | `primitives/ec/testdata/SymmetricKey.vectors.json` | `5cb9b59038ed590becc7eb64fd6ca6007be55a85` |
| `sighash_legacy.json` | go-sdk | `script/interpreter/data/sighash_legacy.json` | `5cb9b59038ed590becc7eb64fd6ca6007be55a85` |
| `sighash_bip143.json` | go-sdk | `script/interpreter/data/sighash_bip143.json` | `5cb9b59038ed590becc7eb64fd6ca6007be55a85` |
| `script_tests.json` | go-sdk | `script/interpreter/data/script_tests.json` | `5cb9b59038ed590becc7eb64fd6ca6007be55a85` |
| `bump.vectors.json` | go-sdk | `transaction/testdata/bump.go` (transliterated) | `5cb9b59038ed590becc7eb64fd6ca6007be55a85` |
| `beef.vectors.json` | go-sdk | `transaction/beef_test.go` constants `BRC62Hex`, `BEEF`, `BEEFSet` + `transaction/testdata/bump.go` constant `Issue96BeefHex` | `5cb9b59038ed590becc7eb64fd6ca6007be55a85` |

`bump.vectors.json` and `beef.vectors.json` are not byte-identical to upstream
because upstream stores them inside Go source files rather than as standalone
JSON. They are faithful transliterations; each vector is one Go literal copied
verbatim into a JSON string.
