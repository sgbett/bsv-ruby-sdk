# Network Architecture Redesign — Command/Provider/Registry

**HLR:** #494
**Date:** 2026-04-18
**Status:** Draft

## Overview

Replace the SDK's ad-hoc network classes with a declarative Command/Provider/Registry
architecture. Providers declare capabilities; consumers compose them via a Registry with
automatic failover. The SDK defines the command vocabulary; gems register providers at boot.

## Motivation

- No UTXO on-chain verification (blocks #376 janitor, UTXOPool health)
- No failover between providers
- Conflated interfaces (`ChainProvider` mixes chain verification with UTXO fetching)
- Adding new providers requires touching multiple classes across gems
- TS wallet-toolbox solved this with a monolithic 400-line `Services` class — we can do better

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ Command Vocabulary (SDK — declarative)              │
│                                                     │
│  :broadcast  :get_tx  :is_utxo  :get_merkle_path   │
│  :get_utxos  :current_height  :valid_root  ...      │
└──────────────────────┬──────────────────────────────┘
                       │ defines
┌──────────────────────▼──────────────────────────────┐
│ Provider Implementations (SDK — declarative)         │
│                                                     │
│  WhatsOnChain    provides :get_tx, :is_utxo, ...    │
│  ARC             provides :broadcast, :get_tx_status│
│  (future) mAPI   provides :broadcast, :is_utxo      │
│  (future) Node   provides :get_tx, :broadcast        │
└──────────────────────┬──────────────────────────────┘
                       │ registered into
┌──────────────────────▼──────────────────────────────┐
│ Registry (Consumer — imperative at boot)             │
│                                                     │
│  register(woc, except: [:broadcast])                │
│  register(arc, only: [:broadcast, :get_tx_status])  │
│                                                     │
│  call(:is_utxo, txid, vout)  → WoC                 │
│  call(:broadcast, tx)        → ARC                  │
│  call(:get_tx, txid)         → WoC (→ ARC fallback) │
└─────────────────────────────────────────────────────┘
```

## Phased Delivery

### Phase 1 — Core Framework (#495)

**Scope:** Command, Provider, Registry, Specifier, Result types.

**Files:**
- `gem/bsv-sdk/lib/bsv/network/command.rb`
- `gem/bsv-sdk/lib/bsv/network/provider.rb`
- `gem/bsv-sdk/lib/bsv/network/registry.rb`
- `gem/bsv-sdk/lib/bsv/network/specifier.rb`
- `gem/bsv-sdk/lib/bsv/network/result.rb`
- `gem/bsv-sdk/spec/bsv/network/command_spec.rb`
- `gem/bsv-sdk/spec/bsv/network/provider_spec.rb`
- `gem/bsv-sdk/spec/bsv/network/registry_spec.rb`

**Key decisions:**
- Commands are value objects (frozen after definition)
- Provider base class uses `provides` class macro and `call_<name>` convention
- Registry dispatch is synchronous (no async/threading)
- Result type is a simple tagged union: Success, Error(retryable:), NotFound
- Failover iterates providers in registration order on retryable errors

**No external dependencies. No existing code changed. Purely additive.**

### Phase 2 — Provider Implementations (#496)

**Scope:** WhatsOnChain provider (7 commands), ARC provider (4 commands).

**Files:**
- `gem/bsv-sdk/lib/bsv/network/providers/whats_on_chain.rb`
- `gem/bsv-sdk/lib/bsv/network/providers/arc.rb`
- `gem/bsv-sdk/spec/bsv/network/providers/whats_on_chain_spec.rb`
- `gem/bsv-sdk/spec/bsv/network/providers/arc_spec.rb`

**Key decisions:**
- Providers wrap HTTP calls and normalise responses
- WoC provider adds `:is_utxo` (new WoC endpoint: `GET /tx/{txid}/out/{vout}/spent`)
- WoC provider adds `:get_merkle_path` (existing WoC endpoint: `GET /tx/{txid}/proof/tsc`)
- ARC provider adapts existing `BSV::Network::ARC` logic (EF format, rejection handling)
- Both support injectable `http_client:` for test isolation

**Risk:** WoC's `/tx/{txid}/out/{vout}/spent` endpoint needs verification — confirm it
exists and returns a usable response. Fallback: derive from address UTXO set.

### Phase 3 — SDK Integration (#497)

**Scope:** Default registry, command definitions, backward compatibility.

**Files:**
- `gem/bsv-sdk/lib/bsv/network/commands.rb` (command vocabulary)
- `gem/bsv-sdk/lib/bsv/network.rb` (default_registry, convenience methods)
- Integration specs

**Key decisions:**
- `BSV::Network.default_registry` is lazy-initialised, configurable via env vars
- Existing `ARC.default` and `WhatsOnChain.new` continue to work unchanged
- No deprecation warnings yet — Phase 4 handles wallet migration
- `BSV::Network.commands` and `BSV::Network.capability_matrix` are introspection APIs

### Phase 4 — Wallet Integration (#498)

**Scope:** WalletClient accepts Registry, new wallet operations, ChainProvider deprecated.

**Files:**
- `gem/bsv-wallet/lib/bsv/wallet_interface/wallet_client.rb` (accept `network:` param)
- `gem/bsv-wallet/lib/bsv/wallet_interface/wallet_health.rb` (new)
- `gem/bsv-wallet/spec/...`

**Key decisions:**
- `network:` param is a Registry; backward compat wraps legacy params in a Registry
- `wallet_health(verify: true)` iterates outputs, calls `:is_utxo`, quarantines invalids
- `recover_failed_broadcast(txid)` calls `:get_tx_status`, promotes or cleans up
- `BroadcastQueue` wraps Registry's `:broadcast` command (not a separate injection)
- `ChainProvider` module stays but emits deprecation warnings

**This phase unblocks #376 (janitor) and UTXOPool on-chain health checks.**

### Phase 5 — Documentation Generation (#499)

**Scope:** Capability matrix, command docs, introspection APIs, rake tasks.

**Files:**
- `gem/bsv-sdk/lib/bsv/network/documentation.rb`
- `gem/bsv-sdk/lib/tasks/network.rake`

**Key decisions:**
- Documentation is a projection of existing declarations — no manual maintenance
- Capability matrix shows provider × command availability
- Extension point for remote capability discovery (`.well-known` pattern) — not implemented
- Rake tasks for CLI output; programmatic API for integration

## Dependency Chain

```
#495 (framework) → #496 (providers) → #497 (SDK integration)
                                            │
                                            ▼
                                      #498 (wallet)  →  #376 (janitor)
                                            │
                                      #499 (docs)
```

Phases 1-3 are sequential. Phases 4 and 5 can run in parallel after Phase 3.

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| WoC `/tx/{txid}/out/{vout}/spent` endpoint may not exist | Verify before Phase 2. Fallback: derive from address UTXO set or script hash history |
| Large refactor scope | Each phase is independently releasable; existing code never breaks |
| Over-abstraction | Phase 1 is minimal — Command, Provider, Registry. No factories, no middleware, no plugin system. Extend only when concrete need arises |
| Performance (failover latency) | Failover is sequential, not parallel. Consider parallel dispatch later if needed |

## Release Strategy

- Phase 1-3: SDK release (0.13.0 — new MINOR for framework addition)
- Phase 4: Wallet release (0.10.0 — new MINOR for Registry integration)
- Phase 5: SDK patch or minor (documentation only)
- #376: Wallet release after Phase 4

## Open Questions

1. Should the existing `BSV::Network::ARC` class be refactored to extend `Provider`, or should `Providers::ARC` be a new class wrapping it?
2. Should `BroadcastQueue` (InlineQueue/SolidQueueAdapter) be provider-aware, or continue wrapping a raw broadcaster?
3. How should rate limiting be handled — per-provider config, or Registry-level throttling?
