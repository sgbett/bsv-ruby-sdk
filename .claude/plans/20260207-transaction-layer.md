# BSV Ruby SDK — Transaction Layer

## Goal

Implement `BSV::Transaction` — the third layer in the SDK dependency chain (Primitives → Script → Transaction). This enables the primary attestation use case: create a transaction with P2PKH inputs funded by UTXOs, an OP_RETURN output, a change output, sign the inputs, and serialise for broadcast.

## Key Technical Decisions

- **VarInt as a stateless module.** `encode` returns binary bytes, `decode` returns `[value, bytes_consumed]`. Placed in the `Transaction` namespace since it's only used here.
- **Input stores source UTXO metadata directly.** `source_locking_script` and `source_satoshis` on `TransactionInput`, rather than carrying full parent transactions (simpler than Go SDK's `SourceTransaction` approach).
- **Sighash is a method on Transaction.** `sighash_preimage(input_index, sighash_type)` needs access to all inputs/outputs, so it belongs on `Transaction`. Only `SIGHASH_ALL|FORKID` (0x41) initially — raises on unsupported types.
- **P2PKH signing as a convenience method.** `sign(input_index, private_key)` computes sighash, signs, sets unlocking script. Avoids Go SDK's `UnlockingScriptTemplate` interface until needed.
- **Fee estimation via satoshis-per-byte.** Unsigned P2PKH inputs budgeted at ~148 bytes. Go SDK's `FeeModel` interface deferred.
- **Deserialisation included.** Parsing raw transactions from hex is needed for test vectors and costs little to implement alongside serialisation.
- **Txid stored in internal byte order** (same as wire format). Display-order conversion via explicit helpers (`txid_from_hex`, `txid_hex`).

## File Structure

```
lib/bsv/
  transaction.rb                    # autoload hub (replace empty stub)
  transaction/
    var_int.rb                      # VarInt encoding/decoding
    transaction_input.rb            # TransactionInput class
    transaction_output.rb           # TransactionOutput class
    sighash.rb                      # Sighash flag constants
    transaction.rb                  # Transaction class (serialise, parse, sign, txid, fee)

spec/bsv/transaction/
    var_int_spec.rb
    transaction_input_spec.rb
    transaction_output_spec.rb
    sighash_spec.rb
    transaction_spec.rb
```

## Build Order (6 steps)

### 1. `VarInt` — Bitcoin variable-length integer encoding

**File:** `lib/bsv/transaction/var_int.rb`

Module with two module functions:
- `encode(value)` → binary string
- `decode(data, offset = 0)` → `[value, bytes_consumed]`

Encoding: 0–252 = 1 byte, 253–65535 = `0xFD` + 2 LE, 65536–2³²-1 = `0xFE` + 4 LE, 2³²+ = `0xFF` + 8 LE.

### 2. `TransactionOutput` — output data + serialisation

**File:** `lib/bsv/transaction/transaction_output.rb`

- `attr_reader :satoshis, :locking_script`
- `initialize(satoshis:, locking_script:)`
- `to_binary` — 8-byte LE satoshis + varint script length + script bytes
- `self.from_binary(data, offset = 0)` → `[output, bytes_consumed]`

### 3. `TransactionInput` — input data + serialisation

**File:** `lib/bsv/transaction/transaction_input.rb`

- `attr_reader :prev_tx_id, :prev_tx_out_index, :sequence`
- `attr_accessor :unlocking_script, :source_satoshis, :source_locking_script`
- `initialize(prev_tx_id:, prev_tx_out_index:, unlocking_script: nil, sequence: 0xFFFFFFFF)`
- `to_binary` — txid(32) + vout(4 LE) + varint scriptlen + scriptsig + sequence(4 LE)
- `self.from_binary(data, offset = 0)` → `[input, bytes_consumed]`
- `self.txid_from_hex(hex)` — converts display-order hex to internal byte order
- `outpoint_binary` — 36-byte outpoint for sighash

### 4. `Sighash` — flag constants

**File:** `lib/bsv/transaction/sighash.rb`

Constants: `ALL` (0x01), `NONE` (0x02), `SINGLE` (0x03), `ANYONE_CAN_PAY` (0x80), `FORK_ID` (0x40), `ALL_FORK_ID` (0x41).

### 5. `Transaction` — main class

**File:** `lib/bsv/transaction/transaction.rb`

Construction:
- `initialize(version: 1, lock_time: 0)` with `@inputs = []`, `@outputs = []`
- `add_input(input)`, `add_output(output)`

Serialisation:
- `to_binary`, `to_hex`, `self.from_binary(data)`, `self.from_hex(hex)`

Transaction ID:
- `txid` → 32-byte binary (display order)
- `txid_hex` → 64-char hex

Sighash (BIP-143 with FORKID):
- `sighash_preimage(input_index, sighash_type = ALL_FORK_ID)` — 10-component preimage
- `sighash(input_index, sighash_type)` — SHA-256d of preimage

Signing:
- `sign(input_index, private_key, sighash_type = ALL_FORK_ID)` — signs and sets unlocking script
- `sign_all(private_key, sighash_type = ALL_FORK_ID)` — signs all unsigned inputs

Fee:
- `estimated_fee(satoshis_per_byte: 0.5)` — estimates fee accounting for unsigned input sizes
- `total_input_satoshis`, `total_output_satoshis`

### 6. Wire up autoloads + RuboCop config

Update `lib/bsv/transaction.rb` with autoloads. Add `lib/bsv/transaction/**/*` to RuboCop metric exclusions (matching existing primitives/script pattern). Add spec exclusions too.

## Test Vectors

### Sighash (from Go SDK `signaturehash_test.go`)

**Vector 1 — 1 Input 2 Outputs:**
- Unsigned tx: `010000000193a35408...00000000`
- Input 0, prev satoshis: 100000000, prev script: `76a914c0a3c167...88ac`
- Expected preimage: `010000007ced5b2e...41000000`
- Expected sighash: `be9a42ef2e2dd7ef02cd631290667292cbbc5018f4e3f6843a8f4c302a2111b1`

**Vector 2 — 2 Inputs 3 Outputs (index 0):**
- Expected sighash: `8b15eecfb6d5e727485e19797b5d1829e0630e8b43c806707685238e28a3194c`

**Vector 3 — 2 Inputs 3 Outputs (index 1):**
- Expected sighash: `7b72c355a2714a5039d97fbd5eee792099b0eab4bf07d2e5bfcfc3309f81badb`

### Serialisation
- Parse Go SDK test transaction hex, verify structure, round-trip

### Integration
- Full attestation flow: construct tx with P2PKH input + OP_RETURN output + change output, sign, verify txid

## Existing Building Blocks

- `BSV::Primitives::Digest.sha256d(data)` — double SHA-256
- `BSV::Primitives::PrivateKey#sign(hash)` → `Signature` (RFC 6979, low-S)
- `BSV::Primitives::Signature#to_der` — DER encoding
- `BSV::Script::Script.p2pkh_unlock(sig_der, pubkey)` — unlocking script
- `BSV::Script::Script.op_return(*data)` — OP_RETURN script
- `BSV::Script::Script#to_binary` / `.from_binary(bytes)` — script serialisation

## Commit Sequence

1. `feat(transaction): add VarInt encoding and decoding`
2. `feat(transaction): add TransactionOutput with binary serialisation`
3. `feat(transaction): add TransactionInput with binary serialisation`
4. `feat(transaction): add Sighash flag constants`
5. `feat(transaction): add Transaction class with serialisation, sighash, signing, and fee estimation`
6. `chore(transaction): wire up autoloads and update RuboCop config`

## Deferred Work

Create a single HLR issue covering deferred transaction capabilities:
- BEEF format serialisation/deserialisation (BRC-95)
- Merkle path verification and SPV proofs
- Additional SIGHASH types beyond ALL|FORKID
- `UnlockingScriptTemplate` pattern for custom script signing

## Verification

```bash
bundle exec rspec spec/bsv/transaction/   # all transaction specs pass
bundle exec rubocop                        # no lint violations
bundle exec rake                           # full suite green
```
