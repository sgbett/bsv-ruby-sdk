# Model Arcade as a distinct protocol from ARC; fix GorillaPool provider

Date: 2026-05-29
Branch: TBD (sub-branch off `master`)
Status: Drafted, awaiting approval to open HLR + sub-issues

## Context

`bitcoin-sv/arc` and `bsv-blockchain/arcade` are different broadcast services.
Arcade markets itself as having an "Arc-compatible API" but the actual paths,
response bodies, status taxonomies, and endpoint coverage diverge enough that
treating them as the same protocol produces 404s on every request and silent
shape mismatches when responses do come back.

The SDK currently registers `Protocols::ARC` against
`https://arcade.gorillapool.io` inside `Providers::GorillaPool`. This was a
category error rather than a path typo. The same provider also registers
`Protocols::Chaintracks` against the same host, which is also broken — Arcade's
chaintracks_server runs as a separate service on a different port with
different paths.

## Phase 0 findings (probed against live services, 2026-05-29)

### Arcade `:broadcast`

- Path: `POST /tx` (no `/v1` prefix).
- Accepts `application/octet-stream`, `text/plain` hex, or `application/json`
  with `{"rawTx": "<hex>"}`.
- Success: `{"status": "submitted"}`.
- Idempotent re-submit: `{"status": "already submitted", "txid": "<hex>",
  "state": "SEEN_ON_NETWORK"}`.
- Validation failure: HTTP 400 + `{"reason": "..."}`.
- Backpressure: HTTP 503 + `Retry-After: 1` header.

ARC by contrast returns `{"txid": "...", "txStatus": "SEEN_ON_NETWORK", ...}`.
The two response bodies do not overlap. Shared response parsing is not viable.

### Arcade `:get_tx_status`

- Path: `GET /tx/{txid}`.
- Hit: 200 + `{txid, txStatus, status, timestamp, blockHash, blockHeight,
  merklePath, extraInfo, competingTxs}`.
- Miss: 404 + `{"error": "transaction not found"}` even when the txid is a
  known-mined mainnet tx. Verified empirically. Arcade only knows transactions
  it has been asked to track; it is not a general blockchain query interface.

This is a behavioural divergence with broader implications for the network
porcelain layer ([[project_network_porcelain.md]]): Arcade is fine for
"broadcast and follow my own submissions" but useless for "look up an arbitrary
txid".

### Arcade `txStatus` taxonomy

`RECEIVED`, `SEEN_ON_NETWORK`, `SEEN_ON_MULTIPLE_NODES`, `MINED`, `IMMUTABLE`,
`REJECTED`.

ARC adds `DOUBLE_SPEND_ATTEMPTED`, `INVALID`, `MALFORMED`,
`MINED_IN_STALE_BLOCK`. Only `REJECTED` overlaps. ARC's `REJECTED_STATUSES`
constant must not be shared with Arcade.

### Arcade `:health`

- Path: `GET /health`.
- Body: `{"status": "ok", "datahub_urls": [{"url": "...", "healthy": true},
  ...]}`.

ARC's `/v1/health` returns a standard ARC-shaped body. Codebase grep
confirms no current consumer of `provider.call(:health)` outside the protocol
declarations themselves, so divergent health shapes are safe today.

### Arcade `:get_policy`

Does not exist. Arcade's validation policy is configured server-side via YAML.

### Chaintracks on `arcade.gorillapool.io`

`Protocols::Chaintracks` requests `/chaintracks/v2/tip` and
`/chaintracks/v2/header/height/{height}`. Arcade's chaintracks_server uses
`/tip`, `/headers`, `/header/height/:height`, `/header/hash/:hash`, etc. — no
`/chaintracks/v2/` prefix — and is mounted as a separate service on its own
port. All paths probed against `arcade.gorillapool.io` returned 404.

### Headers

Arcade documents `X-CallbackUrl`, `X-CallbackToken`, `X-FullStatusUpdates`,
`X-SkipFeeValidation`, `X-SkipScriptValidation`.

ARC additionally uses `XDeployment-ID`, `X-SkipTxValidation`, `X-CallbackBatch`.
These remain ARC-only.

## Design

### Sibling protocols, not a shared abstract base

