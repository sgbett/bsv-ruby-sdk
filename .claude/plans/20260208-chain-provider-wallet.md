# BSV Ruby SDK — Chain Data Provider + Wallet

## Context

Planning for issue #7 (attestation) revealed two SDK gaps. `bsv-attest` needs to fund transactions and fetch raw transactions from the chain, but the SDK currently only *sends* data (via ARC). These are SDK-level concerns, not attest-level concerns.

**Dependency chain:** Primitives → Script → Transaction → Network → **Chain Provider** → **Wallet** → (then Attest)

## What We're Building

### 1. Chain Data Provider (extends `BSV::Network`)

Read data FROM the blockchain. Duck-typed contract — any object responding to `#fetch_utxos(address)` and `#fetch_transaction(txid)` qualifies. WhatsOnChain as the default implementation.

### 2. Wallet (new `BSV::Wallet` module)

Holds a private key, sources UTXOs via a chain provider, funds and signs transactions. P2PKH-only for MVP.

## File Structure

```
lib/bsv/network/
  utxo.rb                          # UTXO value object
  chain_provider_error.rb          # ChainProviderError exception
  whats_on_chain.rb                # WhatsOnChain implementation

lib/bsv/
  wallet.rb                        # autoload hub
  wallet/
    insufficient_funds_error.rb    # InsufficientFundsError exception
    wallet.rb                      # Wallet class

spec/bsv/network/
  utxo_spec.rb
  chain_provider_error_spec.rb
  whats_on_chain_spec.rb

spec/bsv/wallet/
  insufficient_funds_error_spec.rb
  wallet_spec.rb
```

**Modified files:** `lib/bsv/network.rb` (add autoloads), `lib/bsv-sdk.rb` (add Wallet autoload), `.rubocop.yml` (add wallet exclusions)

---

## Build Order (7 steps)

### 1. `UTXO` — value object

**File:** `lib/bsv/network/utxo.rb`

```ruby
class UTXO
  attr_reader :tx_hash, :tx_pos, :satoshis, :height

  def initialize(tx_hash:, tx_pos:, satoshis:, height: nil)
  def ==(other)  # compare by tx_hash + tx_pos (the outpoint)
  alias eql? ==
  def hash       # consistent with == for use in Hash/Set
end
```

- `tx_hash` is hex string (display order), matching WoC API field name
- `satoshis` (not `value`) for consistency with SDK conventions
- `height: nil` for unconfirmed (WoC returns `height: 0` for unconfirmed)

**Spec:** attribute storage, equality by outpoint, hash consistency, read-only attributes.

### 2. `ChainProviderError` — exception

**File:** `lib/bsv/network/chain_provider_error.rb`

```ruby
class ChainProviderError < StandardError
  attr_reader :status_code

  def initialize(message, status_code: nil)
end
```

Follows the `BroadcastError` pattern. No `txid` (not meaningful for read operations).

**Spec:** StandardError subclass, stores message and status_code, defaults to nil.

### 3. `WhatsOnChain` — chain data provider

**File:** `lib/bsv/network/whats_on_chain.rb`

```ruby
class WhatsOnChain
  BASE_URL = 'https://api.whatsonchain.com'

  def initialize(network: :mainnet, http_client: nil)
    @network = network == :mainnet ? 'main' : 'test'
    @http_client = http_client
  end

  # @return [Array<UTXO>]
  def fetch_utxos(address)
    # GET /v1/bsv/{network}/address/{address}/unspent
    # Maps WoC JSON: tx_hash, tx_pos, value→satoshis, height
  end

  # @return [BSV::Transaction::Transaction]
  def fetch_transaction(txid)
    # GET /v1/bsv/{network}/tx/{txid}/hex
    # Returns plain text hex → Transaction.from_hex(body)
  end

  private

  def get(path)           # builds GET request, delegates to execute
  def execute(uri, request) # injectable HTTP client or Net::HTTP fallback
  def handle_response(response) # raises ChainProviderError on non-2xx
end
```

