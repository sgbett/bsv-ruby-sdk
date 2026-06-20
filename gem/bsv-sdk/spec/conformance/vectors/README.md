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
| `script_tests.json` | go-sdk | `script/interpreter/data/script_tests.json` | `5cb9b59038ed590becc7eb64fd6ca6007be55a85` |
`beef.vectors.json` has been **removed** — BEEF conformance now uses the canonical ts-stack corpus:
`sdk/transactions/serialization.json` (vectors `tx-003`, `tx-006`) and
`regressions/beef-isvalid-hydration.json` + `regressions/beef-v2-txid-panic.json`.
Ruby-local fixtures without a canonical equivalent are inlined in `spec/conformance/beef_spec.rb`.
See [issue #849](https://github.com/sgbett/bsv-ruby-sdk/issues/849) for the upstream coverage suggestion.

`bump.vectors.json` has been superseded by canonical corpus vectors loaded from
`tmp/conformance-vectors/` via `ConformanceVectors.canonical` and
`ConformanceVectors.canonical_regression`. See `spec/conformance/bump_spec.rb` for
the vector IDs: `sdk/transactions/merkle-path.json` (17 vectors) and
`regressions/merkle-path-odd-node.json` (5 vectors).

`sighash_bip143.json` and `sighash_legacy.json` have been **removed**. FORKID
sighash conformance now reads from the canonical corpus (`sdk/scripts/evaluation.json`,
filtered to `["sighash"]`-tagged FORKID vectors). Legacy (pre-FORKID) sighash
has been retired permanently: BSV requires FORKID on all signatures, so these
vectors have no valid meaning on-chain. See the Protocol Philosophy section in
`CLAUDE.md` ("recognise everything, construct only what's valid") and issue #845.
