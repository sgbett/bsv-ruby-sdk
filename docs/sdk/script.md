---
title: Script
nav_order: 2
parent: SDK
---

# Script

The `BSV::Script` module handles Bitcoin script parsing, construction, and execution. Scripts define the spending conditions for transaction outputs.

## Creating Scripts

### From Serialised Data

```ruby
# From hex
script = BSV::Script::Script.from_hex('76a914751e76e8199196d454941c45d1b3a323f1433bd688ac')

# From binary
script = BSV::Script::Script.from_binary(binary_data)

# From ASM (human-readable opcodes)
script = BSV::Script::Script.from_asm(
  'OP_DUP OP_HASH160 751e76e8199196d454941c45d1b3a323f1433bd6 OP_EQUALVERIFY OP_CHECKSIG'
)
```

### From Chunks

```ruby
script = BSV::Script::Script.from_chunks([
  BSV::Script::Chunk.new(opcode: BSV::Script::Opcodes::OP_DUP),
  BSV::Script::Chunk.new(opcode: BSV::Script::Opcodes::OP_HASH160),
  BSV::Script::Chunk.new(opcode: 0x14, data: pubkey_hash),
  BSV::Script::Chunk.new(opcode: BSV::Script::Opcodes::OP_EQUALVERIFY),
  BSV::Script::Chunk.new(opcode: BSV::Script::Opcodes::OP_CHECKSIG)
])
```

## Script Templates

Templates provide convenient constructors for common script patterns.

### P2PKH (Pay to Public Key Hash)

The most common script type. Locks funds to a public key hash (address).

```ruby
pubkey_hash = private_key.public_key.hash160  # 20 bytes

# Locking script: OP_DUP OP_HASH160 <hash> OP_EQUALVERIFY OP_CHECKSIG
lock = BSV::Script::Script.p2pkh_lock(pubkey_hash)

# Unlocking script: <sig> <pubkey>
unlock = BSV::Script::Script.p2pkh_unlock(signature_bytes, pubkey_bytes)
```

### P2PK (Pay to Public Key)

Locks funds directly to a public key (no hashing).

```ruby
pubkey = private_key.public_key.compressed  # 33 bytes

# Locking script: <pubkey> OP_CHECKSIG
lock = BSV::Script::Script.p2pk_lock(pubkey)

# Unlocking script: <sig>
unlock = BSV::Script::Script.p2pk_unlock(signature_bytes)
```

### Multisig (m-of-n)

Requires m signatures from n public keys.

```ruby
keys = [alice_pubkey, bob_pubkey, carol_pubkey]  # compressed public key bytes

# Locking script: OP_2 <key1> <key2> <key3> OP_3 OP_CHECKMULTISIG
lock = BSV::Script::Script.p2ms_lock(2, keys)  # 2-of-3

# Unlocking script: OP_0 <sig1> <sig2>
unlock = BSV::Script::Script.p2ms_unlock(sig1, sig2)
```

### OP_RETURN (Data Carrier)

Store arbitrary data on-chain. The output carries zero satoshis.

```ruby
# Single data item
script = BSV::Script::Script.op_return('hello world'.b)

# Multiple data items (push each separately)
script = BSV::Script::Script.op_return(
  'app-prefix'.b,
  'payload'.b,
  [Time.now.to_i].pack('V')
)
```

## Builder Pattern

For custom scripts, use the builder:

```ruby
script = BSV::Script::Script.builder
  .push_op(:OP_DUP)
  .push_op(:OP_HASH160)
  .push_data(pubkey_hash)
  .push_op(:OP_EQUALVERIFY)
  .push_op(:OP_CHECKSIG)
  .build
```

## Serialisation

```ruby
script.to_hex       # hex string
script.to_binary    # raw bytes
script.to_asm       # "OP_DUP OP_HASH160 751e76... OP_EQUALVERIFY OP_CHECKSIG"
script.length       # byte length of the serialised script
```

## Type Detection

Scripts can be classified by their pattern:

