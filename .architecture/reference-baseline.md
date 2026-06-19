# Reference SDK Baselines

Records the commit each reference SDK was at when the Ruby SDK reached a given version.
Use this to scope divergence analysis — only changes *after* the baseline commit are new.

## bsv-sdk v0.1.0 (2026-02-14)

Baseline established at initial release. Development drew from all three SDKs
dynamically (no single pinned commit during development).

| SDK | Version | Commit | Description |
|-----|---------|--------|-------------|
| [go-sdk](https://github.com/bsv-blockchain/go-sdk) | v1.2.18 | `725db51` | Fix BIP276 decoding, AuthFetch data race, and add NUM2BIN tests (#288) |
| [ts-stack](https://github.com/bsv-blockchain/ts-stack) (TS SDK at `packages/sdk/`) | v2.0.0 | `8acc706` | Merge pull request #481 — fix/optimizations (SHA from pre-monorepo ts-sdk, reachable via subtree import) |
| [py-sdk](https://github.com/bsv-blockchain/py-sdk) | v1.0.10 | `f505ea5` | Added OP_CAT template example and script (#137) |

### How to use

To see what changed in a reference SDK since this baseline:

```bash
git -C /opt/go/go-sdk log --oneline 725db51..HEAD
git -C /opt/js/ts-stack log --oneline 8acc706..HEAD -- packages/sdk
git -C /opt/python/py-sdk log --oneline f505ea5..HEAD
```

Note: the 8acc706 baseline commit predates the ts-stack monorepo move
(May 2026). The commit IS reachable from ts-stack because the standalone
ts-sdk repo was imported via `git subtree`, but the range walks the
whole monorepo's history. The `-- packages/sdk` path filter scopes the
log to the TS SDK changes, which is what the comparison wants. After
the next baseline update the ts-stack SHA will be the new anchor and
the path filter becomes redundant.

Update this file when cutting a new Ruby SDK release, recording the new baseline commits.
