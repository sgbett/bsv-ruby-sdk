# Release a Gem

Guided release workflow for a single gem from this monorepo. Releases one gem per invocation.

**Gem key:** `$ARGUMENTS`

---

## Gem Registry

| Key | Gem name | Version file | Tag prefix | Gemspec path | Downstream deps |
|-----|----------|-------------|------------|--------------|-----------------|
| `sdk` | `bsv-sdk` | `gem/bsv-sdk/lib/bsv/version.rb` | `v` | `gem/bsv-sdk/bsv-sdk.gemspec` | `bsv-wallet`, `bsv-attest` |
| `wallet` | `bsv-wallet` | `gem/bsv-wallet/lib/bsv/wallet_interface/version.rb` | `wallet-v` | `gem/bsv-wallet/bsv-wallet.gemspec` | `bsv-wallet-postgres` |
| `wallet-postgres` | `bsv-wallet-postgres` | `gem/bsv-wallet-postgres/lib/bsv/wallet_postgres/version.rb` | `wallet-postgres-v` | `gem/bsv-wallet-postgres/bsv-wallet-postgres.gemspec` | none |
| `attest` | `bsv-attest` | `gem/bsv-attest/lib/bsv/attest/version.rb` | `attest-v` | `gem/bsv-attest/bsv-attest.gemspec` | none |

Version constants:
- `sdk` → `BSV::VERSION`
- `wallet` → `BSV::WalletInterface::VERSION`
- `wallet-postgres` → `BSV::WalletPostgres::VERSION`
- `attest` → `BSV::Attest::VERSION`

---

## Step 0: Hard Refusal

If `$ARGUMENTS` contains a space or comma (multiple keys), **stop immediately**:

> This skill releases one gem at a time. You provided multiple gem keys: `$ARGUMENTS`.
> Run `/release <key>` once per gem, in dependency order if releasing multiple gems.

Do not proceed past this step if multiple keys are detected.

---

## Step 1: Select Gem

If `$ARGUMENTS` is empty or not one of `sdk`, `wallet`, `wallet-postgres`, `attest`, prompt:

```
Which gem do you want to release?

  sdk              bsv-sdk               currently 0.x.x
  wallet           bsv-wallet            currently 0.x.x
  wallet-postgres  bsv-wallet-postgres   currently 0.x.x
  attest           bsv-attest            currently 0.x.x

Enter one of: sdk, wallet, wallet-postgres, attest
```

Read current versions by running:
```bash
grep "VERSION = " gem/bsv-sdk/lib/bsv/version.rb
grep "VERSION = " gem/bsv-wallet/lib/bsv/wallet_interface/version.rb
grep "VERSION = " gem/bsv-wallet-postgres/lib/bsv/wallet_postgres/version.rb
grep "VERSION = " gem/bsv-attest/lib/bsv/attest/version.rb
```

Once a valid gem key is confirmed, set these variables (conceptually) for the rest of the steps:
- `GEM_KEY` — the key (e.g. `sdk`)
- `GEM_NAME` — the gem name (e.g. `bsv-sdk`)
- `GEM_DIR` — the gem subdirectory (e.g. `gem/bsv-sdk`)
- `VERSION_FILE` — path to version.rb
- `TAG_PREFIX` — the tag prefix
- `GEMSPEC_PATH` — path to the gemspec
- `CURRENT_VERSION` — the version string extracted from version.rb

---

## Step 2: Pre-flight Checks

Run all four checks. Abort on any failure.

**Check 1 — gh CLI authenticated:**
```bash
gh auth status
```
Abort if not authenticated:
> Pre-flight failed: `gh` CLI is not authenticated. Run `gh auth login` and retry.

**Check 2 — Clean working tree:**
```bash
git status --porcelain
```
Abort if any output:
> Pre-flight failed: working tree is dirty. Commit or stash your changes before releasing.
>
> Recovery: no changes have been made. Clean the tree and run `/release $GEM_KEY` again.

**Check 3 — On master branch:**
```bash
git branch --show-current
```
Abort if not `master`:
> Pre-flight failed: you are on branch `<branch>`, not `master`. Switch to master before releasing.
>
> Recovery: no changes have been made. Run `git checkout master` and retry.

**Check 4 — Local master up to date with origin:**
```bash
git fetch origin master
git status -uno
```
Abort if behind:
> Pre-flight failed: local master is behind origin/master. Run `git pull` before releasing.
>
> Recovery: no changes have been made. Run `git pull` and retry.

