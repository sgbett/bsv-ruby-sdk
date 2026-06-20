# Cross-SDK conformance vectors

Canonical vector provenance is now tracked in
[`.architecture/conformance.lock`](../../../.architecture/conformance.lock).
See [`docs/testing/conformance-vectors.md`](../../../docs/testing/conformance-vectors.md)
for the sync procedure and guidance on adding new families.

## Ruby-local fixtures

These files have no canonical equivalent in the ts-stack corpus and are kept here
with explicit skip-with-reason in their specs:

| File | Source SDK | Why Ruby-local |
|---|---|---|
| `SymmetricKey.vectors.json` | go-sdk `primitives/ec/testdata/SymmetricKey.vectors.json` at `5cb9b59` | Base64 AES-256-GCM round-trip vectors; canonical corpus has NIST AES vectors with different inputs |

## Retired files

`script_tests.json` — removed. Script evaluation conformance now reads from the
canonical corpus (`sdk/scripts/evaluation.json`). See `spec/conformance/script_tests_spec.rb` and issue #846.

`beef.vectors.json` — removed. BEEF conformance now uses the canonical ts-stack corpus
(`sdk/transactions/serialization.json`, `regressions/beef-isvalid-hydration.json`,
`regressions/beef-v2-txid-panic.json`). Ruby-local fixtures are inlined in
`spec/conformance/beef_spec.rb`. See [issue #849](https://github.com/sgbett/bsv-ruby-sdk/issues/849).

`bump.vectors.json` — removed. Merkle path conformance now uses the canonical corpus
(`sdk/transactions/merkle-path.json`, `regressions/merkle-path-odd-node.json`).
See `spec/conformance/bump_spec.rb`.

`sighash_bip143.json` and `sighash_legacy.json` — removed. FORKID sighash conformance
reads from the canonical corpus (`sdk/scripts/evaluation.json`, `["sighash"]`-tagged
vectors). Legacy (pre-FORKID) sighash has been retired permanently: BSV requires
FORKID on all signatures, so these vectors have no valid meaning on-chain. See the
Protocol Philosophy section in `CLAUDE.md` and issue #845.