The shared-abstract-base proposal from the initial plan is withdrawn. Response
bodies and status taxonomies diverge too much to model Arcade as a kind of ARC
or to factor a meaningful "ArcCompatible" base out of them. Forcing the
abstraction would lie about the upstream relationship.

`Protocols::Arcade` and `Protocols::ARC` both subclass `Protocol` directly.
Each owns its endpoint table, its escape hatches, its response parsing.

### Narrow shared helpers

The genuine overlap is small. Two ways to handle it:

1. Lift `resolve_tx_hex` and `safe_parse_json` to module-level helpers
   (`BSV::Network::Util` or similar).
2. Inline the helpers in each protocol.

Decision: option 1. Both helpers are useful for other protocols too
(`Protocols::TAALBinary` already does its own hex coercion). Putting them in a
shared namespace removes copy-paste without inventing a misleading inheritance
relationship.

### Endpoint-path refactor for ARC

`ARC#call_broadcast` and `ARC#call_broadcast_many` currently hardcode
`'/v1/tx'` and `'/v1/txs'` inside the escape hatch instead of reading from the
endpoint table. Refactor both to read the path from
`self.class.endpoints[:broadcast][:path]` via a small helper, so subclasses (or
future siblings) can declare a different path and reuse the same escape hatch
skeleton. No behaviour change; existing `arc_spec.rb` expectations stay green.

### `Protocols::Arcade` surface (v1)

```ruby
endpoint :broadcast,     :post, '/tx',          response: :json
endpoint :get_tx_status, :get,  '/tx/{txid}',   response: :json
endpoint :health,        :get,  '/health',      response: :json
```

Escape hatches:

- `call_broadcast(tx, **opts)` — JSON body `{"rawTx": <hex>}`, Arcade headers,
  Arcade response parser:
  - 200 + `{"status": "submitted"}` → success, `data: {"status": "submitted"}`.
  - 200 + `{"status": "already submitted", "txid": ..., "state": ...}` →
    success, `data: body`.
  - 400 + `{"reason": ...}` → `http_success: false`, `error_message: reason`.
  - 503 → `http_success: false`, retryable, surface `Retry-After` header in
    error message.
- `call_get_tx_status(txid)` — passes through the 404-on-unknown semantics. A
  404 returns a `ProtocolResponse` with `http_success: false` and a
  recognisable error class so callers can distinguish "not found" from "server
  error".

Out of v1 scope: `:broadcast_many`, `:ready`, `:get_policy`, SSE `/events`.

### `Providers::GorillaPool` rewire

```ruby
Provider.new('GorillaPool', auth: resolved_auth, rate_limit: rate_limit) do |p|
  p.protocol Protocols::Arcade,   base_url: 'https://arcade.gorillapool.io', auth: auth, **opts
  p.protocol Protocols::Ordinals, base_url: 'https://ordinals.gorillapool.io', **common
  p.protocol Protocols::JungleBus, base_url: 'https://junglebus.gorillapool.io', **common
end
```

- Drop `Protocols::ARC` registration entirely.
- Drop the broken `Protocols::Chaintracks` registration. Leave an inline
  comment pointing to a follow-up issue for correctly wiring GorillaPool's
  chaintracks_server (separate URL/port, separate work).
- Same shape for testnet.

### Live broadcast integration spec

`spec/bsv/network/protocols/broadcast_integration_spec.rb`, tagged
`:integration`, env-gated on `BSV_LIVE_TEST_WIF`. With the WIF present:

1. Read the funded UTXO from a configured source (probe the address via the
   provider being tested, or accept a `BSV_LIVE_TEST_PREVOUT` env hint).
2. Build a 1-in/1-out spend back to the same address, 100 sat/kB fee.
3. Broadcast via `Providers::TAAL.mainnet(api_key: ENV['TAAL_API_KEY'])` —
   assert `txStatus` is one of `SEEN_ON_NETWORK | RECEIVED`.
4. Broadcast via `Providers::GorillaPool.mainnet` — assert `status` is
   `submitted` or `already submitted`.
5. `:get_tx_status` against TAAL — assert the txid round-trips.

This is the single most valuable spec to add. Its absence is the underlying
reason the GorillaPool category error survived multiple PRs.

## Sub-tasks

Each ships as its own PR ([[feedback_commit_per_task.md]]).

### Task 1 — Refactor ARC broadcast path lookup