Display: "Pre-flight checks passed."

---

## Step 3: Already-Released Checks

**Check 1 — Tag does not already exist:**
```bash
git tag | grep "^${TAG_PREFIX}${CURRENT_VERSION}$"
```
Abort if tag exists:
> Already-released check failed: tag `${TAG_PREFIX}${CURRENT_VERSION}` already exists.
>
> This version has already been tagged. If you need to release again, bump the version first.
>
> Recovery: no changes have been made.

**Check 2 — Version not already on RubyGems** (soft check — warn on timeout or unavailability):
```bash
gem search --remote --exact "$GEM_NAME" 2>&1
```
If output contains `$CURRENT_VERSION`, abort:
> Already-released check failed: `$GEM_NAME $CURRENT_VERSION` is already published on RubyGems.
>
> Bump the version in `$VERSION_FILE` to release a new version.
>
> Recovery: no changes have been made.

If the command times out or fails, warn and continue:
> Warning: could not check RubyGems availability (network issue or gem not yet published). Continuing with caution.

Display: "Already-released checks passed. Current version `$CURRENT_VERSION` is not yet released."

---

## Step 4: Determine Last Tag

Find the most recent tag for this gem:

```bash
git tag | grep "^${TAG_PREFIX}" | sort -V | tail -1
```

If no tag found, this is a first release. Fall back to the earliest commit that touches `$GEM_DIR`:
```bash
git log --oneline --reverse -- "$GEM_DIR/" | head -1
```

Store as `LAST_TAG` (or `FIRST_COMMIT_SHA` if no tag).

Display: "Collecting commits since `$LAST_TAG` (or since first commit for `$GEM_DIR`) ..."

---

## Step 5: Suggest Version Bump

Gather conventional commits scoped to `$GEM_DIR` since the last tag:

```bash
# If LAST_TAG exists:
git log ${LAST_TAG}..HEAD --oneline -- "$GEM_DIR/"

# If no tag (first release), use FIRST_COMMIT_SHA..HEAD:
git log ${FIRST_COMMIT_SHA}..HEAD --oneline -- "$GEM_DIR/"
```

Apply bump rules (applied in order, first match wins):
- Any commit matching `feat!:` or `fix!:` or `!:` → **MAJOR**
- Any commit matching `feat:` → **MINOR**
- Otherwise → **PATCH**

Show suggested bump with reasoning:

```
Version bump suggestion for $GEM_NAME:

  Current version:  $CURRENT_VERSION
  Suggested bump:   PATCH  →  x.y.z+1
  Reason:           no feat: or breaking commits found

  Commits included:
    abc1234 fix: correct fee calculation rounding
    def5678 test: add edge case for empty script

Confirm version? [suggested] or enter a custom version:
```

Wait for user to confirm the suggested version or provide a custom one. Store as `NEW_VERSION`.

---

## Step 6: Downstream Dependency Checks

Only run for gems with downstream dependents (`sdk` and `wallet`).

Skip this step entirely for `wallet-postgres` and `attest`.

### Part A — Dependency Floor Check

For **sdk** — check `bsv-wallet` and `bsv-attest` floor versions:
```bash
grep "bsv-sdk" gem/bsv-wallet/bsv-wallet.gemspec
grep "bsv-sdk" gem/bsv-attest/bsv-attest.gemspec
```

For **wallet** — check `bsv-wallet-postgres` floor version:
```bash
grep "bsv-wallet" gem/bsv-wallet-postgres/bsv-wallet-postgres.gemspec
```

For each downstream, extract the floor version from the `add_dependency` line (e.g. `'>= 0.10.0'`).

If the floor is lower than `$NEW_VERSION`, warn:
```
Warning: bsv-wallet's floor on bsv-sdk is '>= 0.10.0', which is below the new version $NEW_VERSION.
Consider raising the floor in gem/bsv-wallet/bsv-wallet.gemspec before releasing $GEM_NAME $NEW_VERSION.
```

This is a soft warning — ask the user whether to continue or pause to raise the floor first.

### Part B — Interface Compliance Check (wallet only)

Only for `wallet`. Skip for all other gems.

Extract abstract method names from `StorageAdapter`:
```bash
grep -n "def " gem/bsv-wallet/lib/bsv/wallet_interface/storage_adapter.rb | grep -v "#"
```

Find all concrete adapter implementations (scan all `.rb` files under downstream `lib/`):
```bash
grep -rn "def " gem/bsv-wallet-postgres/lib/ | grep -v "#"
```

