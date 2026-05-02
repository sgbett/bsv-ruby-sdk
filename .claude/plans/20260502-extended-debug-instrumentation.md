# Extended Debug Instrumentation: Sighash, Interpreter, EF Fallback, Ancestry, ProtoWallet

## Context

Following the txid consistency audit (#686), the SDK now has a `BSV.logger` infrastructure. This extends debug instrumentation to the five areas where silent failures cost the most debugging time: sighash preimage construction, script interpreter execution, EF format fallback, BEEF ancestry traversal, and ProtoWallet key derivation.

## Plan

### 1. Sighash preimage instrumentation (`transaction.rb`)

Add logging to `sighash_preimage` showing each BIP-143 component as display-order hex. When a signature fails verification, developers can diff their preimage against a known-good one component by component.

**`sighash_preimage`** (after building buf, before return) — log all 10 components:
```
[Sighash] input=0 type=0x41 hashPrevouts=abc... hashSequence=def...
          scriptCode=76a9... value=100000 hashOutputs=012...
```

**`sighash`** — log the final 32-byte digest.

**`hash_prevouts`**, **`hash_sequence`**, **`hash_outputs`** — no separate logging needed; the preimage log captures the output.

### 2. Script interpreter instrumentation (`interpreter.rb`, `crypto.rb`)

Three levels of logging:

**a) Execution entry/exit** (`execute` method) — log script start, which script (unlock/lock), chunk count, and final result:
```
[Interpreter] === unlock_script (12 chunks) ===
[Interpreter] === lock_script (5 chunks) ===
[Interpreter] final stack: [true] -> success
```

**b) Opcode-level trace** (`execute_opcode`) — log each executed opcode with stack depth. Skip data pushes to reduce noise:
```
[Interpreter] OP_DUP (stack: 2)
[Interpreter] OP_HASH160 (stack: 3)
[Interpreter] OP_EQUALVERIFY (stack: 3)
[Interpreter] OP_CHECKSIG (stack: 2)
```

**c) Signature verification detail** (`verify_checksig` in crypto.rb) — log the sighash type, pubkey fingerprint, and verification result:
```
[Interpreter] CHECKSIG: sighash_type=0x41 pubkey=02ab...cd result=true
```

### 3. EF format fallback (`arc.rb`)

Log when `to_ef_hex` fails and the fallback to raw hex triggers, including which input caused the failure:
```
[ARC] EF serialisation failed: input 2 is missing source_satoshis — falling back to raw hex
```

### 4. BEEF ancestry collection (`transaction.rb`)

**`collect_ancestors_recursive`** — log merkle_path stops and skipped inputs:
```
[Transaction] ancestor: <dtxid> proven at height 800000 (leaf stop)
[Transaction] ancestor: <dtxid> input 1 has no source_transaction (skipped)
```

**`build_beef_bumps`** — log grouping and extraction:
```
[Transaction] BEEF: 5 ancestors, 3 proven across 2 block heights
```

### 5. ProtoWallet key derivation (`proto_wallet.rb`, `key_deriver.rb`)

**`create_signature`** — log counterparty (especially when defaulting to 'anyone'):
```
[ProtoWallet] create_signature: protocol=[2, "certificate signature"] key_id="..." counterparty=anyone
```

**`verify_signature`** — log counterparty, for_self flag, and result:
```
[ProtoWallet] verify_signature: counterparty=<hex> for_self=false result=valid
```

**`derive_private_key` / `derive_public_key`** — log the invoice number and derivation direction:
```
[KeyDeriver] derive_public_key: invoice="2-certificate signature-type serial" for_self=false
```

## Files Modified

| File | Change |
|------|--------|
| `gem/bsv-sdk/lib/bsv/transaction/transaction.rb` | Sighash preimage + ancestry logging |
| `gem/bsv-sdk/lib/bsv/script/interpreter/interpreter.rb` | Execution entry/exit + opcode trace |
| `gem/bsv-sdk/lib/bsv/script/interpreter/operations/crypto.rb` | CHECKSIG detail logging |
| `gem/bsv-sdk/lib/bsv/network/protocols/arc.rb` | EF fallback logging |
| `gem/bsv-sdk/lib/bsv/wallet/proto_wallet.rb` | Sign/verify logging |
| `gem/bsv-sdk/lib/bsv/wallet/proto_wallet/key_deriver.rb` | Derivation path logging |

## Design principles

- All logging uses `BSV.logger&.debug { ... }` — block form, zero cost when nil
- Display-order hex for txids (human-readable), truncated where appropriate
- No logging of private keys, signatures, or secret material — only fingerprints and metadata
- Opcode trace is intentionally verbose (it's debug level) — developers want full trace when they enable it

## Verification

```bash
bundle exec rake spec:sdk   # all existing specs pass
bundle exec rubocop          # lint check
```
