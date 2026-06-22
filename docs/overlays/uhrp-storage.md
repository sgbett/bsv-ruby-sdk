# UHRP Storage

UHRP — the **Universal Hash Resource Protocol**
([BRC-26](https://hub.bsvblockchain.org/brc/overlays/0026)) — is a
content-addressed file-storage layer for BSV.

Each file has a self-verifying URL of the form
`XUT6PqWb3GP3LR7dmBMCJwZ3oo5g1iGCF3CrpzyuJCemkGu1WGoq` — a Base58Check
encoding of the SHA-256 hash of the content with a two-byte
`0xCE 0x00` version prefix. Anyone who knows the URL can request the file,
fetch it from any willing host, and verify it's the right bytes by
recomputing the hash.

## Why it exists

Centralised storage has a single point of failure: if the host disappears
or pulls the file, the link is dead. UHRP turns that on its head:

1. **Anyone can host.** A host advertises that it has the file by publishing
   a UTXO whose locking script contains the file's SHA-256 hash, the URL it
   will serve from, and an expiry timestamp.
2. **Anyone can find a host.** A reader queries the `ls_uhrp` lookup service
   with a UHRP URL and gets back a list of currently-advertised host URLs.
3. **The content is self-verifying.** The reader downloads from any host
   and SHA-256s the body. If the hash matches, the content is correct —
   the host is untrusted.
4. **Hosts can be paid to stay online.** The advertisement UTXO can be
   funded by the publisher, multiplying the hosts as a hedge against any
   single host going offline.

This is what makes UHRP useful for content the network has to keep
available — long-term archives, software updates, signed certificates —
without trusting any one server.

## What the SDK provides

The `bsv-sdk` gem ships the **read path**: URL helpers and a downloader.

### `BSV::Storage::Utils` — URL encode/decode

```ruby
require 'bsv-sdk'

# Encode 32 raw bytes as a UHRP URL
data = File.binread('document.pdf')
url  = BSV::Storage::Utils.get_url_for_file(data)
# => "XUT7mGMrAbG3EWJz..."

# Decode a URL back to its 32-byte SHA-256 hash
hash = BSV::Storage::Utils.get_hash_from_url(url)

# Validate (never raises)
BSV::Storage::Utils.valid_url?(url)         # => true
BSV::Storage::Utils.valid_url?('not-a-url') # => false
```

URLs are accepted with or without the `uhrp:` or `uhrp://` scheme prefix.
The `web+uhrp://` variant is deliberately not normalised — we follow the TS
SDK contract here so URLs round-trip identically across SDKs.

### `BSV::Storage::Downloader` — resolve and fetch

```ruby
require 'bsv-sdk'

dl = BSV::Storage::Downloader.new(network_preset: :mainnet)

# What hosts currently advertise this file?
urls = dl.resolve('uhrp://XUT7mGMrAbG3EWJz...')
# => ["https://nanostore.example/cdn/abc...", "https://archive.example/uhrp/xyz..."]

# Download and verify
result = dl.download('uhrp://XUT7mGMrAbG3EWJz...')
result.data       # => binary file content (already SHA-256 verified)
result.mime_type  # => "application/pdf"
```

The downloader queries `ls_uhrp`, decodes each PushDrop output to extract
the host URL and expiry, drops expired advertisements, and then walks the
host list until one returns bytes that match the URL's hash. 4xx and 5xx
responses are treated as failed hosts and the next URL is tried — there
is no special handling for 401/402/403 in v1.

See [SDK reference: Storage](../sdk/storage.md) for the full method
surface.

## What the wallet provides

Publishing to UHRP — creating the host-advertisement UTXOs — lives in
[`bsv-wallet`](https://github.com/sgbett/bsv-wallet). A `StorageUploader` there takes a file
and a target host, signs the advertisement, pays the satoshi cost, and
submits to the `tm_uhrp` topic on behalf of the wallet's identity.

The split matches the SDK/wallet boundary: reading needs no key material or
funding; publishing needs both.

## Reference implementations and infrastructure

The canonical UHRP storage server references now live in the
[bsv-blockchain/ts-stack](https://github.com/bsv-blockchain/ts-stack)
monorepo under `infra/`:

- **[uhrp-server-basic](https://github.com/bsv-blockchain/ts-stack/tree/main/infra/uhrp-server-basic)** (`@bsv/uhrp-lite`) — minimal single-host implementation suitable for local-development or a single-tenant deployment.
- **[uhrp-server-cloud-bucket](https://github.com/bsv-blockchain/ts-stack/tree/main/infra/uhrp-server-cloud-bucket)** (`@bsv/uhrp-storage-server`) — cloud-bucket-backed implementation for production deployments.

Both implement:

- Upload endpoints that accept file content plus a hosting commitment.
- A notifier that broadcasts the advertisement to the overlay.
- Billing for hosting duration.

The standalone `bsv-blockchain/storage-server` repo was archived in May
2026 when the two-tier split was introduced inside ts-stack.

Public UHRP overlay nodes are reachable through the default
`BSV::Overlay::LookupResolver` — you don't need to know specific host
URLs in normal SDK usage.

## Edge cases worth knowing

- **Privacy of host URLs.** The downloader follows whatever URLs the
  overlay returns, including non-HTTPS or private-IP hosts. The SHA-256
  verification means the returned bytes can't be tampered with, but the
  DNS resolution and TCP attempt itself can leak. For wallet apps running
  on user devices, consider filtering URLs before fetching (the SDK
  doesn't filter by design — that policy belongs at the integration
  layer).
- **Redirects are not followed.** Net::HTTP's default is preserved. A 302
  is treated as a failed host. Hosts that need to redirect should serve
  directly.
- **Expired advertisements are silently dropped.** No exception, no log
  line — the host simply doesn't appear in `resolve`'s result.

## References

- [BRC-26](https://hub.bsvblockchain.org/brc/overlays/0026) — UHRP specification
- [ts-stack/infra/uhrp-server-basic](https://github.com/bsv-blockchain/ts-stack/tree/main/infra/uhrp-server-basic) — minimal reference server (`@bsv/uhrp-lite`)
- [ts-stack/infra/uhrp-server-cloud-bucket](https://github.com/bsv-blockchain/ts-stack/tree/main/infra/uhrp-server-cloud-bucket) — production reference server (`@bsv/uhrp-storage-server`)
- TypeScript: [`StorageDownloader.ts`](https://github.com/bsv-blockchain/ts-stack/blob/main/packages/sdk/src/storage/StorageDownloader.ts)
- Python: [`bsv/storage/downloader.py`](https://github.com/bsv-blockchain/py-sdk/blob/master/bsv/storage/downloader.py)
- [SDK reference: Storage](../sdk/storage.md)
