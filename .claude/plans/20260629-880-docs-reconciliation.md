# [HLR] Docs reconciliation — accuracy, coverage, structure

GitHub issue: [#880](https://github.com/sgbett/bsv-ruby-sdk/issues/880)

Companion HLRs executed as part of this cleanup:
- [#877](https://github.com/sgbett/bsv-ruby-sdk/issues/877) — Rationalise docs nav structure (General vs Reference)
- [#878](https://github.com/sgbett/bsv-ruby-sdk/issues/878) — Create CONTRIBUTING.md

## Problem

The MkDocs→Jekyll migration (#861/#865 + follow-ups) settled the toolchain but didn't touch content. Three things need attention before the docs can be trusted by anyone landing from a search engine.

### 1. Accuracy — incorrect docs are worse than missing

A spot-check audit against the code on `master` surfaced material inaccuracies. The clearest examples:

- **`docs/sdk/network.md`** documents an API that doesn't exist. The whole "Broadcasting" section uses `BSV::Network::ARC.default`, `arc.broadcast(tx)`, `arc.status(txid)`, and `arc.broadcast_many(...)` returning `BroadcastResponse` / `BroadcastError`. None of those classes or methods exist. Actual API is `BSV::Network::Protocols::ARC.new(...)` then `.call(:broadcast, tx)`, returning a `ProtocolResponse`. The example would `NameError` on the first line if copy-pasted.
- **`docs/network/examples.md`** repeats the same invented facades (`BSV::Network::ARC.default`, `BSV::Network::WhatsOnChain.default`). Quick-start examples don't run.
- **`docs/overlays/registries.md`** shows `BSV::Registry::Client.new(wallet: nil)` and claims "read paths don't need a wallet" — true conceptually, but the example then calls `resolve_basket`, which falls through `resolver_for` to `@wallet.get_network` when no `resolver:` was injected and `NoMethodError`s on `nil`.
- **`README.md`** "Basic Usage" code block passes `prev_tx_id:` to `BSV::Transaction::TransactionInput.new` — actual keyword is `prev_wtxid:` (per the wtxid convention). Would `ArgumentError` on paste. The README is the first thing a new consumer reads, so its example matters disproportionately.

The audit was a spot-check, not exhaustive. Sub-issue 1 should sweep all hand-authored pages (and `README.md`) methodically before fixes are queued.

### 2. Coverage — major modules with no dedicated page

Top-level modules in `gem/bsv-sdk/lib/bsv-sdk.rb` versus what's documented:

| Module | Files | Doc status |
|---|---|---|
| `BSV::Auth` | 16 | None. `brc-103-wire.md` covers wire transport only, not Auth |
| `BSV::Identity` | 5 | None |
| `BSV::Registry` write paths | 4 | Mentioned in `ecosystem-clients.md`; write API undocumented |
| `BSV::Transaction::ChainTracker(s)` | 4 | Absent from `sdk/transaction.md` |
| `BSV::Transaction::FeeModel(s)` | 3 | Absent |
| `BSV::Transaction::MerklePath` | 1 | Three passing mentions; API undocumented |
| `BSV::Script::PushDropTemplate` | 1 | Only referenced from `registries.md`; not in `sdk/script.md` |
| `BSV::Primitives::Schnorr` | 1 | Not mentioned |
| `BSV::Primitives::KeyShares` | 1 | Not mentioned |

Auth and Identity are the biggest gaps — they're user-facing surfaces that consumers will want to land on directly from a search.

### 3. Structure — finish #877 and #878

Two existing HLRs (#877, #878) already scope the structural cleanup. This parent HLR runs them alongside the accuracy + coverage tracks so the whole content pass lands as one coherent set of PRs rather than three threads of work touching adjacent files.

## Approach

Five sub-issues. Sub-issue 1 (accuracy sweep) lands first so nothing downstream is built on a quietly-broken example. The others parallelise.

### Sub-issue 1 — Accuracy sweep + fixes (new)

Walk every hand-authored `.md` under `docs/` (excluding `_site/`, `reference/api/`, and existing redirect stubs) **and the repo-root `README.md`** — verify class paths, method names, and signatures against the code.

Known fixes (the floor, not the ceiling):

- `README.md` — `prev_tx_id:` → `prev_wtxid:` in Basic Usage; verify the rest of the snippet end-to-end
- `docs/sdk/network.md` — broadcasting, batch, status, callbacks
- `docs/network/examples.md` — quick-start + provider examples
- `docs/overlays/registries.md` — the `Client.new(wallet: nil)` example

**Acceptance:** every code block in `docs/**.md` and `README.md` either executes cleanly against the current SDK or is explicitly marked as illustrative pseudo-code. Reviewer reproduces a sample manually via IRB.

### Sub-issue 2 — New pages: Auth + Identity (new)

- `docs/sdk/auth.md` — `AuthFetch` (BRC-104 client with 402 retry), `Peer` / `PeerSession` (BRC-31 mutual auth), `Certificate` / `MasterCertificate` (BRC-52), `AuthMiddleware`. Session caching, transport selection.
- `docs/sdk/identity.md` — `Identity::Client` (resolve by key / attributes, public field revelation, revocation), relationship with Auth certificates.

Cross-link with `guides/brc-103-wire.md` to clarify the boundary between Auth (BRC-31/52/104) and wire transport (BRC-103).

**Acceptance:** pages land with frontmatter under the SDK section; runnable end-to-end examples; cross-references from BRC-103 wire guide.

### Sub-issue 3 — Fill in coverage gaps on existing pages (new)

- `docs/sdk/transaction.md` — `ChainTracker(s)`, `FeeModel(s)`, expand `MerklePath`.
- `docs/sdk/script.md` — `PushDropTemplate` section, referencing the registries/overlay use case.
- `docs/sdk/primitives.md` — Schnorr signatures, key shares (Shamir-style splitting).
- `docs/overlays/registries.md` — Registry::Client write paths (register / update / revoke) with worked example.

**Acceptance:** every topic in the coverage table above has either a dedicated section or an explicit out-of-scope rationale.

### Sub-issue 4 — Collapse `General` section — see #877

Execute the existing HLR #877: move `docs/general/mcp.md` → `docs/reference/mcp.md` with a redirect stub, delete `general/index.md`, add `docs/sdk/auth.md` and `docs/sdk/identity.md` (from sub-issue 2) to nav.

**Acceptance:** per #877.

### Sub-issue 5 — Create CONTRIBUTING.md — see #878

Execute the existing HLR #878: code / docs / issue-PR / release sections, linked from README.

**Acceptance:** per #878.

## Acceptance criteria (overall)

- [ ] All known broken code examples fixed (incl. `README.md` Basic Usage); no new ones introduced
- [ ] `BSV::Auth` and `BSV::Identity` have dedicated SDK pages
- [ ] `Transaction` page covers `ChainTracker`, `FeeModel`, `MerklePath`
- [ ] `Script` page covers `PushDropTemplate`
- [ ] `Primitives` page covers Schnorr and key shares
- [ ] #877 done — `General` section removed; `mcp.md` lives under `reference/`
- [ ] #878 done — `CONTRIBUTING.md` exists at repo root
- [ ] `rake docs:lint` + `rake docs:proofread` green
- [ ] No 404s from `README.md` links or external references

## Out of scope

- A doctest harness that executes every code block in CI (worth doing later; needs its own design).
- Rewriting the YARD output style or format.
- A companion docs site for `bsv-wallet` (separate repo, separate concern).
- `CODE_OF_CONDUCT.md` (#878 already excludes).
- Mirroring CONTRIBUTING work to `bsv-wallet` (separate HLR per #878).

## Context

- #861 / #865 — Jekyll migration that settled the toolchain
- #856 — moved Track-2 content into `reference/`; redirect-stub pattern
- #877 — General / Reference rationalisation (executed under sub-issue 4)
- #878 — CONTRIBUTING.md (executed under sub-issue 5)
