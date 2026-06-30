---
title: Auth
nav_order: 6
parent: SDK
---

# Auth

The `BSV::Auth` module implements three complementary BSV authentication protocols:

| Class | BRC | Role |
|-------|-----|------|
| `Auth::AuthFetch` | [BRC-104](https://brc.dev/104) | Authenticated HTTP client |
| `Auth::Peer` / `Auth::PeerSession` | [BRC-103](https://brc.dev/103) | Mutual-auth message protocol |
| `Auth::Certificate` / `Auth::MasterCertificate` | [BRC-52](https://brc.dev/52) + [BRC-53](https://brc.dev/53) | Identity certificate format and selective disclosure |
| `Auth::AuthMiddleware` | BRC-104 server side | Rack adapter |

**Boundary note:** this page covers the Auth protocol layer (BRC-103 mutual auth, BRC-52/53
certificates, BRC-104 HTTP transport). The lower-level BRC-103 *wire format* for BRC-100 wallet
calls is a separate concern documented in [BRC-103 Wire Layer](../guides/brc-103-wire.md).
[Identity::Client](identity.md) builds on top of Auth certificates to publish and revoke
on-chain identity tokens.

---

## AuthFetch — BRC-104
{: #auth-fetch }

`Auth::AuthFetch` is the primary client for authenticated HTTP. It wraps `Peer` internally
and exposes a simple `#fetch` method. For most applications this is the only Auth class you
need to interact with directly.

### Construction

```ruby
require 'bsv-sdk'

# wallet must be a BRC-100 interface (ProtoWallet or bsv-wallet Client)
client = BSV::Auth::AuthFetch.new(wallet: my_wallet)
```

Optional parameters:

```ruby
session_mgr = BSV::Auth::SessionManager.new(default_ttl: 7200)  # 2-hour TTL

client = BSV::Auth::AuthFetch.new(
  wallet:                  my_wallet,
  requested_certificates:  { certifiers: ['02abc...'], types: { 'exOl3K...' => ['email'] } },
  session_manager:         session_mgr,
  payment_max_retries:     5
)
```

### Basic authenticated GET

```ruby
response = client.fetch('https://api.example.com/resource')

puts response.status        # => 200
puts response.body          # => '{"data": "..."}'
puts response.identity_key  # => '02abc...' — server's compressed public-key hex
```

`AuthFetch` handles the BRC-103 handshake automatically on the first request to each
base URL. Subsequent requests to the same base URL reuse the cached session.

### POST with a JSON body

```ruby
response = client.fetch(
  'https://api.example.com/items',
  method: 'POST',
  body:   { name: 'example', value: 42 },  # Hash → JSON automatically
  timeout: 60
)
```

### 402 Payment Required

When a server responds with HTTP 402, `AuthFetch` automatically:

1. Reads the `x-bsv-payment-satoshis-required`, `x-bsv-payment-derivation-prefix`, and
   `x-bsv-identity-key` response headers.
2. Derives a payment key and creates a BSV transaction via `wallet.create_action`.
3. Retries the original request with an `x-bsv-payment` header containing the signed transaction.

This requires the wallet to implement `get_public_key` and `create_action` (i.e. a full wallet,
not just `ProtoWallet`).

```ruby
# AuthFetch handles 402 silently — the caller just sees the final response
response = client.fetch('https://api.example.com/paid-resource')
puts response.status  # => 200 if payment succeeded, 402 if max retries exhausted
```

### Session caching

`SessionManager` caches authenticated sessions per base URL. The default TTL is **3,600 seconds**
(one hour). Pass `nil` to disable expiry entirely — suitable for long-running daemons that
connect to a fixed set of servers.

```ruby
# No expiry
session_mgr = BSV::Auth::SessionManager.new(default_ttl: nil)

# Share one session pool across multiple AuthFetch instances
session_mgr = BSV::Auth::SessionManager.new(default_ttl: 3600)

client_a = BSV::Auth::AuthFetch.new(wallet: wallet, session_manager: session_mgr)
client_b = BSV::Auth::AuthFetch.new(wallet: wallet, session_manager: session_mgr)
```

The `SessionManager` is dual-indexed (by session nonce and by peer identity key) and supports
multiple concurrent sessions per peer. Call `session_mgr.sweep_expired` periodically in
long-running servers to reclaim memory.

### Thread safety

`AuthFetch` is safe to use from multiple threads. The `@peers` hash (one `Peer` per base URL)
is protected by a `Mutex`. Each in-flight request uses its own `Queue` to match the response
to the originating call, so concurrent requests to the same server do not interfere.

`SessionManager` is independently thread-safe (all mutations are under a single `Mutex`).

### Security: redact bodies in logging

Payment envelopes (`x-bsv-payment`) contain signed transactions. Application-level request
and response bodies may carry sensitive credentials or private data. Never log full request or
response bodies in production.

```ruby
# Wrong — leaks payment transaction and response body to the log
response = client.fetch('https://api.example.com/resource')
logger.debug("response: #{response.body}")

# Right — log only the status and identity key; omit body content
response = client.fetch('https://api.example.com/resource')
logger.debug("auth fetch: status=#{response.status} peer=#{response.identity_key[0, 16]}...")
```

---

## Peer / PeerSession — BRC-103
{: #peer }

`Auth::Peer` implements the BRC-103 mutual-authentication message protocol. `AuthFetch` uses
`Peer` internally; reach for `Peer` directly only when building custom transports or when
you need to exchange arbitrary authenticated payloads between two parties.

**BRC-103 is NOT BRC-31.** BRC-31 was the earlier "Authrite" precursor. BRC-103 superseded it.
The protocol version negotiated on the wire is `'0.1'`.

### Handshake overview

```
Initiator                                 Responder
──────────                                ─────────
Peer.new(wallet:, transport:)             Peer.new(wallet:, transport:)
#to_peer(payload, peer_identity_key)  →
                                          Peer fires on_general_message callback
                           ←   (handshake + authenticated general message)
```

The handshake is two messages:

1. `initialRequest` — initiator sends identity key and session nonce.
2. `initialResponse` — responder echoes nonce, signs over both nonces, sends its own nonce.

After the handshake, all subsequent messages are `general` messages signed over the payload
with a per-message nonce.

### Using Peer with a transport

You must supply a `Transport` — any object that includes `BSV::Auth::Transport` and implements
`#send` and `#on_data`:

```ruby
# Using the built-in SimplifiedFetchTransport (HTTP POST to /.well-known/auth)
transport = BSV::Auth::SimplifiedFetchTransport.new('https://server.example.com')
peer      = BSV::Auth::Peer.new(wallet: my_wallet, transport: transport)

received = Queue.new
peer.on_general_message { |sender_key, payload| received.push([sender_key, payload]) }

# Send an authenticated message (handshake auto-initiated on first call)
peer.to_peer([72, 101, 108, 108, 111])  # "Hello" as byte array

sender_key, payload = received.pop
puts sender_key   # => '02abc...' — server's identity key
puts payload.pack('C*')  # => 'Hello' echoed back
```

### Certificate negotiation

Pass `certificates_to_request` to require the peer to present certificates during the
handshake. The peer must hold matching certificates or the connection is rejected.

```ruby
TRUSTED_CERTIFIER = '02deadbeef...'  # pin to a known certifier pubkey

peer = BSV::Auth::Peer.new(
  wallet: my_wallet,
  transport: transport,
  certificates_to_request: {
    certifiers: [TRUSTED_CERTIFIER],
    types:      { 'exOl3K...' => ['email'] }
  }
)

peer.on_certificates_received do |sender_key, certs|
  certs.each { |c| puts "received cert from #{c['certifier']}" }
end
```

### Security: nonce sourcing

Nonces in BRC-103 are self-authenticating: 16 CSPRNG bytes followed by a 32-byte HMAC-SHA256
computed by the wallet. Only the wallet that created a nonce can verify it. They are **not**
reusable and must **never** come from user input.

```ruby
# Wrong — user-supplied nonce, breaks authentication guarantee
nonce = params[:nonce]  # attacker controls this
session.session_nonce = nonce

# Right — let BSV::Auth::Nonce generate it
nonce = BSV::Auth::Nonce.create(my_wallet)
# Nonce.create is called internally by Peer; you do not need to call it directly
```

`BSV::Auth::Nonce.create` wraps `SecureRandom.random_bytes(16)` followed by
`wallet.create_hmac`. Never substitute a counter, timestamp, or application-generated string.

### Security: certifier-pubkey pinning

When verifying a peer's certificate, always check the certifier against a known list.
Trust-on-first-use (TOFU) — accepting whatever certifier the peer claims — defeats certificate
verification entirely.

```ruby
KNOWN_CERTIFIERS = [
  '02deadbeef...',  # production certifier
  '03cafebabe...'   # backup certifier
].freeze

peer.on_certificates_received do |sender_key, certs|
  certs.each do |cert|
    certifier = cert.is_a?(Hash) ? cert['certifier'] : cert.certifier
    unless KNOWN_CERTIFIERS.include?(certifier)
      raise BSV::Auth::AuthError, "Untrusted certifier: #{certifier}"
    end
    # proceed with cert.fields
  end
end
```

---

## Certificate / MasterCertificate — BRC-52 + BRC-53
{: #certificates }

`Auth::Certificate` (BRC-52) represents a signed identity certificate binding named fields to
a subject public key. `Auth::MasterCertificate` (BRC-53) extends it with creation and
selective-disclosure flows.

### Two-layer encryption envelope

Each certificate field is encrypted with a two-layer scheme:

1. **Per-field symmetric key** — a random AES-256-GCM key generated for each field independently.
2. **Wrapped symmetric key** — the per-field key is re-encrypted via BRC-42 derivation:
   - Protocol: `[2, 'certificate field encryption']`
   - Key ID for the *master* keyring: `field_name` (no serial number)
   - Key ID for a *verifier* keyring: `"#{serial_number} #{field_name}"`

The serial-number scoping in the verifier key ID is what prevents cross-certificate replay:
a keyring entry produced for certificate A cannot be used to decrypt certificate B, even if
both share a field with the same name.

### Issuing a certificate (certifier side)

```ruby
certifier_wallet = BSV::Wallet::ProtoWallet.new(certifier_key)
cert_type        = Base64.strict_encode64(SecureRandom.random_bytes(32))

cert = BSV::Auth::MasterCertificate.issue_certificate_for_subject(
  certifier_wallet,
  subject_pubkey_hex,
  { 'email' => 'alice@example.com', 'name' => 'Alice' },
  cert_type
)

puts cert.serial_number   # Base64-encoded 32-byte random serial
puts cert.signature       # DER-encoded certifier signature (hex)
```

### Selective disclosure — the default example

Selective disclosure is the normal case. To reveal a field to a verifier, re-wrap the
per-field symmetric key for the verifier's public key — **no re-encryption of the field value
itself**:

```ruby
# Subject holds the MasterCertificate and a wallet
subject_wallet   = BSV::Wallet::ProtoWallet.new(subject_key)
verifier_pubkey  = '02verifier...'

verifier_keyring = BSV::Auth::MasterCertificate.create_keyring_for_verifier(
  subject_wallet,
  certifier:        cert.certifier,
  verifier:         verifier_pubkey,
  fields:           cert.fields,
  fields_to_reveal: ['email'],          # selective — only email, not name
  master_keyring:   cert.master_keyring,
  serial_number:    cert.serial_number
)

verifiable = BSV::Auth::VerifiableCertificate.from_certificate(cert, verifier_keyring)

# Transmit verifiable.to_h to the verifier
```

**What happens under the hood:**

1. Subject decrypts the master keyring entry for `'email'` (key ID: `'email'`, counterparty:
   certifier pubkey).
2. Verifies the recovered symmetric key actually decrypts `cert.fields['email']`.
3. Re-encrypts the symmetric key for the verifier (key ID: `"#{serial_number} email"`,
   counterparty: verifier pubkey).
4. The verifier receives the encrypted field value plus the re-wrapped key — no plaintext
   ever leaves the subject's wallet.

### Verifier decryption

```ruby
verifier_wallet = BSV::Wallet::ProtoWallet.new(verifier_key)
vc              = BSV::Auth::VerifiableCertificate.from_hash(received_hash)

# Verify the certifier signature before trusting any fields
unless vc.verify
  raise 'Certificate signature invalid'
end

# Verify certifier identity against pinned list (see Security section)
unless KNOWN_CERTIFIERS.include?(vc.certifier)
  raise "Untrusted certifier: #{vc.certifier}"
end

decrypted = vc.decrypt_fields(verifier_wallet)
puts decrypted['email']  # => 'alice@example.com'
```

### Certificate signature verification

Signatures use BRC-42 derivation with:
- Protocol: `[2, 'certificate signature']`
- Key ID: `"#{type} #{serial_number}"`
- Counterparty: `'anyone'` on signing; certifier pubkey on verifying

```ruby
valid = cert.verify
puts valid  # => true
```

---

## AuthMiddleware — server-side adapter
{: #auth-middleware }

`Auth::AuthMiddleware` is a Rack middleware that adds BRC-104 server-side authentication to
any Rack application. It intercepts BRC-103 handshake requests and authenticated general
messages, passing everything else through to the downstream app.

```ruby
# config.ru
require 'bsv-sdk'

app = proc do |env|
  [200, { 'content-type' => 'application/json' }, ['{"status":"ok"}']]
end

wallet = BSV::Wallet::ProtoWallet.new(BSV::Primitives::PrivateKey.generate)

use BSV::Auth::AuthMiddleware,
  wallet:                 wallet,
  certificates_to_request: nil   # omit to skip certificate requirements

run app
```

The middleware handles three categories of request:

| Request | Handling |
|---------|----------|
| `POST /.well-known/auth` | BRC-103 handshake dispatch via internal `Peer` |
| Request with `x-bsv-auth-*` headers | Signature verification; downstream app called; response signed |
| Everything else | Passed through unchanged |

See `gem/bsv-sdk/lib/bsv/auth/auth_middleware.rb` for the full implementation including the
`BridgeTransport` that connects the HTTP request/response cycle to the internal `Peer`.
