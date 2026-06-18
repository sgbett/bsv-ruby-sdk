# Overlay services

Overlay services are application protocols that live *on top of* the base BSV
network. They don't change Bitcoin — they index a slice of it, agreeing on a
common interpretation of certain UTXOs and providing a lookup API for clients.

If you've used the SDK's `Storage::Downloader` or `KVStore::Global`, you've
already used an overlay service.

## The problem they solve

The base BSV protocol broadcasts transactions and proves them with merkle
roots. It doesn't help you ask questions like:

- "Which UTXOs advertise the file with this SHA-256 hash?"
- "What's the current value of this key for this controller?"
- "Where can I download `uhrp://XUT6Pq…`?"

Answering those needs a higher layer that watches transactions, tags the
relevant outputs, and lets clients query by application-meaningful keys.
That higher layer is an overlay service.

## How an overlay works

An overlay node runs two complementary services:

1. A **topic manager** ([BRC-22](https://hub.bsvblockchain.org/brc/overlays/0022))
   accepts transactions submitted by any participant, decides which outputs
   are admissible into one or more *topics*, and tracks them. Topics are
   strings like `tm_kvstore` or `tm_uhrp` — see
   [BRC-87](https://hub.bsvblockchain.org/brc/overlays/0087) for the naming
   convention.

2. A **lookup service** ([BRC-24](https://hub.bsvblockchain.org/brc/overlays/0024))
   indexes the admitted outputs and exposes a query API. Lookup providers
   are also strings: `ls_kvstore`, `ls_uhrp`, etc.

Submission is `POST /submit`; query is `POST /lookup`. Both endpoints are
authenticated with [BRC-31](https://hub.bsvblockchain.org/brc/peer-to-peer/0031)
identity signatures, and may be monetised with
[BRC-41](https://hub.bsvblockchain.org/brc/payments/0041) micropayments.

Nodes that host the same topics gossip transactions to each other so the
overlay state stays consistent across the network. The discovery protocol
for finding nodes that host a given topic is
[BRC-23 CHIP](https://hub.bsvblockchain.org/brc/overlays/0023) — also known
as SHIP/SLAP in
[BRC-88](https://hub.bsvblockchain.org/brc/overlays/0088).

## Topic ⇄ lookup-service pairing

In practice, every overlay you'll use ships a `tm_*` topic manager and an
`ls_*` lookup service:

| Application | Topic | Lookup service | BRC |
|---|---|---|---|
| Content addressing (UHRP) | `tm_uhrp` | `ls_uhrp` | [BRC-26](https://hub.bsvblockchain.org/brc/overlays/0026) |
| Global key-value store | `tm_kvstore` | `ls_kvstore` | TS SDK reference |
| Registry definitions | `tm_basketmap` / `tm_protomap` / `tm_certmap` | `ls_basketmap` / `ls_protomap` / `ls_certmap` | [BRC-86](https://hub.bsvblockchain.org/brc/wallet/0086) |
| Identity certificates | `tm_users` | `ls_users` | BRC-52 |

The Ruby SDK's `BSV::Overlay::LookupResolver` is a single client that
multiplexes across any of these by passing the lookup-service identifier in
each query.

## SDK vs wallet — the read/write split

The `bsv-sdk` gem ships the **read paths** for the overlays above. Reading
is pure consumption: no UTXOs spent, no signatures over private keys, no
payment flow. A read client only needs an HTTP transport and a parser.

The **write paths** live in the [`bsv-wallet`](../gems/wallet.md) gem
because creating an advertisement, registering a definition, or setting
a KV entry requires:

- Spending a UTXO to fund the new output, which needs a wallet.
- Signing the output with the wallet's identity key.
- Optionally paying a BRC-41 micropayment to the overlay node.

The split keeps consumer apps light. A read-only viewer or aggregator can
depend on `bsv-sdk` alone; only apps that publish to an overlay also need
`bsv-wallet`.

## What this section covers

The pages below walk through each overlay the SDK supports today,
explaining what the protocol is, what the SDK provides, and where the
wallet picks up for writes.

- **[UHRP Storage](overlays/uhrp-storage.md)** — content-addressed file storage
  ([BRC-26](https://hub.bsvblockchain.org/brc/overlays/0026))
- **[Historian](overlays/historian.md)** — walk the history of any
  application-level state through its transaction ancestry
- **[KVStore](overlays/kvstore.md)** — read overlay-backed signed key-value
  entries
- **[Registries](overlays/registries.md)** — resolve named baskets, protocols,
  and certificate types
  ([BRC-86](https://hub.bsvblockchain.org/brc/wallet/0086))

## Further reading

- BSV Academy: [Essentials of Overlay Services](https://hub.bsvblockchain.org/higher-learning/bsv-academy/bsv-network-topology/essentials-of-overlay-services)
- BRC overlay specs: [22](https://hub.bsvblockchain.org/brc/overlays/0022),
  [24](https://hub.bsvblockchain.org/brc/overlays/0024),
  [26](https://hub.bsvblockchain.org/brc/overlays/0026),
  [87](https://hub.bsvblockchain.org/brc/overlays/0087),
  [88](https://hub.bsvblockchain.org/brc/overlays/0088)
- Reference SDKs: [TypeScript (ts-stack monorepo)](https://github.com/bsv-blockchain/ts-stack) — SDK at `packages/sdk/`, overlay packages at `packages/overlays/`,
  [Go](https://github.com/bsv-blockchain/go-sdk),
  [Python](https://github.com/bsv-blockchain/py-sdk)
