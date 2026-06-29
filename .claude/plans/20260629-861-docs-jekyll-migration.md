# Docs migration: MkDocs → Jekyll + `just-the-docs`, with `bsv-ruby` palette

Date: 2026-06-29
Status: Draft — pending HLR + approval to start

## Why

Upstream MkDocs is effectively abandoned and the original author has announced
plans for a "MkDocs 2.0" rewrite that intentionally breaks every existing
theme, plugin, and configuration. The `mkdocs-material` theme's author
(squidfunk) is independently moving energy to a new generator (Zensical), and
the MkDocs plugin ecosystem is bifurcating between a `ProperDocs` continuation
camp and a Zensical successor camp — see [ProperDocs discussion #33].

Rather than pick a Python-side faction, this migration moves the docs stack to
`Jekyll + just-the-docs`. This:

- Aligns the docs toolchain with the project's Ruby identity (Bundler, gems,
  no Python in CI).
- Removes our exposure to both transitions in one move.
- Establishes a brand-aligned palette (Bitcoin orange + ruby red + black +
  white) derived from this repo's existing GitHub social preview, so the docs
  look like a continuation of the artwork rather than a generic theme.
- Produces a palette artefact (`_sass/color_schemes/bsv-ruby.scss`) that
  `bsv-wallet` can copy verbatim when its docs come online.