- Replace hardcoded `'/v1/tx'` / `'/v1/txs'` in `call_broadcast` /
  `call_broadcast_many` with a lookup from `self.class.endpoints`.
- No behaviour change. All existing `arc_spec.rb` examples pass.
- Lift `resolve_tx_hex` and `safe_parse_json` to `BSV::Network::Util` (or
  equivalent shared location); ARC delegates.

### Task 2 — Introduce `Protocols::Arcade`

- New file `lib/bsv/network/protocols/arcade.rb`.
- Endpoint declarations as above.
- Escape hatches for broadcast and get_tx_status with Arcade-specific response
  parsing.
- Add to `Protocols` autoload.
- Add `arcade_spec.rb` mirroring `arc_spec.rb` structure with stubbed HTTP:
  request shape assertions, success / re-submit / 400 / 503 / 404 response
  parsing.
- Add Arcade to `all_protocols_spec.rb` coverage sweep.

### Task 3 — Rewire `Providers::GorillaPool`

- Swap `Protocols::ARC` → `Protocols::Arcade` in `mainnet` / `testnet`.
- Drop the broken `Protocols::Chaintracks` registration with an inline TODO
  comment referencing the follow-up issue number.
- Update `providers/defaults_spec.rb` expectations.
- Update `auth_integration_spec.rb` scenarios referencing GorillaPool ARC.
- Update doc comments in the file to talk about Arcade.

### Task 4 — Live broadcast integration spec

- New spec, env-gated on `BSV_LIVE_TEST_WIF`.
- Skips cleanly without the env var so CI does not require funds.
- Exercises both `Providers::TAAL` (ARC) and `Providers::GorillaPool` (Arcade)
  end-to-end.

### Task 5 — Docs

- Update or add a network guide explaining the ARC vs Arcade distinction.
- Mention which providers run which.
- Note the broken-Chaintracks follow-up.
- `CHANGELOG.md` entry under unreleased — flag this as a breaking change for
  anyone consuming `Providers::GorillaPool.mainnet.call(:broadcast, ...)`
  expecting ARC-shape responses ([[feedback_no_compat_shims.md]] — pre-1.0,
  clean break, no shim).

## Acceptance criteria

- `Protocols::Arcade` exists with the v1 surface above.
- `Providers::GorillaPool.mainnet.call(:broadcast, tx)` succeeds against the
  live service.
- `Providers::TAAL.mainnet(api_key:).call(:broadcast, tx)` continues to
  succeed against the live service.
- `Providers::GorillaPool` no longer registers `Protocols::ARC` or the broken
  `Protocols::Chaintracks` configuration.
- All existing specs pass.
- New `arcade_spec.rb` unit spec exists.
- New live-network broadcast integration spec exists, env-gated.
- A follow-up issue is open for correctly wiring GorillaPool's
  chaintracks_server.

## Out of scope

- Wiring GorillaPool's chaintracks_server. Separate HLR — needs URL/port
  information from GorillaPool docs or contacts.
- Arcade `:broadcast_many` (different body format from ARC's JSON array).
- Arcade SSE `/events` subscription support.
- Arcade `:ready` endpoint support.
- Arcade `:get_policy` — does not exist upstream.
- Intent-based routing across providers — separate work
  ([[project_network_porcelain.md]]).

## Risks

- Removing the broken Chaintracks registration is a breaking change for any
  caller that was somehow relying on the failure mode. Verify no code paths
  depend on Chaintracks-via-GorillaPool returning errors.
- `:health` shape divergence: if any future code starts consuming
  `provider.call(:health)` expecting an ARC shape, swapping providers breaks
  it. Mitigated today by zero consumers.
- ARC's `REJECTED_STATUSES` constant must not leak into Arcade's response
  parser. Arcade's narrower taxonomy needs its own constant.
- Live broadcast spec needs a real funded WIF in env. Document the
  `BSV_LIVE_TEST_WIF` env var in the spec file header and in the network guide.

## References

- `bitcoin-sv/arc` — original ARC implementation (TAAL runs this at
  `arc.taal.com`).
- `bsv-blockchain/arcade` — Teranode-era reimplementation (GorillaPool runs
  this at `arcade.gorillapool.io`). README markets it as "Arc-compatible" but
  paths and response bodies diverge.
- Phase 0 probes in conversation history dated 2026-05-29.