**Key details:**
- Same injectable HTTP client pattern as ARC (`#request(uri, req)` returning `#code` + `#body`)
- `fetch_utxos` response is JSON array: `[{tx_hash, tx_pos, value, height}]`
- `fetch_transaction` response is **plain text** hex (not JSON) — no JSON parsing needed
- Network: `:mainnet` → `'main'`, `:testnet` → `'test'` in URL path
- No auth needed (WoC free tier, 3 req/sec)

**Spec:** (same mock HTTP client pattern as `arc_spec.rb`)
- `fetch_utxos`: returns Array<UTXO>, correct URL, field mapping (value→satoshis), empty array for no UTXOs, testnet URL, raises on HTTP error
- `fetch_transaction`: returns parsed Transaction, correct URL, raises on HTTP error
- Non-JSON response handling

### 4. Wire up Network autoloads

**File:** `lib/bsv/network.rb` — add autoloads for `UTXO`, `ChainProviderError`, `WhatsOnChain`

### 5. `InsufficientFundsError` — exception

**File:** `lib/bsv/wallet/insufficient_funds_error.rb`

```ruby
class InsufficientFundsError < StandardError
  attr_reader :required, :available

  def initialize(message = nil, required: nil, available: nil)
    super(message || "insufficient funds: need #{required}, have #{available}")
  end
end
```

**Spec:** StandardError subclass, stores required/available, generates default message, accepts custom message.

### 6. `Wallet` — fund, sign, balance

**File:** `lib/bsv/wallet/wallet.rb`

```ruby
class Wallet
  DUST_THRESHOLD = 1

  attr_reader :private_key, :provider

  def initialize(private_key:, provider:)

  def address(network: :mainnet)
    # private_key.public_key.address(network: network)
  end

  def balance(network: :mainnet)
    # provider.fetch_utxos(address).sum(&:satoshis)
  end

  def fund(tx, network: :mainnet, satoshis_per_byte: 0.5)
    # See algorithm below
  end

  def sign(tx)
    tx.sign_all(@private_key)
  end

  def fund_and_sign(tx, network: :mainnet, satoshis_per_byte: 0.5)
    fund(tx, network: network, satoshis_per_byte: satoshis_per_byte)
    sign(tx)
  end

  private

  def locking_script
    @locking_script ||= BSV::Script::Script.p2pkh_lock(@private_key.public_key.hash160)
  end

  def build_input(utxo)
    # TransactionInput with txid_from_hex, source_satoshis, source_locking_script
  end
end
```

#### `fund()` algorithm

```ruby
def fund(tx, network: :mainnet, satoshis_per_byte: 0.5)
  utxos = @provider.fetch_utxos(address(network: network))
  output_total = tx.total_output_satoshis

  # Add a dummy change output so fee estimation accounts for its size
  dummy_change = TransactionOutput.new(satoshis: 0, locking_script: locking_script)
  tx.outputs << dummy_change

  input_total = tx.total_input_satoshis
  funded = false

  utxos.each do |utxo|
    tx.add_input(build_input(utxo))
    input_total += utxo.satoshis

    fee = tx.estimated_fee(satoshis_per_byte: satoshis_per_byte)
    if input_total >= output_total + fee
      funded = true
      break
    end
  end

  # Remove the dummy, calculate actual change
  tx.outputs.delete(dummy_change)

  unless funded
    fee = tx.estimated_fee(satoshis_per_byte: satoshis_per_byte)
    raise InsufficientFundsError.new(required: output_total + fee, available: input_total)
  end

  # Decide whether to add change output
  fee_without_change = tx.estimated_fee(satoshis_per_byte: satoshis_per_byte)
  remainder = input_total - output_total - fee_without_change

  if remainder >= DUST_THRESHOLD
    change_output = TransactionOutput.new(satoshis: remainder, locking_script: locking_script)
    tx.add_output(change_output)
    # Recalculate: adding change output increases fee slightly
    new_fee = tx.estimated_fee(satoshis_per_byte: satoshis_per_byte)
    fee_increase = new_fee - fee_without_change
    final_change = remainder - fee_increase
    if final_change >= DUST_THRESHOLD
      tx.outputs.delete(change_output)
      tx.add_output(TransactionOutput.new(satoshis: final_change, locking_script: locking_script))
    else
      tx.outputs.delete(change_output) # change absorbed by fee
    end
  end
  # If remainder < DUST_THRESHOLD: no change output, miner gets the extra

  tx
end
```

