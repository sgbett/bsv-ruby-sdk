# Project Manager Memory

## Repository

- **Owner/repo:** `sgbett/bsv-ruby-sdk`
- **Default branch:** `master`
- **Gem name:** `bsv-sdk`, namespace `BSV::`

## Labels in Use

- `project:hlr` — HLR issues
- `task` — implementation tasks
- `testing` — test infrastructure
- `enhancement` — feature requests / design discussions
- Layer labels: `layer:primitives`, `layer:script`, `layer:transaction`, `layer:wallet`, `layer:network`, `layer:attest`
- Status: `status:done`, `in-progress`

## Issue Conventions

- HLR titles prefixed with `[HLR] `
- Sub-issues linked via GraphQL `addSubIssue` mutation
- `gh issue view N --json id` returns the `id` field needed for GraphQL node IDs
- Use `--body-file /tmp/filename.md` for multi-line issue bodies (avoid heredocs)

## Reference SDKs

- Located at `/opt/ruby/bsv-reference-sdks/` (go-sdk, ts-sdk, py-sdk)
- TS SDK is the most complete reference; Go SDK has gaps (e.g. "not-implemented" for random change distribution)

## HLR #156 — Benford's Law Change Distribution (SHIPPED)

- PR: #181, sub-issues: #177, #178 (both closed)
- Related standalone: #179 (remainder target discussion), #180 (default distribution discussion)
- Key decisions: default `:equal` (matching TS SDK), remainder to last tx output (matching TS SDK), `rng:` param for testability
- 1710 specs pass, RuboCop clean at time of ship

## Verification Patterns

- Always run `bundle exec rake` (not just specific spec files) to catch regressions
- For statistical specs: verify chi-squared critical values, sample sizes, and seed diversity
- Check `@outputs.last` vs change_outputs.last distinction -- remainder target matters
