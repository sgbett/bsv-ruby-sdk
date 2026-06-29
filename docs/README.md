# BSV Ruby SDK — Documentation

This directory contains the documentation source for the BSV Ruby SDK, built with
[Jekyll](https://jekyllrb.com/) and the [just-the-docs](https://just-the-docs.com/) theme.

## Local development

Preview the site locally:

```bash
bundle exec rake docs:serve
```

The site is served at `http://localhost:4000/bsv-ruby-sdk/` with live-reload enabled.

### Testing redirect stubs locally

`jekyll-redirect-from` prepends `site.url + site.baseurl` to redirect targets,
so by default a local preview redirects you to the production GitHub Pages URL
(`https://sgbett.github.io/bsv-ruby-sdk/...`). To verify a redirect resolves
within localhost, override both at serve time:

```bash
cd docs && bundle exec jekyll serve --livereload \
  --url 'http://localhost:4000' --baseurl ''
```

Then load the old path (e.g. `http://localhost:4000/general/naming-conventions/`)
and confirm it redirects to the new path on the same host.

To build without serving:

```bash
bundle exec rake docs:build
```

To lint frontmatter across all hand-authored `.md` files:

```bash
bundle exec rake docs:lint
```

To regenerate the YARD API reference into `docs/reference/api/`:

```bash
bundle exec rake docs:generate
```

## Why `docs/Gemfile.lock` is committed

The SDK gem itself does **not** commit `Gemfile.lock` — standard practice for
libraries, where consumers resolve their own dependency tree.

The docs site is different: it is a **deployable application** (GitHub Pages).
Committing the lockfile ensures:

- CI produces byte-for-byte identical output to local development.
- A stale or yanked upstream release cannot silently break the deployed site.
- Renovate/Dependabot diffs are explicit and reviewable.

## No custom `_plugins/`

The site uses only built-in just-the-docs features and the
`jekyll-redirect-from` plugin (whitelisted on GitHub Pages). There are no
files under `_plugins/` — this keeps the build compatible with GitHub Pages
safe mode if ever needed.

To add redirect stubs, use the `redirect_to:` frontmatter key provided by
`jekyll-redirect-from`.

## File structure

```
docs/
  _config.yml              — Jekyll + just-the-docs configuration
  _sass/color_schemes/     — bsv-ruby brand palette (SCSS)
  index.md                 — Home page (nav_order: 1)
  guides/                  — How-to guides
  sdk/                     — SDK module reference (hand-authored)
  reference/               — Reference material
    api/                   — YARD output (auto-generated, git-ignored)
  overlays/                — Overlay services documentation
  network/                 — Network layer documentation
  testing/                 — Testing documentation
  general/                 — General documentation
  Gemfile                  — Jekyll gem dependencies
  Gemfile.lock             — Committed (deployable application policy)
```