Compare method names. Any method defined in `StorageAdapter` that is missing from all downstream adapter files is a compliance gap.

If gaps are found:
```
Interface compliance warning: the following StorageAdapter methods are not implemented in bsv-wallet-postgres:

  - method_name_1
  - method_name_2

This may indicate the postgres adapter is out of date.
Abort to fix before releasing? [Y/n]
```

Default is abort. User can override by typing `n`.

---

## Step 7: Generate Changelog Draft

Gather commits for the changelog:

```bash
# If LAST_TAG exists:
git log ${LAST_TAG}..HEAD --oneline -- "$GEM_DIR/"

# If no tag:
git log ${FIRST_COMMIT_SHA}..HEAD --oneline -- "$GEM_DIR/"
```

Group by conventional commit type and map to Keep a Changelog sections:
- `feat:` / `feat!:` → **Added** (breaking: also **Breaking Changes**)
- `fix:` → **Fixed**
- `refactor:` → **Changed**
- `perf:` → **Changed**
- `docs:` → omit (internal)
- `test:` → omit (internal)
- `chore:` / `build:` / `ci:` → omit unless it affects users (use judgement)
- `security:` → **Security**

Format as Keep a Changelog section (British English):

```markdown
## $NEW_VERSION — YYYY-MM-DD

### Added
- Description of feat commit

### Fixed
- Description of fix commit

### Changed
- Description of refactor/perf commit
```

Display the draft and prompt:
```
Changelog draft for $GEM_NAME $NEW_VERSION (shown above).
Edit if needed, then confirm to proceed. [confirm / paste edited version]
```

Store the confirmed changelog section as `CHANGELOG_ENTRY`.

---

## Step 8: Bump Version File

Show what will change:
```
Will update $VERSION_FILE:
  Before: VERSION = '$CURRENT_VERSION'
  After:  VERSION = '$NEW_VERSION'

Confirm? [y/N]
```

On confirmation, edit the version file — replace the `VERSION = '...'` line with the new version. Use the Edit tool (exact string replacement).

---

## Step 9: Update CHANGELOG.md

The changelog lives at `$GEM_DIR/CHANGELOG.md`.

Read the file. Find the line after the top header (e.g. `# Changelog`) and before the first existing `## x.y.z` entry. Insert `$CHANGELOG_ENTRY` there, followed by a blank line.

Show the diff before writing:
```
Will prepend to $GEM_DIR/CHANGELOG.md:

$CHANGELOG_ENTRY

Confirm? [y/N]
```

On confirmation, update the file.

---

## Step 10: Commit

Show the staged diff:
```bash
git diff HEAD $GEM_DIR/lib $GEM_DIR/CHANGELOG.md
```

Wait for confirmation, then commit:
```bash
git add "$VERSION_FILE" "$GEM_DIR/CHANGELOG.md"
git commit -m "chore: release $GEM_NAME v$NEW_VERSION"
```

Display the resulting commit hash.

Recovery guidance if this step fails:
> Commit failed. Your version file and changelog have been modified but not committed.
> To roll back: `git checkout -- $VERSION_FILE $GEM_DIR/CHANGELOG.md`
> To retry: fix the issue and re-run `/release $GEM_KEY`.

---

## Step 11: Create Tag

```
Will create tag: ${TAG_PREFIX}${NEW_VERSION}

Confirm? [y/N]
```

On confirmation:
```bash
git tag "${TAG_PREFIX}${NEW_VERSION}"
```

Recovery guidance if this step fails:
> Tag creation failed. The release commit exists but no tag has been created.
> To tag manually: `git tag ${TAG_PREFIX}${NEW_VERSION}`
> To roll back entirely: `git reset HEAD~1` (unstaged), then `git checkout -- $VERSION_FILE $GEM_DIR/CHANGELOG.md`

---

## Step 12: Push to Origin

**This step requires explicit user approval.** Pushing is irreversible without a force-push.

```
Ready to push to origin/master. This will:

  git push origin master
  git push origin ${TAG_PREFIX}${NEW_VERSION}

After pushing, the release commit and tag will be public.
Type YES to push, or anything else to stop here.
```

Only proceed if the user types `YES` (case-sensitive).

On confirmation:
```bash
git push origin master
git push origin "${TAG_PREFIX}${NEW_VERSION}"
```

