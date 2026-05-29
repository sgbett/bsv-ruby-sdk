# Testnet integration

The SDK includes an integration test suite that exercises the full transaction
lifecycle against the live BSV testnet — key derivation, transaction building,
signing, broadcasting via Arcade (GorillaPool), status polling, and round-trip
serialisation verification via WhatsOnChain.

These tests are tagged `:testnet` and skipped by default. They require a funded
testnet wallet.

## Prerequisites

1. **Generate a testnet key**

    ```ruby
    key = BSV::Primitives::PrivateKey.generate
    puts key.to_wif(network: :testnet)  # => cXxx...
    puts key.public_key.address(network: :testnet)  # => mXxx...
    ```

2. **Fund the address** with at least 3,000 satoshis from the
   [WitnessOnChain faucet](https://witnessonchain.com/faucet/tbsv).

3. **Verify on the explorer** at
   [test.whatsonchain.com](https://test.whatsonchain.com/).

## Running

```bash
BSV_TESTNET_WIF='cXxx...' bundle exec rspec --tag testnet
```

Optionally override the Arcade endpoint:

```bash
BSV_TESTNET_ARCADE_URL='https://testnet.arcade.gorillapool.io' \
  BSV_TESTNET_WIF='cXxx...' \
  bundle exec rspec --tag testnet
```

## What the tests cover

### Wallet setup

Derives a testnet address from the WIF, fetches UTXOs from WhatsOnChain, and
verifies the address format and UTXO availability.

### P2PKH transfer

Builds a pay-to-public-key-hash transaction sending the dust limit (546 sats)
back to the same address, with change. Signs, broadcasts via Arcade, and confirms
the status response contains the expected status.

```ruby
# The core flow, simplified
tx = BSV::Transaction::Transaction.new
tx.add_input(input)
tx.add_output(payment)
tx.add_output(change)
tx.sign_all(private_key)

response = arcade.call(:broadcast, tx)
response.http_success?       # => true
response.data['status']      # => "submitted"
```

### OP_RETURN attestation

Broadcasts a transaction with a zero-satoshi `OP_RETURN` output containing a
timestamped string. Proves the SDK correctly constructs data-carrying
transactions that ARC accepts.

```ruby
data_output = BSV::Transaction::TransactionOutput.new(
  satoshis: 0,
  locking_script: BSV::Script::Script.op_return('my attestation data')
)
```

### Round-trip serialisation

Broadcasts a transaction, waits for WhatsOnChain to index it, fetches the raw
hex back, and verifies it matches the original byte-for-byte. Then parses the
fetched hex back into a `Transaction` object and confirms the txid is identical.

This catches any serialisation drift between our encoder and what the network
actually accepted.

## Design notes

- Each test group consumes a UTXO. Change always returns to the same address,
  so the wallet stays funded across repeated runs.
- Fee estimation uses a simple size-based calculation at 0.5 sat/byte.
- The `TestnetWallet` helper module (in `spec/support/`) wraps WhatsOnChain's
  testnet API for UTXO fetching and raw transaction retrieval. It is not shipped
  in the gem.
