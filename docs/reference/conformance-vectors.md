---
title: Conformance Vectors
nav_order: 3
parent: Reference
---

# Cross-SDK conformance vectors

The Ruby SDK validates its behaviour against canonical test vectors from the
ts-stack conformance corpus. This keeps Ruby's output aligned with the rest of
the SDK family rather than just self-consistent.

Tracking issue: [sgbett/bsv-ruby-sdk#837](https://github.com/sgbett/bsv-ruby-sdk/issues/837)

## Layout

```
spec/
├── conformance/
│   ├── vectors/
│   │   ├── README.md               ← pointer to lock file + Ruby-local fixtures
│   │   └── SymmetricKey.vectors.json  ← Ruby-local (no canonical equivalent)
│   ├── brc42_key_derivation_spec.rb
│   ├── beef_spec.rb
│   ├── bump_spec.rb
│   ├── ecies_spec.rb
│   ├── sha256_spec.rb
│   ├── sighash_bip143_spec.rb
│   └── …
└── support/
    └── conformance_vectors.rb      ← loader (auto-required)
```

The loader provides:

- `ConformanceVectors.load(filename)` — reads from `spec/conformance/vectors/`; returns the parsed JSON as-is.
- `ConformanceVectors.load_rows(filename)` — for Bitcoin Core-style files that mix test rows with comment rows; returns only the test rows.
- `ConformanceVectors.canonical(id)` — loads a file from the canonical corpus at `tmp/conformance-vectors/conformance/vectors/`. Accepts a dot-separated path: `'sdk.keys.public-key'` resolves to `sdk/keys/public-key.json`. Fails with an actionable error if the cache is empty.
- `ConformanceVectors.each_canonical_vector(id) { |envelope, vector| }` — yields once per vector entry, skipping any marked `skip: true` (logs the skip reason).

Per-family parsing logic lives in each spec, not in the loader.

## Running

Conformance specs are part of the default test suite:

```sh
bin/conformance/sync                     # populate or verify the vector cache
bundle exec rake                         # everything (sync step not included — run manually first)
bundle exec rspec spec/conformance/      # conformance only
bundle exec rspec --tag conformance      # conformance (via tag)
```

In CI, a dedicated step runs `bin/conformance/sync` before the RSpec invocation (see
[CI wiring](#ci-wiring) below).

## Fetch flow

The canonical corpus is fetched from GitHub's anonymous codeload endpoint:

```
https://codeload.github.com/bsv-blockchain/ts-stack/tar.gz/{sha}
```

`bin/conformance/sync` downloads the tarball at the SHA recorded in
`.architecture/conformance.lock`, verifies the sha256 digest, and extracts
`conformance/` into `tmp/conformance-vectors/`. The cache directory is
gitignored.

### Why codeload, not the Actions artifact API

The ts-stack CI publishes a `conformance-vectors` GitHub Actions artifact on
every `main` push. We deliberately do **not** use that artifact as the primary
fetch path for two reasons:

1. **No authentication dependency.** The codeload URL is anonymous — fork CI
   and external contributors get a working setup with zero token configuration.
2. **No expiry.** GitHub Actions artifacts expire after 90 days. A SHA-pinned
   codeload URL is permanent.

The artifact API remains useful as a **discovery channel**: querying it reveals
the `head_sha` of the latest `main` run, which is the value to pass when
bumping the corpus revision. It is never on the critical fetch path.

### The lock file

`.architecture/conformance.lock` pins the exact corpus revision in use:

```yaml
# .architecture/conformance.lock
# Auto-managed by bin/conformance/sync — do not edit by hand.
upstream: bsv-blockchain/ts-stack
path: conformance/
sha: <40-char commit SHA>
fetched_at: <ISO date>
tarball_sha256: <sha256 of the downloaded tarball>
vectors_count: <number of vector files in the corpus>
vectors_total: <total number of individual test vectors>
```

| Field | Meaning |
|---|---|
| `upstream` | The GitHub repository the corpus originates from |
| `path` | The subdirectory extracted from the tarball |
| `sha` | 40-char commit SHA; the only valid form (no branch names) |
| `fetched_at` | ISO date the lock was last written |
| `tarball_sha256` | sha256 of the downloaded gzip tarball; used to detect upstream tampering on re-fetch |
| `vectors_count` | Number of JSON files extracted |
| `vectors_total` | Total individual vectors across all files (from `META.json`) |

## Bumping the corpus revision

To pull in a newer corpus:

1. **Discover the latest `main` SHA.** The artifact API is the easiest source:

   ```sh
   gh api -X GET /repos/bsv-blockchain/ts-stack/actions/artifacts \
     -q '.artifacts[] | select(.name == "conformance-vectors") | .workflow_run.head_sha' \
     | head -1
   ```

2. **Fetch and update the lock:**

   ```sh
   bin/conformance/sync <new-sha> --update
   ```

   This overwrites `.architecture/conformance.lock` with the new SHA and
   tarball digest.

3. **Run the conformance suite:**

   ```sh
   bundle exec rspec spec/conformance/
   ```

4. **Review any failures** (see [Handling a breaking corpus revision](#handling-a-breaking-corpus-revision)).

5. **Commit the lock file alongside any spec changes** in a single commit.

## Handling a breaking corpus revision

If a corpus bump breaks conformance specs, **investigate before acting**:

- **Real Ruby SDK bug** — a new vector exercises behaviour the Ruby SDK gets
  wrong. File an issue, do not silently update the lock.
- **Intentional vector regeneration upstream** — the upstream maintainers
  changed expected values (rare). Confirm via the upstream PR or changelog
  before bumping. If confirmed, bump and update the relevant specs.
- **Feature not implemented** — a new vector exercises a protocol feature the
  Ruby SDK does not implement (e.g. a wallet-tier BRC). Mark the spec example
  `skip 'reason'` with a cross-reference to an issue.

**Never silently update the lock to bypass a failing spec.** The lock file is a
correctness checkpoint, not a rubber stamp.

## CI wiring

The GitHub Actions workflow (`.github/workflows/ci.yml`) runs the sync step
before the RSpec invocation:

```yaml
- name: Cache conformance vectors
  uses: actions/cache@v4
  with:
    path: tmp/conformance-vectors
    key: conformance-${{ hashFiles('.architecture/conformance.lock') }}

- name: Sync conformance vectors
  run: bin/conformance/sync
```

The cache key is derived from the content of the lock file. A cache miss
triggers a full anonymous fetch from codeload; a hit reuses the cached tree
without a network round-trip. No `GH_TOKEN` is required.

`bin/conformance/sync` (no SHA argument) reads the lock SHA and is a no-op
if the cache already matches. It re-fetches if the cache is absent or was
populated from a different SHA.

## What's NOT in the canonical corpus

Some Ruby SDK fixtures have no canonical upstream equivalent. These live in
`spec/conformance/vectors/` and are explicitly noted in
`spec/conformance/vectors/README.md`:

| File / constant | Why it's Ruby-local |
|---|---|
| `SymmetricKey.vectors.json` | go-sdk base64 AES-256-GCM round-trip vectors. The canonical corpus has NIST AES vectors (`sdk/crypto/aes.json`) but with different inputs (hex-encoded FIPS-197 test cases). No upstream equivalent for our base64 GCM corpus. |
| `BEEF_V2_SET_HEX` (inline in `beef_spec.rb`) | go-sdk `BEEFSet` constant — V2 BEEF, 3 BUMPs, 3 transactions. See [issue #849](https://github.com/sgbett/bsv-ruby-sdk/issues/849). |
| `BEEF_V1_B64` (inline in `beef_spec.rb`) | go-sdk `BEEF` constant — V1 base64, 9 transactions. See [issue #849](https://github.com/sgbett/bsv-ruby-sdk/issues/849). |
| `BEEF_ISSUE96_HEX` (inline in `beef_spec.rb`) | go-sdk `Issue96BeefHex` — V1 BEEF regression, 5 BUMPs, 14 transactions. See [issue #849](https://github.com/sgbett/bsv-ruby-sdk/issues/849). |
| Legacy sighash (retired) | Pre-FORKID sighash has no valid meaning on BSV. Retired per Protocol Philosophy ("recognise everything, construct only what's valid"). See `CLAUDE.md`. |

## Adding a new vector family

1. **Pick a domain from the canonical corpus.** Browse
   `tmp/conformance-vectors/conformance/vectors/` after running
   `bin/conformance/sync`. Each subdirectory (`sdk/`, `regressions/`, etc.)
   contains JSON files in the standard envelope format.

2. **Write the spec** under `spec/conformance/<family>_spec.rb`. Load vectors
   with `ConformanceVectors.each_canonical_vector('sdk.domain.filename')` and
   assert whatever makes sense. Prefer one example per vector so RSpec output
   identifies the specific vector that failed.

3. **Run the suite** and confirm either:
   - All canonical vectors pass, or
   - Failing vectors represent genuine latent bugs filed as follow-ups.

   Vectors that exercise features not yet implemented should use `skip` with a
   clear cross-reference.

4. No vendoring. The canonical corpus is never copied into `spec/conformance/vectors/`.
