# Cross-SDK conformance vectors

The Ruby SDK validates its behaviour against canonical test vectors from the
other BSV reference SDKs (Go, TypeScript). This keeps Ruby's output aligned
with the rest of the SDK family rather than just self-consistent, which is
the letter-versus-spirit risk the cross-SDK compliance review surfaced.

Tracking issue: [sgbett/bsv-ruby-sdk#307](https://github.com/sgbett/bsv-ruby-sdk/issues/307)

## Layout

```
spec/
├── conformance/
│   ├── vectors/
│   │   ├── README.md               ← provenance (source SDK, path, commit SHA)
│   │   ├── BRC42.private.vectors.json
│   │   ├── BRC42.public.vectors.json
│   │   ├── SymmetricKey.vectors.json
│   │   ├── sighash_bip143.json
│   │   ├── sighash_legacy.json
│   │   ├── script_tests.json
│   │   ├── bump.vectors.json
│   │   └── beef.vectors.json
│   ├── brc42_key_derivation_spec.rb
│   ├── symmetric_key_spec.rb
│   ├── sighash_bip143_spec.rb
│   ├── sighash_legacy_spec.rb
│   ├── script_tests_spec.rb
│   ├── beef_spec.rb
│   ├── bump_spec.rb
│   └── …
└── support/
    └── conformance_vectors.rb      ← tiny JSON loader (auto-required)
```

The loader is intentionally minimal. It only provides two methods:

- `ConformanceVectors.load(filename)` — returns the parsed JSON as-is.
- `ConformanceVectors.load_rows(filename)` — for Bitcoin Core-style files
  that mix test rows with single-element comment rows, returns only the
  test rows.

Per-family parsing logic lives in each spec, not in the loader. Keep the
loader dumb on purpose — if you find yourself wanting to add a generic
decoder, resist and add it to the spec that needs it instead.

## Running

Conformance specs are part of the default test suite:

```sh
bundle exec rake                         # everything
bundle exec rspec spec/conformance/      # conformance only
bundle exec rspec --tag conformance      # conformance (via tag)
```

The tag is applied automatically by `spec/support/conformance_helper.rb` to
every file under `spec/conformance/`.

## Adding a new vector family

1. **Copy the source file verbatim** into `spec/conformance/vectors/`. Byte
   identity with upstream matters — it makes future syncs a plain `diff`.
   If the source is embedded inside another language's source file (like
   go-sdk's BEEF constants in `beef_test.go`), transliterate faithfully,
   one JSON string per upstream literal, and note the transformation in
   the provenance README.

2. **Record provenance** in `spec/conformance/vectors/README.md`: source
   SDK, source path within that SDK, and the commit SHA you copied from.

3. **Write the spec** under `spec/conformance/<family>_spec.rb`. Load the
   vectors with `ConformanceVectors.load(...)` and assert whatever makes
   sense for the family. Prefer one example per vector so RSpec output
   identifies the specific vector that failed.

4. **Run the suite** and confirm either:
   - All seeded vectors pass, or
   - Failing vectors represent genuine latent bugs filed as follow-ups
     against the relevant A-cluster HLR in the 0.9.0 rollout plan
     (`.claude/plans/20260408-v090-compliance-rollout.md`).

   Vectors that can't run against the current API (e.g. BIP-143 sighash
   vectors that need non-FORKID hashTypes) should be kept as vendored
   files plus a spec file that uses `skip` with a clear cross-reference.

## Syncing from upstream

The reference SDK clones live under language-appropriate locations:
`/opt/go/go-sdk`, `/opt/python/py-sdk`, and `/opt/js/ts-stack` (the TS
SDK is at `packages/sdk/` inside the `bsv-blockchain/ts-stack` monorepo;
`/opt/js/ts-stack` is the clone root for `git pull`). To refresh a
vector file from the Go reference:

```sh
git -C /opt/go/go-sdk pull
diff -q /opt/go/go-sdk/primitives/ec/testdata/BRC42.private.vectors.json \
        spec/conformance/vectors/BRC42.private.vectors.json
# If different, copy the new version and update README.md's commit SHA column.
cp /opt/go/go-sdk/primitives/ec/testdata/BRC42.private.vectors.json \
   spec/conformance/vectors/BRC42.private.vectors.json
```

Run the spec after each file update. A vector change that breaks the spec
usually means either a real semantics change upstream (investigate whether
BSV agrees) or an intentional vector regeneration (rare — double-check).

Submodules are deliberately avoided. They complicate CI, make historical
reproducibility fragile, and don't save meaningful effort for a regression
test corpus that changes a few times a year at most.

## Why static snapshots, not submodules?

The alternative — pulling reference SDKs in as git submodules — was
considered and rejected because:

- Conformance vectors change very rarely, so the "live sync" benefit is
  marginal.
- Submodules in CI add setup cost and an extra failure mode.
- Byte-identical static copies make `diff` against the provenance-listed
  upstream commit immediately meaningful. You can tell at a glance whether
  the file has been touched.
- The sync procedure is simple enough that documenting it here is cheaper
  than automating it.
