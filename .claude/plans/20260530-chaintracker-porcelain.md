# Provider-routed ChainTracker: first wedge into network porcelain

Date: 2026-05-30
Branch: `feat/783-chaintracker-porcelain`
HLR: #783
Status: Planned; sub-issues filed; ready for `/do-hlr 783`

## Context

`BSV::Transaction::ChainTracker` is the semantic capability "verify merkle
proofs / read chain tip". `ChainTrackers::Chaintracks` is the only concrete
implementation and it hard-codes `Protocols::Chaintracks` as its backend. That
backend assumes the caller is running their own `chaintracks_server` — no
public instance exists for GorillaPool (DNS NXDOMAIN; discovered while closing
out #775).

Meanwhile `Providers::GorillaPool` already exposes block-header data via
JungleBus (`/v1/block_header/tip`, `/v1/block_header/get/{height}`, both
return the merkle root). The plumbing exists; the semantic layer just doesn't
know to ask through the provider.

This is the smallest concrete instance of a broader pattern: **semantic
operations should route through a Provider, not bind to one branded
protocol**. Resolving it for ChainTracker establishes the pattern that
broadcast / get_tx / fee-model porcelain can follow later.

## Discovery (probed against live services, 2026-05-29)

| URL | Result |
|---|---|
| `https://chaintracks.gorillapool.io` | DNS NXDOMAIN — host does not exist |
| `https://arcade.gorillapool.io/tip` and variants | 404 |
| `https://chaintracks.junglebus.gorillapool.io` | DNS error |
| `https://junglebus.gorillapool.io/v1/block_header/tip` | **200** — returns tip with `merkleroot` |
| `https://junglebus.gorillapool.io/v1/block_header/get/{height}` | **200** — full header including `merkleroot` |

Testnet (probed 2026-05-30):

| URL | Result |
|---|---|
| `https://testnet.junglebus.gorillapool.io/v1/block_header/tip` | **200** — testnet tip (height ~1738231) |
| `https://testnet.junglebus.gorillapool.io/v1/block_header/get/1000000` | **200** — testnet header with `merkleroot` |

GorillaPool's chain data is served by JungleBus on both mainnet and testnet.
There is no separate `chaintracks_server` to wire.

## Two-layer architecture (existing, mostly correct)

```
┌─────────────────────────────────────────────────────────────┐
│ SEMANTIC LAYER (what callers need)                          │
│                                                             │
│   ChainTracker.valid_root_for_height?  "verify merkle root" │
│   ChainTracker.current_height          "current chain tip"  │
│   FeeModel.compute_fee                 "fee for this tx"    │
└─────────────────────────────────────────────────────────────┘
         │ today: hard-coded backend (Chaintracks)
         │ target: routes via Provider#call
         ▼
┌─────────────────────────────────────────────────────────────┐
│ PROVIDER LAYER (composes branded protocols, routes commands)│
│                                                             │
│   Provider#call(:command, …) → first-registered-wins        │
│   Providers::GorillaPool ─┬── Protocols::Arcade             │
│                           ├── Protocols::Ordinals           │
│                           └── Protocols::JungleBus          │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ WIRE-PROTOCOL LAYER (speaks a specific API shape)           │
│                                                             │
│   Protocols::ARC, Arcade, JungleBus, Chaintracks, …         │
└─────────────────────────────────────────────────────────────┘
```

Misalignment today: the semantic layer (`ChainTracker`) talks directly to a
single wire protocol instead of going through the Provider's command-routing
machinery.

## Design decisions

### A1 — Promote `ChainTracker` to a working default impl

`BSV::Transaction::ChainTracker.new(provider)` becomes a working instance
that wraps any Provider exposing `:get_block_header` and `:current_height`.
The base class doubles as the default implementation. Subclasses that
override both methods continue to work without calling `super`.

Alternative considered: separate `ChainTrackers::ProviderRouted` class. A1
chosen because it makes `ChainTracker.default` ergonomic and the base class
already describes itself as "an object that answers two questions" —
providing a useful default doesn't change that.

### B2 — Delete `ChainTrackers::Chaintracks`

The class exists only to wrap a Provider construction around
`Protocols::Chaintracks`. The porcelain ChainTracker subsumes it. For users
running their own chaintracks_server, construct a single-protocol Provider
explicitly:

```ruby
own = Provider.new('local') { |p| p.protocol Protocols::Chaintracks, base_url: 'http://my-server' }
tracker = ChainTracker.new(own)
```

Alternative considered: keep `Chaintracks` as a thin convenience without
`.default`. B2 chosen because the convenience is marginal and removing the
class avoids the dual-existence cognitive load.

### C2 — Doc note on `Protocols::Chaintracks` public availability

`Protocols::Chaintracks` is a correct wire-protocol class. Its YARD example
shows `arcade.gorillapool.io` as the base URL — wrong (the host returns 404
on every chaintracks path; GorillaPool's chain data lives on JungleBus).
Update the example to a local placeholder URL and add a one-line note that
no public Chaintracks instance is hosted; for general use against
GorillaPool, callers should use the porcelain `ChainTracker.new(provider)`
against JungleBus.

## Sub-tasks

Each ships as its own commit, following the per-task pattern.

### Task 1 — Add `:current_height` to `Protocols::JungleBus` (#784)

Single endpoint declaration plus spec coverage. Pattern already exists in
`Protocols::Chaintracks`. JungleBus's `/v1/block_header/tip` returns the
full tip header; a response lambda extracts `height`.

Files: `protocols/jungle_bus.rb`, `protocols/jungle_bus_spec.rb`,
`all_protocols_spec.rb` (command-count assertions shift).

### Task 2 — Promote `ChainTracker` to working impl (#785)

Constructor takes a Provider. `valid_root_for_height?` dispatches
`provider.call(:get_block_header, height)`, normalises the
`merkleroot`/`merkleRoot`/`merkle_root` field name diversity, compares
case-insensitively. `current_height` dispatches `provider.call(:current_height)`,
returns the Integer.

Files: `chain_tracker.rb`, `chain_tracker_spec.rb`.

### Task 3 — `ChainTracker.default`; remove `ChainTrackers::Chaintracks` (#786)

Add `ChainTracker.default(testnet: false)` returning a tracker against
`Providers::GorillaPool.default(testnet: testnet)`. Delete
`chain_trackers/chaintracks.rb` and its spec. Update
`Providers::GorillaPool.testnet` to register JungleBus alongside Arcade
(testnet probe confirmed JungleBus works at
`https://testnet.junglebus.gorillapool.io`) so the testnet default tracker
works out of the box.

Files: `chain_tracker.rb`, `chain_trackers.rb` (autoload),
`providers/gorilla_pool.rb`, `providers/defaults_spec.rb`. Delete
`chain_trackers/chaintracks.rb` and `chain_trackers/chaintracks_spec.rb`.

### Task 4 — `Protocols::Chaintracks` doc note (#787)

YARD-only change. Example URL → local placeholder. Add `@note` directing
readers to the porcelain for general use. Independent of other tasks; can
run in parallel.

Files: `protocols/chaintracks.rb`.

### Task 5 — Live integration spec (#788)

Env-gated read-only spec exercising `ChainTracker.default` against live
GorillaPool. Three examples: tip height returns Integer above a sanity
threshold; known-good merkle root validates; wrong root rejects. No funds
required.

Files: `chain_tracker_integration_spec.rb` (new).

### Task 6 — Docs and CHANGELOG (#789)

Update `docs/sdk/network.md` table, add a "Provider-routed semantic
operations" subsection to `docs/network/overview.md`, CHANGELOG entry
documenting the breaking removal of `ChainTrackers::Chaintracks` with
migration examples, and closing #778 (the chaintracks-wiring question
dissolves into the porcelain).

Files: `docs/sdk/network.md`, `docs/network/overview.md`,
`gem/bsv-sdk/CHANGELOG.md`.

## Sequencing

```
#784 → #785 → #786 → ( #788 ∥ #789 )
#787 independent — can run any time
```

## Acceptance criteria (HLR level)

- `Protocols::JungleBus` declares `:current_height`.
- `ChainTracker.new(provider)` works against any Provider that exposes both
  `:get_block_header` and `:current_height`.
- `ChainTracker.default` returns a working tracker against GorillaPool via
  JungleBus, both mainnet and testnet.
- `tracker.valid_root_for_height?` is case-insensitive across the
  `merkleroot`/`merkleRoot` field divergence.
- Live integration spec passes against live mainnet JungleBus.
- `BSV::Transaction::ChainTrackers::Chaintracks` is gone; constant lookup
  raises.
- `Providers::GorillaPool.testnet` registers JungleBus alongside Arcade.
- #778 closes when this HLR completes — the chaintracks-wiring question
  dissolves.

## Out of scope

- Broadcast porcelain (separate HLR — standardise `:broadcast` response
  shape across ARC and Arcade).
- Tx fetch porcelain (separate HLR — `:get_tx` across JungleBus, Ordinals,
  WoC).
- Fee model porcelain (separate HLR — `LivePolicy` hard-codes its backend
  URL).
- Cross-provider failover (later — start with single-provider routing).
- Caching tier in the default ChainTracker. Callers wrap if they need it.
- Renaming `Protocols::Chaintracks`. Its wire shape is correct; only its
  presumed public availability is wrong.

## Risks

- Breaking removal of `ChainTrackers::Chaintracks` may affect downstream
  consumers. None in this repo. Documented in CHANGELOG with migration.
- `Providers::GorillaPool.testnet` gaining JungleBus changes
  `defaults_spec.rb` expectations — straightforward fix.
- Field name normalisation must handle at least `merkleroot`, `merkleRoot`,
  `merkle_root`. Tests cover all three.
- `Provider#call` raises `ArgumentError` when no protocol serves a command.
  The porcelain lets this propagate — callers see the same error for
  misconfigured providers as for any other command misuse.

## References

- HLR #783 — Provider-routed ChainTracker: first wedge into network porcelain
- #778 — Wire GorillaPool's chaintracks_server (dissolves into this HLR)
- #775 — Arcade split (sibling concern; surfaced this misalignment)
- Existing pattern: `Protocols::Chaintracks#current_height` lambda response
- Probes documented inline above