[ProperDocs discussion #33]: https://github.com/orgs/ProperDocs/discussions/33

## Goal

`https://sgbett.github.io/bsv-ruby-sdk/` rebuilt on Jekyll, identical content,
all 32 hand-authored pages reachable through the existing 7-section nav,
existing redirects honoured, YARD API output still served at
`/reference/api/`, no Python in CI.

## Palette (extracted from the social preview)

Brightest-pixel sample from `bsv-ruby-sdk.png` (1280×640):

| Element        | Brand hex   | Docs-text variant (AA pass) | Notes |
|----------------|-------------|------------------------------|-------|
| Bitcoin orange | `#F68617`   | `#C26200`                    | Primary brand identity; full brand for non-text accents |
| Ruby red       | `#FD2A24`   | `#C8101A`                    | Vivid; full brand only for icons/dividers, darker for in-text |
| Pill black     | `#000000`   | `#0A0A0A`                    | Body ink (light mode); paper (dark mode) |
| Paper          | `#FFFFFF`   | —                            | Paper (light mode); body ink (dark mode) |

The SCSS file defines both pairs so the brand colour is recoverable for
imagery while in-text tokens default to the AA-passing variants.

## Workstreams

### 1. Palette artefact

Create `docs/_sass/color_schemes/bsv-ruby.scss` overriding the `just-the-docs`
variables: `$link-color`, `$btn-primary-color`, body ink, paper, border, code
background, search background. Define a dark scheme mirroring the social
preview (near-black surface with orange + ruby accents). Self-contained and
copyable into `bsv-wallet` later.

### 2. Jekyll skeleton

- `docs/Gemfile` (kept separate from the SDK root `Gemfile` so gem-dev deps
  stay clean): `jekyll`, `just-the-docs`, `jekyll-redirect-from`.
- `docs/_config.yml`: `theme: just-the-docs`, `color_scheme: bsv-ruby`,
  `search_enabled: true`, `mermaid.version: "11"`,
  `plugins: [jekyll-redirect-from]`, repo URL, site title/description,
  matching `url:` + `baseurl:` (currently `sgbett.github.io` + `/bsv-ruby-sdk`).
- `docs/.gitignore`: `_site/`, `.jekyll-cache/`.

### 3. Nav migration

Translate the explicit `nav:` block from `mkdocs.yml` (Home, Guides, SDK,
Overlay services, Network, Reference, Testing, General — **section names
preserved**) into per-file frontmatter:

```yaml
---
title: Page Title
parent: Section
nav_order: N
---
```

- 7 section landing pages get `has_children: true`.
- ~32 hand-authored files touched, mechanical edits. Likely scriptable in
  bulk by parsing the existing `mkdocs.yml` nav block.
- Index page gets `nav_order: 1` and no `parent:`.

### 4. Redirects

The three redirects from HLR #856 become Jekyll redirect stubs under the old
paths:

| Old path                                 | New path                                  |
|------------------------------------------|-------------------------------------------|
| `general/naming-conventions.md`          | `reference/naming-conventions.md`         |
| `guides/wtxid-dtxid.md`                  | `reference/wtxid-dtxid.md`                |
| `testing/conformance-vectors.md`         | `reference/conformance-vectors.md`        |

`jekyll-redirect-from` handles this with a frontmatter `redirect_to:` on each
stub file. Whitelisted on GitHub Pages, though we'll be building in CI anyway.

### 5. YARD integration

`rake docs:generate` continues writing to `docs/reference/api/` (the existing
location — sibling to hand-authored reference content per the documentation
strategy in `Rakefile`). No change to the rake task.

Add a `defaults:` block in `_config.yml` so `/reference/api/**` gets
`nav_exclude: true` (don't list every generated class page in the side nav)
but remains linkable from authored prose.

### 6. CI workflow rewrite

`.github/workflows/docs.yml`:

- Drop the `actions/setup-python` step and `pip install -r docs/requirements.txt`.
- Drop `mkdocs gh-deploy`.
- Keep the YARD generation step (`bundle exec rake docs:generate`).
- Add `bundle install --gemfile=docs/Gemfile` + `bundle exec jekyll build
  --source docs --destination _site`.
- Switch to the modern GitHub Pages deploy chain:
  `actions/configure-pages` → `actions/upload-pages-artifact` →
  `actions/deploy-pages`. Project-scoped permissions, no force-push to
  `gh-pages` branch.

### 7. Mermaid

`mermaid:` block in `_config.yml` (`just-the-docs` has built-in support since
0.5). Verify with one diagram in the new theme as part of the PR.

### 8. Decommission

- Delete `mkdocs.yml`.
- Delete `docs/requirements.txt`.
- Remove `mkdocs build` / `mkdocs serve` references from `README.md` and any
  contributor docs.

## Out of scope

- **bsv-wallet's migration.** Separate follow-up; reuses `bsv-ruby.scss` and
  the workflow shape.
- **Section renaming.** Current 7-section structure preserved. The redundancy
  between `General` and `Reference` can be tidied in a separate content PR
  later — not mixed into an infra swap.
- **Content rewrites.** Infrastructure swap only.
- **Visual parity with mkdocs-material.** Accepted as a deliberate aesthetic
  shift to the brand-aligned palette.
- **PR preview deploys.** Deferred. Visual regression risk accepted on this
  pass; can be addressed in a follow-up if it bites.

## Risks

- **Visual regression.** Different theme, different look. Eyeballed on local
  `bundle exec jekyll serve` before merging.
- **Nav frontmatter drift.** Jekyll relies on per-file ordering; easy to
  forget on new pages. Mitigation: contributor note + a lint script that flags
  `.md` files under `docs/` missing required frontmatter.
- **Custom domain / canonical URLs.** Mis-set `url:` / `baseurl:` breaks
  asset URLs. Verify on first deploy by opening any page and checking that
  CSS/JS/images load.
- **`just-the-docs` lock-in.** Content is portable markdown; only nav
  frontmatter is theme-specific. Switching themes later would be a frontmatter
  rewrite, not a content rewrite. Acceptable.

## Workflow per project conventions

1. **HLR first.** Open issue
   `[HLR] Migrate docs from MkDocs to Jekyll + just-the-docs` with problem
   (MkDocs abandonment), approach (this plan), acceptance criteria.
2. **`/plan:tasks`** against the HLR — break into commits-per-task:
   - Palette artefact (`bsv-ruby.scss`).
   - Jekyll skeleton (`_config.yml`, `Gemfile`).
   - Nav frontmatter (bulk, scripted).
   - Redirect stubs.
   - YARD integration (`defaults:` block).
   - CI swap.
   - Decommission of MkDocs files.
3. **Branch from `master`, single PR, merge commit** (no squash).
4. **No defensive `mkdocs<2` pin needed** — this migration supersedes the
   time-bomb concern.

## Acceptance criteria

- `bundle exec jekyll build --source docs` succeeds locally.
- `bundle exec jekyll serve --source docs` renders the site; all 7 sections
  navigable; index page loads.
- All 32 hand-authored pages reachable from the nav.
- The 3 HLR #856 redirects resolve correctly (manual click-through).
- YARD API output at `/reference/api/` renders; links from authored
  reference pages to API pages work.
- Mermaid fenced blocks render as diagrams.
- Search returns results for known terms (e.g. "wtxid", "BEEF").
- Light/dark mode toggle works; palette matches the social preview.
- CI workflow runs in <2× the current docs.yml duration (sanity bound).
- No Python dependency in CI.
- `mkdocs.yml`, `docs/requirements.txt` removed; no stale references in
  `README.md` or contributor docs.