```ruby
script.p2pkh?       # Pay to Public Key Hash
script.p2pk?        # Pay to Public Key
script.multisig?    # m-of-n Multisig
script.op_return?   # OP_RETURN (data carrier)
script.p2sh?        # Pay to Script Hash (read-only detection)

# General classification
script.type
#=> 'pubkeyhash', 'pubkey', 'multisig', 'nulldata',
#   'scripthash', 'empty', or 'nonstandard'
```

{: .note }
> **P2SH Detection**
>
> P2SH scripts are detected for completeness (e.g. when parsing historical
> transactions), but BSV does not support P2SH execution. No P2SH
> constructors are provided.

## Data Extraction

Extract structured data from known script types:

```ruby
# P2PKH: extract the 20-byte public key hash
script.pubkey_hash    #=> "\x75\x1e\x76..." or nil

# P2SH: extract the 20-byte script hash
script.script_hash    #=> "\xa9\x14..." or nil

# OP_RETURN: extract data items
script.op_return_data #=> ["\x68\x65\x6c\x6c\x6f"] or nil

# Addresses (for P2PKH scripts)
script.addresses                        # mainnet
script.addresses(network: :testnet)     # testnet
```

## Working with Chunks

Scripts are composed of chunks — either opcodes or data pushes. Chunks are lazily parsed on first access.

```ruby
chunks = script.chunks

chunks.each do |chunk|
  if chunk.data
    puts "DATA: #{chunk.data.unpack1('H*')} (#{chunk.data.bytesize} bytes)"
  else
    puts "OP: #{BSV::Script::Opcodes.name_for(chunk.opcode)}"
  end
end
```

## BIP-276 Text Encoding

`Script::BIP276` implements the [BIP-276](https://github.com/moneybutton/bips/blob/master/bip-0276.mediawiki) text-sharing format, which provides a compact, checksummed way to pass raw scripts and script templates between BSV tools as human-readable strings.

The encoded form is `<prefix>:<version-byte><network-byte><hex-payload><checksum>`, where the checksum is the first four bytes of double-SHA-256 over the full preimage.

```ruby
# Encode a script's binary form
encoded = BSV::Script::BIP276.encode(
  script.to_binary,
  prefix:  BSV::Script::BIP276::PREFIX_SCRIPT,   # 'bitcoin-script'
  network: BSV::Script::BIP276::NETWORK_MAINNET, # 1
  version: BSV::Script::BIP276::CURRENT_VERSION  # 1
)
#=> "bitcoin-script:010176a914...6f0cd86a"

# Decode — returns an immutable Result with :prefix, :version, :network, :data
result = BSV::Script::BIP276.decode(encoded)
result.prefix   #=> "bitcoin-script"
result.version  #=> 1
result.network  #=> 1
result.data     #=> binary script bytes
```

Convenience helpers lock the prefix:

```ruby
# Script round-trip
encoded = BSV::Script::BIP276.encode_script(binary_script)
result  = BSV::Script::BIP276.decode_script(encoded)

# Template round-trip
encoded = BSV::Script::BIP276.encode_template(binary_template)
result  = BSV::Script::BIP276.decode_template(encoded)
```

**Field order note:** the two header bytes are `<version><network>` — version first, then network. This matches the BIP-276 specification and the Go SDK reference implementation. The Python SDK has these two fields reversed, a known bug that is invisible when both values are `0x01` (the default) but produces incorrect output for testnet or non-default versions. See `spec/bsv/script/bip276_spec.rb` for Go SDK cross-SDK conformance vectors that prove the correct byte order.

## Script Interpreter

Verify that an unlocking script satisfies a locking script:

```ruby
BSV::Script::Interpreter.verify(
  tx: transaction,
  input_index: 0,
  unlock_script: input.unlocking_script,
  lock_script: input.source_locking_script,
  satoshis: input.source_satoshis
)
#=> true or false
```

The interpreter supports post-Genesis BSV opcodes and enforces FORKID sighash validation.
