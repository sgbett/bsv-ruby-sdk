# Storage

The `BSV::Storage` module provides utilities for working with UHRP (Unified Hash Resource
Protocol), the content-addressed storage standard used by BSV overlay services.

## Storage::Utils

`Storage::Utils` encodes and decodes UHRP URLs. A UHRP URL is a Base58Check string whose
payload contains the SHA-256 hash of the content, making each URL self-verifying and
stable across storage providers.

```ruby
require 'bsv-sdk'

# Generate a UHRP URL from file content
data = File.binread('document.pdf')
url  = BSV::Storage::Utils.get_url_for_file(data)
# => "XUT7mGMrAbG3EWJz..."

# Round-trip: decode the hash back from the URL
hash = BSV::Storage::Utils.get_hash_from_url(url)
# => 32-byte binary SHA-256 digest

# Validate a URL (returns false rather than raising)
BSV::Storage::Utils.valid_url?(url)         # => true
BSV::Storage::Utils.valid_url?('not-a-url') # => false

# Normalise a URL that includes the uhrp: scheme or // authority prefix
normalised = BSV::Storage::Utils.normalize_url('uhrp://XUT7mGMrAbG3EWJz...')
```

**Contract notes:**

- `get_url_for_file` computes SHA-256 internally — pass raw binary, not hex.
- `get_hash_from_url` accepts `uhrp:` and `uhrp://` prefixes; `web+uhrp://` is not
  stripped (follows the TS SDK; Python diverges here).
- `valid_url?` never raises — use it as a guard before `get_hash_from_url`.

## Storage::Downloader

`Downloader` resolves a UHRP URL to a list of HTTP(S) hosts via the `ls_uhrp` overlay
lookup service, then fetches the content and verifies its SHA-256 hash.

```ruby
require 'bsv-sdk'

downloader = BSV::Storage::Downloader.new(network_preset: :mainnet)

# Resolve only — returns an Array of download URLs without fetching content
urls = downloader.resolve('XUT7mGMrAbG3EWJz...')
# => ["https://staging-nanostore.babbage.systems/cdn/..."]

# Full download — verifies hash, returns DownloadResult
result = downloader.download('XUT7mGMrAbG3EWJz...')
result.data       # => binary String (file content)
result.mime_type  # => "application/pdf"
```

**Contract notes:**

- Any 4xx/5xx response, empty body, or network exception causes that host to be skipped;
  the next host in the list is tried automatically.
- `download` raises `BSV::Storage::DownloadError` if all hosts fail or the UHRP lookup
  returns no entries.
- HTTP redirects are not followed in v1.
- Pass `http_client:` to inject a test double that responds to `.call(url)` and returns
  an object with `#code`, `#body`, and `#[]` (header access).
