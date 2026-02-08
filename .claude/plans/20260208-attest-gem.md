# BSV Attest — Data Attestation Gem

## Context

Issue #7. All SDK dependencies are complete (primitives, script, transaction, network, chain provider, wallet). `bsv-attest` is a thin domain layer: hash data, publish hash to chain, verify hash on chain.

Separate gem (`bsv-attest`) in the same monorepo, depending on `bsv-sdk`.

---

## File Structure

```
bsv-attest.gemspec                          # NEW
lib/bsv-attest.rb                           # NEW: gem entry point
lib/bsv/attest.rb                           # NEW: autoload hub + module methods
lib/bsv/attest/version.rb                   # NEW
lib/bsv/attest/configuration.rb             # NEW
lib/bsv/attest/response.rb                  # NEW
lib/bsv/attest/verification_error.rb        # NEW

spec/bsv/attest/configuration_spec.rb       # NEW
spec/bsv/attest/response_spec.rb            # NEW
spec/bsv/attest/verification_error_spec.rb  # NEW
spec/bsv/attest/attest_spec.rb              # NEW
```

**Modified:** `Gemfile` (add second gemspec), `.rubocop.yml` (add attest exclusions)

---

## Build Order (6 steps)

### 1. Version + Gemspec

**`lib/bsv/attest/version.rb`** — `BSV::Attest::VERSION = '0.1.0'`

**`bsv-attest.gemspec`** — follows `bsv-sdk.gemspec` pattern:
- `add_dependency 'bsv-sdk'`
- `required_ruby_version >= 2.7`
- `licence: 'Open BSV'`
- `files: Dir.glob('lib/bsv/attest{.rb,/**/*}') + %w[lib/bsv-attest.rb LICENCE]`

### 2. VerificationError

**`lib/bsv/attest/verification_error.rb`**

```ruby
class VerificationError < StandardError; end
```

**Spec:** StandardError subclass, stores message.

### 3. Configuration

**`lib/bsv/attest/configuration.rb`**

```ruby
class Configuration
  attr_accessor :wallet, :broadcaster, :provider
end
```

- `wallet` — `BSV::Wallet::Wallet` instance (for fund+sign)
- `broadcaster` — any `#broadcast(tx)` (e.g. ARC)
- `provider` — any `#fetch_transaction(txid)` (e.g. WhatsOnChain, for verify)
- All default to `nil`; errors surface at use time

**Spec:** defaults to nil, supports setting all three attributes.

### 4. Response

**`lib/bsv/attest/response.rb`**

```ruby
class Response
  attr_reader :hash, :transaction, :txid

  def initialize(hash:, transaction:, txid:)
  def hash_hex  # @hash.unpack1('H*')
end
```

- `hash` — binary 32-byte SHA-256 digest
- `transaction` — `BSV::Transaction::Transaction` instance
- `txid` — hex string from broadcast response

**Spec:** attribute storage, `hash_hex` returns 64-char hex string.

### 5. Module methods + entry point

**`lib/bsv/attest.rb`** — autoload hub + class methods:

```ruby
module BSV
  module Attest
    autoload :Configuration,     'bsv/attest/configuration'
    autoload :Response,          'bsv/attest/response'
    autoload :VerificationError, 'bsv/attest/verification_error'

    class << self
      def configuration    # lazy-initialised Configuration.new
      def configure        # yield(configuration)
      def reset_configuration!

      def hash(data)
        BSV::Primitives::Digest.sha256(data)
      end

      def publish(data, wallet: nil, broadcaster: nil)
        # 1. hash(data)
        # 2. Build tx with OP_RETURN output containing hash
        # 3. wallet.fund_and_sign(tx)
        # 4. broadcaster.broadcast(tx)
        # 5. Return Response.new(hash:, transaction:, txid:)
        # Raises ArgumentError if wallet/broadcaster missing
      end

      def verify(data, txid, provider: nil)
        # 1. hash(data)
        # 2. provider.fetch_transaction(txid)
        # 3. Scan outputs for OP_FALSE OP_RETURN <data> pattern
        # 4. Return true if any data chunk matches hash
        # 5. Raise VerificationError if not found
        # Raises ArgumentError if provider missing
      end
    end
  end
end
```

