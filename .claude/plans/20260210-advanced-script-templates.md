# Advanced Script Templates — Task #22

## Context

Issue #22, sub-task of HLR #8. Adds template constructors for P2PK, P2SH, and bare multisig (P2MS) script types. Currently only `p2pkh_lock`, `p2pkh_unlock`, and `op_return` exist.

The "custom locking scripts" acceptance criterion is already met by the Builder API (#23).

---

## File Structure

```
lib/bsv/script/script.rb        # MODIFIED — add template class methods
spec/bsv/script/script_spec.rb  # MODIFIED — add template tests
```

No new files needed. All templates follow the existing pattern as class methods on `Script`.

---

## Implementation

All methods added to the `# --- Templates ---` section of `lib/bsv/script/script.rb`, using the existing private `encode_push_data` helper.

### 1. P2PK (Pay to Public Key)

`<pubkey> OP_CHECKSIG`

```ruby
def self.p2pk_lock(pubkey_bytes)
  raise ArgumentError, 'pubkey must be 33 or 65 bytes' unless [33, 65].include?(pubkey_bytes.bytesize)

  buf = encode_push_data(pubkey_bytes)
  buf << [Opcodes::OP_CHECKSIG].pack('C')
  new(buf)
end

def self.p2pk_unlock(signature_der)
  new(encode_push_data(signature_der))
end
```

### 2. P2SH (Pay to Script Hash)

Lock: `OP_HASH160 <20-byte script hash> OP_EQUAL`

Unlock: `<push_data...> <serialised redeem_script>` — push items (typically signatures) followed by the serialised redeem script.

```ruby
def self.p2sh_lock(script_hash)
  raise ArgumentError, 'script_hash must be 20 bytes' unless script_hash.bytesize == 20

  buf = [Opcodes::OP_HASH160].pack('C')
  buf << encode_push_data(script_hash)
  buf << [Opcodes::OP_EQUAL].pack('C')
  new(buf)
end

def self.p2sh_unlock(redeem_script, *push_items)
  buf = ''.b
  push_items.each { |item| buf << encode_push_data(item.b) }
  buf << encode_push_data(redeem_script.to_binary)
  new(buf)
end
```

`p2sh_unlock` takes a `Script` (the redeem script) and zero or more binary push items (typically signatures). The redeem script is serialised and pushed last, matching Bitcoin consensus.

### 3. P2MS (Bare Multisig)

Lock: `OP_M <pubkey1> <pubkey2> ... OP_N OP_CHECKMULTISIG`

Unlock: `OP_0 <sig1> <sig2> ...` — OP_0 for the CHECKMULTISIG off-by-one bug.

```ruby
def self.p2ms_lock(m, pubkeys)
  n = pubkeys.length
  raise ArgumentError, 'm must be between 1 and n' unless m >= 1 && m <= n
  raise ArgumentError, 'n must be <= 16' unless n <= 16

  buf = [Opcodes::OP_1 + m - 1].pack('C')
  pubkeys.each { |pk| buf << encode_push_data(pk.b) }
  buf << [Opcodes::OP_1 + n - 1].pack('C')
  buf << [Opcodes::OP_CHECKMULTISIG].pack('C')
  new(buf)
end

def self.p2ms_unlock(*signatures)
  buf = [Opcodes::OP_0].pack('C')
  signatures.each { |sig| buf << encode_push_data(sig.b) }
  new(buf)
end
```

M and N encoded as OP_1 (0x51) through OP_16 (0x60). Validates M <= N and N <= 16.

---

## Test Strategy

### P2PK tests

- `p2pk_lock` with 33-byte compressed pubkey produces correct script
- `p2pk_lock` with 65-byte uncompressed pubkey works
- `p2pk_lock` raises on wrong-length pubkey
- `p2pk_lock` output passes `p2pk?` predicate
- `p2pk_unlock` wraps signature in push data
- Round-trip: chunks parse correctly

### P2SH tests

- `p2sh_lock` produces `OP_HASH160 <hash> OP_EQUAL`
- `p2sh_lock` raises on wrong-length hash
- `p2sh_lock` output passes `p2sh?` predicate
- `p2sh_unlock` pushes items then serialised redeem script
- Round-trip with `script_hash` extraction: `p2sh_lock(hash).script_hash == hash`

### P2MS tests

- `p2ms_lock` produces `OP_2 <key1> <key2> <key3> OP_3 OP_CHECKMULTISIG` for 2-of-3
- `p2ms_lock` output passes `multisig?` predicate
- `p2ms_lock` raises when m > n
- `p2ms_lock` raises when n > 16
- `p2ms_unlock` produces `OP_0 <sig1> <sig2>`
- 1-of-1 multisig works (edge case)

### Backward compatibility

All existing tests pass unchanged.

---

## Commit

Single commit: `feat(script): add P2PK, P2SH, and P2MS script templates`

---

## Verification

```bash
bundle exec rspec spec/bsv/script/script_spec.rb
bundle exec rubocop lib/bsv/script/script.rb
bundle exec rake
```