**Key design notes:**
- Uses a dummy change output during UTXO selection so `estimated_fee` accounts for the change output size. Removes it afterwards.
- P2PKH locking script derived from the wallet's private key — no need to fetch source transactions.
- `DUST_THRESHOLD = 1` — BSV has no dust relay limit. Any output >= 1 satoshi is valid.
- Returns `tx` for chaining.

**Spec:** (mock provider returning configurable UTXOs)
- `address`: matches `private_key.public_key.address`
- `balance`: sum of UTXO satoshis, 0 when empty
- `fund`: adds inputs, adds change output when above dust, omits change when below dust, raises InsufficientFundsError with correct amounts, preserves existing outputs, sets source_satoshis and source_locking_script on inputs
- `sign`: delegates to `tx.sign_all`, all inputs get unlocking scripts
- `fund_and_sign`: transaction is both funded and signed, produces valid serialisable transaction

### 7. Wire up Wallet autoloads + RuboCop config

- `lib/bsv/wallet.rb` — autoload hub for `InsufficientFundsError`, `Wallet`
- `lib/bsv-sdk.rb` — add `autoload :Wallet, 'bsv/wallet'`
- `.rubocop.yml` — add `lib/bsv/wallet/**/*` to Metrics exclusions, `spec/bsv/wallet/**/*` to RSpec exclusions

---

## WhatsOnChain API Reference

### `GET /v1/bsv/{network}/address/{address}/unspent`
- Returns: `[{tx_hash, tx_pos, value, height}]`
- `value` is in satoshis (integer)
- `height: 0` = unconfirmed
- No auth required (free tier, 3 req/sec)

### `GET /v1/bsv/{network}/tx/{txid}/hex`
- Returns: plain text raw transaction hex
- No JSON wrapping

### Networks
- `main` = mainnet, `test` = testnet

---

## Commit Sequence

1. `feat(network): add UTXO value object`
2. `feat(network): add ChainProviderError exception class`
3. `feat(network): add WhatsOnChain chain data provider`
4. `chore(network): wire up chain provider autoloads`
5. `feat(wallet): add InsufficientFundsError exception class`
6. `feat(wallet): add Wallet with fund, sign, and balance`
7. `chore(wallet): wire up autoloads and extend RuboCop exclusions`

---

## GitHub Issues

Before implementing, create two HLRs:
- **[HLR] Chain data provider — read transactions and UTXOs from the network** (label: `layer:network`)
- **[HLR] Wallet — fund and sign transactions** (new label: `layer:wallet`)

---

## What This Enables for Attest

With these two capabilities, `bsv-attest` becomes a thin domain layer:

```ruby
# publish(data) pseudocode:
hash = BSV::Primitives::Digest.sha256(data)
tx = Transaction.new
tx.add_output(TransactionOutput.new(satoshis: 0, locking_script: Script.op_return(hash)))
wallet.fund_and_sign(tx)
broadcaster.broadcast(tx)

# verify(data, txid) pseudocode:
tx = provider.fetch_transaction(txid)
expected = BSV::Primitives::Digest.sha256(data)
tx.outputs.any? { |o| op_return_contains_hash?(o, expected) }
```

---

## Verification

```bash
bundle exec rspec spec/bsv/network/   # chain provider specs pass
bundle exec rspec spec/bsv/wallet/    # wallet specs pass
bundle exec rubocop                    # no lint violations
bundle exec rake                       # full suite green
```