Recovery guidance if the user declines or push fails:
> Push skipped (or failed). The release commit and tag exist locally but have not been pushed.
>
> To push manually:
>   git push origin master
>   git push origin ${TAG_PREFIX}${NEW_VERSION}
>
> To roll back locally:
>   git tag -d ${TAG_PREFIX}${NEW_VERSION}
>   git reset HEAD~1

---

## Step 13: Build the Gem

The gemspec uses `Dir.chdir(__dir__)` for file globbing, so build must run
from inside the gem directory. Use `--output` to place the `.gem` file at a
known location relative to the repo root:

```bash
cd $GEM_DIR && gem build $GEM_NAME.gemspec --output $GEM_NAME-$NEW_VERSION.gem && cd -
mv $GEM_DIR/$GEM_NAME-$NEW_VERSION.gem ./$GEM_NAME-$NEW_VERSION.gem 2>/dev/null || true
```

The gem file will be at `./$GEM_NAME-$NEW_VERSION.gem` (repo root).

**Sanity check** — inspect the `.gem` contents:
```bash
tar -tzf $GEM_NAME-$NEW_VERSION.gem
```

Verify:
- `lib/` directory is present
- `CHANGELOG.md` is present
- `LICENSE` is present
- No unexpected files (e.g. `.env`, `spec/`, `tmp/`)

If anything looks wrong, warn the user and ask whether to continue or abort.

---

## Step 14: Prompt User to Push to RubyGems

The skill cannot push to RubyGems — credentials are yours to control.

Display:
```
The gem has been built at:

  $GEM_NAME-$NEW_VERSION.gem

To publish to RubyGems, run this command yourself:

  gem push $GEM_NAME-$NEW_VERSION.gem

This requires your RubyGems API key (run `gem signin` if not already authenticated).

Confirm once you have pushed (or type 'skip' to skip RubyGems and continue to GitHub release):
```

Wait for the user to confirm.

---

## Step 15: Create GitHub Release

```bash
gh release create "${TAG_PREFIX}${NEW_VERSION}" \
  --title "$GEM_NAME $NEW_VERSION" \
  --notes "$CHANGELOG_ENTRY" \
  --target master

gh release upload "${TAG_PREFIX}${NEW_VERSION}" \
  "$GEM_NAME-$NEW_VERSION.gem"
```

Recovery guidance if this fails:
> GitHub release creation failed. The gem has been pushed to RubyGems (if you confirmed that step).
> To create the release manually:
>   gh release create ${TAG_PREFIX}${NEW_VERSION} --title "$GEM_NAME $NEW_VERSION" --notes "..."
>   gh release upload ${TAG_PREFIX}${NEW_VERSION} $GEM_NAME-$NEW_VERSION.gem

---

## Step 16: Summary

Display a summary table:

```
Release complete!

  Gem:             $GEM_NAME
  Version:         $NEW_VERSION
  Tag:             ${TAG_PREFIX}${NEW_VERSION}
  Commit:          <sha>
  RubyGems:        https://rubygems.org/gems/$GEM_NAME/versions/$NEW_VERSION
  GitHub release:  https://github.com/sgbett/bsv-ruby-sdk/releases/tag/${TAG_PREFIX}${NEW_VERSION}

Next steps:
  - If you released sdk or wallet, check whether downstream gems need a matching release
  - Update any dependent gemspec floors if you raised a compatibility requirement
  - Announce the release in the appropriate channels
```

---

## Abort Recovery Quick Reference

| Step failed | State | Recovery |
|-------------|-------|----------|
| Pre-flight | Nothing changed | Fix issue, run `/release $GEM_KEY` again |
| Already-released | Nothing changed | Bump version, run `/release $GEM_KEY` again |
| Downstream checks | Nothing changed | Fix gaps or override, rerun |
| Version bump / changelog | Files modified, not committed | `git checkout -- $VERSION_FILE $GEM_DIR/CHANGELOG.md` |
| Commit | Files modified, not committed | Fix issue and re-stage, or `git checkout --` to discard |
| Tag | Committed, not tagged | `git tag ${TAG_PREFIX}${NEW_VERSION}` manually |
| Push | Local only | `git push origin master && git push origin ${TAG_PREFIX}${NEW_VERSION}` |
| Build | Committed, tagged, pushed | `cd $GEM_DIR && gem build $GEM_NAME.gemspec && mv $GEM_NAME-$NEW_VERSION.gem ../..` |
| RubyGems push | Built, not on RubyGems | `gem push $GEM_NAME-$NEW_VERSION.gem` |
| GitHub release | On RubyGems, no GH release | `gh release create ...` manually |
