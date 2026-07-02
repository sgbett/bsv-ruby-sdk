# Contributing

Bug reports, feature requests, and pull requests are welcome. Read this before opening anything — particularly the docs section, which catches most first-time contributors.

## Code contributions

### Branching and commits

- Branch from `master` using the convention `feat/<issue>-<slug>` (e.g. `feat/123-add-schnorr-verify`).
- All changes land via PR — no direct push to `master`.
- Merge commits, not squash.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `feat:` / `fix:` / `docs:` / `refactor:` / `test:` / `chore:`. Use `!` for breaking changes (e.g. `fix!:`). Scope is optional.

### Ruby version

- Development: Ruby 3.4.2 (`.ruby-version`).
- Gem floor: `>= 3.3`. Do not use Ruby 3.4+ features (e.g. the `it` block parameter) — the gem must run on 3.3.
- CI matrix: 3.3, 3.4, 4.0.

### Running checks

```bash
bundle exec rubocop          # lint
bundle exec rake             # full test suite (all gems)
bundle exec rake spec:sdk    # SDK specs only
```

Both must be green before opening a PR.

## Docs contributions

### Where files live

Hand-authored pages go in `docs/<section>/<slug>.md`. The `docs/reference/api/` directory is YARD-generated — do not hand-edit files there.

### Required frontmatter

Every hand-authored `.md` file **must** have frontmatter:

```yaml
---
title: Page Title
nav_order: 5
parent: SDK          # or nav_exclude: true for hidden pages
---
```

The `docs/_config.yml` `defaults:` block **replaces** the just-the-docs theme defaults rather than merging with them (this is Jekyll's behaviour for user-defined `defaults:`). The config restores `layout: default` explicitly, but if you omit frontmatter entirely, Jekyll falls back to no layout — rendering bare unstyled HTML with no nav. `rake docs:lint` catches this, but the error message is not obvious.

### Callout syntax

Use Kramdown block IAL, **not** GFM admonitions. The wrong form is a soft failure — it renders as a plain blockquote without the callout styling, and nothing in `rake docs:lint` catches it today. Check your preview locally with `rake docs:serve` when adding callouts.

**Wrong (GFM / GitHub-flavoured Markdown):**

```markdown
> [!NOTE]
> This is a note.
```

**Right (Kramdown block IAL):**

```markdown
> This is a note.
{: .note }
```

Available callout classes: `note` (blue), `important` (yellow), `warning` (red).

### Local preview and CI parity

```bash
bundle exec rake docs:serve      # local Jekyll server
bundle exec rake docs:lint       # frontmatter + BSV:: symbol / kwarg / Ruby-syntax checks (matches CI)
bundle exec rake docs:proofread  # link checker (matches CI)
```

Do not commit `_site/` or `.jekyll-cache/` — both are in `docs/.gitignore`.

### Docs check expectation

If your PR changes a public class, method signature, or keyword argument under `BSV::`, update the corresponding `docs/sdk/*.md` page, or note `docs/N/A` in the PR body explaining why no docs update was needed. CI's symbol-existence linter (#892) catches drift in class/method names; prose drift is a human concern.

## Issue and PR conventions

### HLR issues

Substantial features use an HLR (High-Level Requirement) issue to capture the *why* before implementation:

- Label: `project:hlr`
- Title prefix: `[HLR]` (e.g. `[HLR] Implement incremental analysis`)
- Body: problem, approach, acceptance criteria, context

Sub-issues are linked via GitHub's parent-child UI or GraphQL `addSubIssue`. Sub-issue closure does **not** propagate from parent to child — give each sub-issue its own `Closes #N` reference in the PR body.

### ADRs

ADRs are reserved for decisions that need explanation and will outlast the PR conversation. HLR + plan + PR is usually sufficient; don't reach for an ADR reflexively.

## Release flow

Releases use the `/release <key>` skill, which guides you through version bump, changelog entry, tagging, gem build, and RubyGems push.

Tag conventions:

| Gem | Tag prefix | Example |
|-----|-----------|---------|
| `bsv-sdk` | `v` | `v0.10.0` |
| `bsv-attest` | `attest-v` | `attest-v0.1.0` |

PRs do not bump versions or add CHANGELOG entries — both are handled at release time.

## Reporting security issues

See [SECURITY.md](SECURITY.md) for the full policy.

The short version: use [GitHub's private vulnerability reporting](https://github.com/sgbett/bsv-ruby-sdk/security) — the **Report a vulnerability** button on the Security tab. This opens a private draft advisory that only maintainers can see. Do **not** open a public issue or PR for anything security-relevant; the GHSA private-fork workflow keeps the fix embargoed until a patched release is ready.
