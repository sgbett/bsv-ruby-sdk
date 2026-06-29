---
title: Custom Provider Integration
nav_order: 2
parent: Testing
---

# Custom Provider integration

The SDK includes an integration test that exercises the Protocol DSL and
Provider dispatch against a live
[chaintracks-cloudflare](https://github.com/Calhooon/chaintracks-cloudflare)
worker — a Rust-based Cloudflare Worker that exposes BSV block header data over
HTTP.

The test is tagged `:chaintracks_live` and skipped by default. It makes
read-only GET requests and is safe to run repeatedly.

## Why this test exists

The built-in protocols (`ARC`, `WoCREST`, `Chaintracks`, etc.) ship with the
SDK and are tested in the main spec suite. But consumers can define their own
protocols for any HTTP service. This integration test proves that the full
custom-protocol path works end-to-end against real HTTP:

- **Protocol DSL** — `endpoint` declarations, command registration, introspection
- **Response handlers** — `:json`, `:raw`, and custom lambdas returning
  different types (integer, string, hash, boolean)
- **Path interpolation** — `{placeholder}` tokens in URL paths and query strings,
  filled from keyword arguments
- **Provider dispatch** — command routing, capability matrix, error handling
- **Result types** — `Success`, `NotFound`, and `Error` mapped from HTTP status codes

## Running

```bash
bundle exec rspec --tag chaintracks_live
```

Optionally point at a different worker:

```bash
CHAINTRACKS_URL='https://my-worker.example.com' \
  bundle exec rspec --tag chaintracks_live
```

## How it works

The test defines a custom `Protocol` subclass inline, wires it into a
`Provider`, and calls every endpoint through the provider's `call` interface.

### Defining the protocol

Each `endpoint` declaration maps a command name to an HTTP method, a path
template, and a response handler:

```ruby
class ChaintracksWorker < BSV::Network::Protocol
  # :json handler — parses the body as JSON, returns a Hash
  endpoint :get_info, :get, '/getInfo', response: :json

  # Lambda handler — unwrap the worker's { status, value } envelope
  endpoint :current_height, :get, '/currentHeight',
    response: lambda { |body| JSON.parse(body)['value'] }

  # Path interpolation — {height} is filled from keyword args
  endpoint :find_header, :get, '/findHeaderHexForHeight?height={height}',
    response: lambda { |body| JSON.parse(body)['value'] }

  # Multiple placeholders
  endpoint :get_headers, :get, '/getHeaders?height={height}&count={count}',
    response: lambda { |body| JSON.parse(body)['value'] }

  endpoint :is_valid_root, :get,
    '/isValidRootForHeight?root={root}&height={height}',
    response: lambda { |body| JSON.parse(body)['value'] }
end
```

### Wiring into a provider

```ruby
tracker = BSV::Network::Provider.new('MyChaintracks') do |p|
  p.protocol ChaintracksWorker,
    base_url: 'https://rust-chaintracks.dev-a3e.workers.dev'
end
```

### Calling endpoints

```ruby
# No parameters
result = tracker.call(:current_height)
result.data  # => 945704

# Single keyword parameter — interpolated into {height}
result = tracker.call(:find_header, height: 945_694)
result.data  # => { "height" => 945694, "merkleRoot" => "...", ... }

# Multiple parameters
result = tracker.call(:get_headers, height: 945_694, count: 3)
result.data  # => "0100000083..." (480 hex chars = 3 x 80-byte headers)

# Error handling
result = tracker.call(:find_header, height: 999_999_999)
result.success?    # => false
result.not_found?  # => true
```

### Introspection

```ruby
tracker.commands
# => #<Set: {:get_info, :current_height, :find_header, ...}>

tracker.capability_matrix
# => { #<ChaintracksWorker> => [:current_height, :find_header, ...] }

tracker.protocol_for(:current_height)
# => #<ChaintracksWorker>
```

## Cross-verification

The test also verifies that the custom provider and the SDK's built-in
`WhatsOnChain` ChainTracker agree on chain state — heights match within 2
blocks, and a merkle root fetched from the worker validates against WoC. This
confirms that custom and built-in providers can interoperate against the same
chain.

## Acknowledgements

Thanks to [John Calhoon](https://x.com/johncalhooon) for the
[chaintracks-cloudflare](https://github.com/Calhooon/chaintracks-cloudflare)
project, which gave us a real-world, publicly available HTTP service to test
custom provider integration against.
