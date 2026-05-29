# BRC-103 Wire Layer

The BRC-103 wire layer is a compact binary frame protocol for invoking BRC-100 wallet methods over
any transport. It encodes method calls, arguments, results, and errors as byte sequences —
independently of HTTP, sockets, or any other carrier. All 28 BRC-100 methods are covered: from
`create_action` through `get_version`.

The Ruby SDK implements both sides:

- **Client side** — `WalletWireTransceiver`: serialises Ruby keyword arguments to binary frames,
  transmits them over a transport, and deserialises the binary result back to a Ruby hash.
- **Server side** — `WalletWireProcessor`: decodes incoming binary frames, dispatches to any
  `Interface::BRC100` wallet, and returns binary result frames.
- **Transport** — `WalletWire` (module): the single-method interface that connects the two sides.
  Any class that implements `transmit_to_wallet(message)` can serve as a transport.

## Choosing a substrate

| Substrate | Use case |
|-----------|----------|
| `Substrates::HTTPWalletWire` | Binary frames over HTTP/HTTPS (`Content-Type: application/octet-stream`). High-throughput inter-service calls or any server that speaks the BRC-103 binary protocol. |
| `Substrates::HTTPWalletJSON` | JSON over HTTP/HTTPS (`Content-Type: application/json`). Posts to `/v1/wallet/{camelCaseMethodName}`; matches MetaNet Desktop conventions. Does not use the binary frame codec. |
| In-process loopback (`WalletWireProcessor`) | Testing, or calling a wallet in the same Ruby process without serialisation overhead. |

If you are building something new and control both client and server, prefer `HTTPWalletWire` — it is more compact and avoids JSON parsing overhead. If you are connecting to MetaNet Desktop or any existing server that speaks JSON over HTTP, use `HTTPWalletJSON`.

## End-to-end example: HTTPWalletWire

```ruby
require 'bsv-sdk'

# Connect to a server running WalletWireProcessor or any go-sdk compatible binary server.
client = BSV::Wallet::Substrates::HTTPWalletWire.client(base_url: 'https://wallet.example')

# All 28 BRC-100 methods are available as Ruby methods.
result = client.get_public_key(identity_key: true)
# result[:public_key] is a 33-byte compressed pubkey as a binary string.
puts result[:public_key].unpack1('H*')  # "0279be..." — hex form for display

result = client.get_network
puts result[:network]     # :mainnet or :testnet

result = client.get_version
puts result[:version]     # "0.1.0"
```

The `.client` factory is a convenience wrapper. It is exactly equivalent to:

```ruby
wire   = BSV::Wallet::Substrates::HTTPWalletWire.new(base_url: 'https://wallet.example')
client = BSV::Wallet::WalletWireTransceiver.new(wire)
```

### Adding request headers

Pass `headers:` when you need bearer tokens or other per-request metadata:

```ruby
client = BSV::Wallet::Substrates::HTTPWalletWire.client(
  base_url: 'https://wallet.example',
  headers:  { 'Authorization' => 'Bearer eyJ...' }
)
```

## End-to-end example: HTTPWalletJSON

`HTTPWalletJSON` posts JSON to `{base_url}/v1/wallet/{methodName}`, where `methodName` is
the camelCase BRC-100 name (e.g. `getPublicKey`, `createAction`). It implements
`Interface::BRC100` directly — there is no binary frame layer.

```ruby
require 'bsv-sdk'

client = BSV::Wallet::Substrates::HTTPWalletJSON.new(
  base_url: 'https://wallet.example.com'
)

result = client.get_network
puts result[:network]  # 'mainnet'

result = client.get_public_key(identity_key: true)
puts result[:public_key]  # "02abc..."
```

With authentication headers (e.g. connecting to MetaNet Desktop):

```ruby
client = BSV::Wallet::Substrates::HTTPWalletJSON.new(
  base_url: 'https://wallet.example.com',
  headers:  { 'Authorization' => 'Bearer eyJ...' }
)
```

## End-to-end example: loopback (in-process)

This pattern is ideal for tests and for applications where the wallet runs in the same process:

```ruby
require 'bsv-sdk'

key    = BSV::Primitives::PrivateKey.generate
proto  = BSV::Wallet::ProtoWallet.new(key)

# WalletWireProcessor includes WalletWire, so it can be passed directly to the transceiver.
processor = BSV::Wallet::WalletWireProcessor.new(proto)
client    = BSV::Wallet::WalletWireTransceiver.new(processor)

# client has the full BRC-100 interface; calls go through binary serialisation and back.
result = client.get_public_key(identity_key: true)
puts result[:public_key].unpack1('H*')  # 66-char hex of the identity public key
```

The loopback path is byte-for-byte identical to a real wire call — it uses the full serialisation
stack, so it exercises the same code paths as remote calls. This makes it useful for writing
integration tests that verify wire behaviour without a running server.

## Implementing a custom transport

Implement `transmit_to_wallet` in any class and include `WalletWire`:

```ruby
class MyTransport
  include BSV::Wallet::WalletWire

  def transmit_to_wallet(message)
    # message is a binary String (ASCII-8BIT encoding, BRC-103 request frame).
    # Return a binary String (BRC-103 result frame).
    raw_response = MyTransportLayer.call(message)
    raw_response
  end
end

client = BSV::Wallet::WalletWireTransceiver.new(MyTransport.new)
client.get_height  # => { height: 123456 }
```

## The `authenticated?` method

Call byte 23 in the BRC-103 specification is labelled `IS_AUTHENTICATED`. The Ruby interface
uses `authenticated?` (predicate suffix, no `is_` prefix), matching the existing
`Interface::BRC100` definition. When calling through the wire, use the Ruby name:

```ruby
client.authenticated?  # => { authenticated: true }
```

The wire layer handles the mapping from `authenticated?` to call byte 23 internally.

## Error handling and rehydration

When the server-side wallet raises a `BSV::Wallet::Error` subclass, `WalletWireProcessor` encodes
the error code and message into an error result frame. `WalletWireTransceiver` decodes the frame
and re-raises the matching subclass on the client side:

```ruby
client = BSV::Wallet::WalletWireTransceiver.new(processor)

begin
  client.create_action(description: 'pay invoice', outputs: [])
rescue BSV::Wallet::InsufficientFundsError => e
  puts e.message  # the original message from the server
  puts e.code     # 5
rescue BSV::Wallet::Error => e
  puts e.code     # 1–7 depending on the failure
end
```

The full error class table is in the [error reference](../sdk/wallet.md#wire-layer-errors).

## Cross-SDK conformance

The wire format matches the go-sdk byte-for-byte. Conformance vectors covering all 28 call
types live under `gem/bsv-sdk/spec/bsv/wallet/conformance/brc103/` in the SDK source. A Ruby
server (`WalletWireProcessor`) can serve a go-sdk client and vice versa without any conversion
layer.
