# Plan: `/release` Skill for Gem Releases

**Issue:** #304
**Previous release pain:** Missing v0.5.0 tag, building from wrong directory, manual changelog

---

## Gem Registry

| Key | Gem name | Version file | Tag prefix | Downstream deps |
|-----|----------|-------------|------------|-----------------|
| `sdk` | `bsv-sdk` | `gem/bsv-sdk/lib/bsv/version.rb` | `v` | `bsv-wallet`, `bsv-attest` |
| `wallet` | `bsv-wallet` | `gem/bsv-wallet/lib/bsv/wallet_interface/version.rb` | `wallet-v` | `bsv-wallet-postgres` |
| `wallet-postgres` | `bsv-wallet-postgres` | `gem/bsv-wallet-postgres/lib/bsv/wallet_postgres/version.rb` | `wallet-postgres-v` | none |
| `attest` | `bsv-attest` | `gem/bsv-attest/lib/bsv/attest/version.rb` | `attest-v` | none |

Dependency chain: `bsv-sdk → bsv-wallet → bsv-wallet-postgres`

---

## Release Flow (16 steps)

### Step 0: Hard refusal
Refuse if user requests releasing multiple gems at once. One at a time only.

### Step 1: Pre-flight checks
- Dirty working tree → abort
- Not on master → abort
- Local master behind origin → abort

### Step 2: Select gem
From `$ARGUMENTS` or prompt user. Show current versions.

### Step 3: Already-released checks
- Version already tagged locally → abort
- Version already on RubyGems (`gem search --remote --exact`) → abort

### Step 4: Choose version bump
- Gather commits since last tag scoped to `gem/<dir>/`
- Suggest bump based on conventional commits (`feat!:` → major, `feat:` → minor, else → patch)
- User confirms or overrides

### Step 5: Downstream dependency check
Only for gems with downstream dependents (sdk, wallet).

**Part A — Dependency floor check:**
Read downstream gemspec, check `add_dependency` floor version. Soft warning if floor < new version.

**Part B — Interface compliance check (wallet only):**
- Extract `def method_name` from `StorageAdapter` (methods raising `NotImplementedError`)
- Extract `def method_name` from each downstream adapter (all `.rb` files in `lib/`)
- Report any gaps. Default to abort; user can override.

### Step 6: Generate changelog draft
- `git log <last_tag>..HEAD -- gem/<dir>/` grouped by conventional commit type
- Map to Keep a Changelog sections (Added, Fixed, Changed, Breaking, Security)
- British English throughout
- Display for user review/edit

### Step 7: Bump version.rb
Simple string replacement of `VERSION = 'x.y.z'` line.

### Step 8: Update CHANGELOG.md
Prepend new section after the header, before the first existing `## X.Y.Z` entry.

### Step 9: Commit
```
git add gem/<dir>/lib/.../version.rb gem/<dir>/CHANGELOG.md
git commit -m "chore: release <gem-name> v<version>"
```

### Step 10: Tag
`git tag <prefix><version>` using gem's prefix convention.

### Step 11: Push to master (with confirmation)
```
git push origin master
git push origin <tag>
```

### Step 12: Build gem
`cd gem/<dir> && gem build <name>.gemspec` (must build from inside gem directory).

### Step 13: Sanity check
Inspect `.gem` contents — verify `lib/`, `CHANGELOG.md`, `LICENSE` present, no unexpected files.

### Step 14: Prompt user to push to RubyGems
Skill cannot push — credentials are manual. Display the command and wait for confirmation.

### Step 15: Create GitHub release
```
gh release create <tag> --title "<gem-name> <version>" --notes "<changelog>" --target master
gh release upload <tag> gem/<dir>/<gem-name>-<version>.gem
```

### Step 16: Summary
Table with gem, version, tag, commit, RubyGems link, GitHub release link, next steps.

---

## Error Handling

**Hard aborts:** dirty tree, wrong branch, behind origin, already tagged, already on RubyGems, user declines confirmation.

**Soft warnings:** downstream floor not raised, interface compliance failure (default abort, overridable), sanity check anomalies, GitHub release creation failure.

**Recovery guidance:** at every abort, explain what state the release is in and how to continue or roll back.

---

## Rakefile Cleanup

Remove all four `Bundler::GemHelper.install_tasks` lines. The `/release` skill replaces the entire `release[remote]` workflow. Keep `rspec` and `docs:` tasks. Add comment directing to `/release`.

---

## CLAUDE.md Updates

- Update "Releasing Companion Gems" section to reference `/release` as canonical mechanism
- Document tag prefix conventions for all four gems
- Fix the `gem build` example in Commands section (currently references old path)

---

## Task Breakdown

1. **Create `.claude/commands/release.md`** — the skill file with full flow
2. **Clean up Rakefile** — remove unsafe `install_tasks`, add comment
3. **Update CLAUDE.md** — releasing docs, tag conventions, fix build example
4. **Manual verification** — dry-run `/release` to test the flow

---

## Risks

| Risk | Mitigation |
|------|-----------|
| `gem search --remote` slow/unavailable | Timeout + soft warning |
| `gh` CLI not authenticated | Check `gh auth status` in pre-flight |
| No previous tag for a gem (e.g. attest) | Use earliest commit touching `gem/<dir>/` |
| Interface check false positives (mixins) | Scan all `.rb` files in downstream `lib/` |
| New gems added to monorepo | Update gem registry in skill file |