**`lib/bsv-attest.rb`** — entry point:
```ruby
require 'bsv-sdk'
require_relative 'bsv/attest'
```

**Key details:**
- `publish` and `verify` accept per-call overrides (`wallet:`, `broadcaster:`, `provider:`) alongside global config
- OP_RETURN detection: `chunks[0].opcode == OP_FALSE && chunks[1].opcode == OP_RETURN`, data from `chunks[2..]`
- Underlying errors propagate naturally (BroadcastError, InsufficientFundsError, ChainProviderError)
- Does NOT add `autoload :Attest` to `lib/bsv-sdk.rb` — separate gem loads itself

**Spec (`attest_spec.rb`):**
- `.hash` — returns 32-byte binary SHA-256, matches `Digest.sha256`
- `.configure` / `.reset_configuration!` — yields config, resets to defaults
- `.publish` — builds OP_RETURN tx, calls fund_and_sign, broadcasts, returns Response; raises ArgumentError without wallet/broadcaster; accepts per-call overrides
- `.verify` — returns true when hash found in OP_RETURN; raises VerificationError when not found; raises ArgumentError without provider; works with multi-push OP_RETURN outputs

**Mock strategy** (follows `wallet_spec.rb` pattern):
- Mock wallet: `#fund_and_sign(tx)` returns tx
- Mock broadcaster: `#broadcast(tx)` returns `BroadcastResponse.new(txid: ...)`
- Mock provider: `#fetch_transaction(txid)` returns a real Transaction built with `Script.op_return`

### 6. Wiring

- **`Gemfile`** — replace placeholder comment with `gemspec name: 'bsv-attest'`
- **`.rubocop.yml`** — add `lib/bsv/attest/**/*` to Metrics exclusions, `spec/bsv/attest/**/*` to RSpec exclusions, `lib/bsv-attest.rb` to `Naming/FileName` exclude

---

## Existing Code to Reuse

| Need | Existing code | File |
|------|--------------|------|
| SHA-256 | `BSV::Primitives::Digest.sha256(data)` | `lib/bsv/primitives/digest.rb` |
| OP_RETURN script | `BSV::Script::Script.op_return(*data_items)` | `lib/bsv/script/script.rb` |
| Script chunks | `script.chunks` → `[Chunk]` with `.opcode`, `.data` | `lib/bsv/script/chunk.rb` |
| Opcodes | `OP_FALSE = 0x00`, `OP_RETURN = 0x6a` | `lib/bsv/script/opcodes.rb` |
| Transaction | `BSV::Transaction::Transaction.new`, `.add_output` | `lib/bsv/transaction/transaction.rb` |
| Output | `TransactionOutput.new(satoshis:, locking_script:)` | `lib/bsv/transaction/transaction_output.rb` |
| Fund+sign | `wallet.fund_and_sign(tx)` | `lib/bsv/wallet/wallet.rb` |
| Broadcast | `broadcaster.broadcast(tx)` → `BroadcastResponse` | `lib/bsv/network/arc.rb` |
| Fetch tx | `provider.fetch_transaction(txid)` → `Transaction` | `lib/bsv/network/whats_on_chain.rb` |

---

## Commit Sequence

1. `feat(attest): add bsv-attest gem with version and gemspec`
2. `feat(attest): add VerificationError exception class`
3. `feat(attest): add Configuration class`
4. `feat(attest): add Response value object`
5. `feat(attest): add hash, publish, and verify module methods`
6. `chore(attest): wire up Gemfile and extend RuboCop exclusions`

---

## Verification

```bash
bundle install                          # resolves both gemspecs
bundle exec rspec spec/bsv/attest/      # attest specs pass
bundle exec rubocop                     # no new lint violations
bundle exec rake                        # full suite green
```
