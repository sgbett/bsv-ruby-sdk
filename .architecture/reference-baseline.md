# Reference SDK Baselines

Records the commit each reference SDK was at when the Ruby SDK reached a given version.
Use this to scope divergence analysis — only changes *after* the baseline commit are new.

## bsv-sdk v0.1.0 (2026-02-14)

Baseline established at initial release. Development drew from all three SDKs
dynamically (no single pinned commit during development).

| SDK | Version | Commit | Description |
|-----|---------|--------|-------------|
| [go-sdk](https://github.com/bsv-blockchain/go-sdk) | v1.2.18 | `725db51` | Fix BIP276 decoding, AuthFetch data race, and add NUM2BIN tests (#288) |
| [ts-sdk](https://github.com/bsv-blockchain/ts-sdk) | v2.0.0 | `8acc706` | Merge pull request #481 — fix/optimizations |
| [py-sdk](https://github.com/bsv-blockchain/py-sdk) | v1.0.10 | `f505ea5` | Added OP_CAT template example and script (#137) |

### How to use

To see what changed in a reference SDK since this baseline:

```bash
git -C /opt/ruby/bsv-reference-sdks/go-sdk log --oneline 725db51..HEAD
git -C /opt/ruby/bsv-reference-sdks/ts-sdk log --oneline 8acc706..HEAD
git -C /opt/ruby/bsv-reference-sdks/py-sdk log --oneline f505ea5..HEAD
```

Update this file when cutting a new Ruby SDK release, recording the new baseline commits.
