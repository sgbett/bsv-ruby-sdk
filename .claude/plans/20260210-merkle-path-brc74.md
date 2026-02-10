# MerklePath (BRC-74) — Task #18

## Context

Issue #18, sub-task of HLR #11. Implements BRC-74 BSV Unified Merkle Path (BUMP) format for proving transaction inclusion in a block. Prerequisite for BEEF (#17).

Go SDK: `transaction/merklepath.go`

---

## File Structure

```
lib/bsv/transaction/merkle_path.rb       # NEW — MerklePath + PathElement
spec/bsv/transaction/merkle_path_spec.rb  # NEW — specs
lib/bsv/transaction.rb                    # MODIFIED — add autoload :MerklePath
```

---

## Implementation

### Data Structures

**`PathElement`** — simple value object (nested inside `MerklePath`):

```ruby
class PathElement
  attr_reader :offset, :hash, :txid, :duplicate

  def initialize(offset:, hash: nil, txid: false, duplicate: false)
    @offset = offset       # Integer — position in tree level
    @hash = hash           # String (32 bytes binary) or nil if duplicate
    @txid = txid           # Boolean — true if this is a txid
    @duplicate = duplicate # Boolean — true if duplicates sibling
  end
end
```

**`MerklePath`** — the main class:

```ruby
class MerklePath
  attr_reader :block_height, :path

  def initialize(block_height:, path:)
    @block_height = block_height  # Integer
    @path = path                  # Array of Array of PathElement (path[level][index])
  end
end
```

### Binary Format (BRC-74)

```
[BlockHeight: VarInt]
[TreeHeight: 1 byte (uint8)]
For each level (0 to TreeHeight-1):
  [NumLeaves: VarInt]
  For each leaf (sorted by offset):
    [Offset: VarInt]
    [Flags: 1 byte]  — bit 0 (0x01): duplicate, bit 1 (0x02): txid
    if not duplicate:
      [Hash: 32 bytes, internal/wire byte order]
```

### Hash Byte Order

**Critical:** Hashes in the BRC-74 binary format are in **internal (wire) byte order** — the natural SHA256 output. This is the same order used for concatenation in merkle parent computation. Display-order hex strings (like txids or merkle roots shown to humans) are the **reverse** of internal order.

- `from_binary` reads 32 bytes as-is (internal order)
- `to_binary` writes 32 bytes as-is (internal order)
- `compute_root` returns internal-order bytes
- `compute_root_hex` reverses result for display-order hex

### Methods

#### `MerklePath.from_binary(data, offset = 0)` → `[MerklePath, bytes_consumed]`

1. Read block_height as VarInt
2. Read tree_height as uint8
3. For each level (0..tree_height-1):
   - Read num_leaves as VarInt
   - For each leaf: read offset (VarInt), flags (1 byte), hash (32 bytes if not duplicate)
   - Sort level by offset
4. Return `[MerklePath.new(...), total_bytes_consumed]`

#### `MerklePath.from_hex(hex)` → `MerklePath`

Decode hex, call `from_binary`, return just the MerklePath (no offset needed).

#### `#to_binary` → `String`

Write block_height (VarInt) + tree_height (1 byte) + levels.

#### `#to_hex` → `String`

#### `#compute_root(txid = nil)` → `String` (32 bytes, internal order)

1. If txid nil, use first non-nil hash in level 0
2. Special case: single txid in block (1 leaf at level 0) → return txid
3. Build indexed path (Hash of `{ offset → element }` per level)
4. Find leaf matching txid at level 0
5. Walk up the tree for each height:
   - `sibling_offset = (leaf_offset >> height) ^ 1`
   - Look up sibling via `offset_leaf(height, sibling_offset)` (with recursive computation)
   - If duplicate: `parent = SHA256d(working + working)`
   - If sibling offset even: `parent = SHA256d(sibling + working)`
   - If sibling offset odd: `parent = SHA256d(working + sibling)`
6. Return final working hash

**`offset_leaf(level, offset)`** — private helper matching Go's `GetOffsetLeaf`:
- If element exists at `indexed_path[level][offset]`, return it
- If level == 0, return nil
- Otherwise, check `indexed_path[level-1][offset*2]` and `indexed_path[level-1][offset*2+1]`
- If both children exist, compute parent hash and cache

#### `#compute_root_hex(txid_hex = nil)` → `String` (display-order hex)

Convenience: converts txid from display hex → internal bytes, calls `compute_root`, reverses result → display hex.

#### `#combine(other)` → `self` (mutates in place)

1. Validate same block_height
2. Validate same root
3. Merge path elements from `other` into `self`, keyed by offset per level
4. Sort each level by offset

#### Class method: `merkle_tree_parent(left, right)` → `String` (32 bytes)

```ruby
def self.merkle_tree_parent(left, right)
  Primitives::Digest.sha256d(left + right)
end
```

Exposed as a class method for testing against the deterministic vector.

---

## Existing Code to Reuse

| Need | Code | File |
|------|------|------|
| VarInt encode/decode | `VarInt.encode(v)`, `VarInt.decode(data, offset)` | `lib/bsv/transaction/var_int.rb` |
| Double SHA-256 | `Primitives::Digest.sha256d(data)` | `lib/bsv/primitives/digest.rb` |

---

## Test Coverage

### Go SDK test vector (BRC74Hex)

```
fe8a6a0c000c04fde80b0011774f01d26412f0d16ea3f0447be0b5ebec67b0782e321a7a01cbdf7f734e30fde90b02004e53753e3fe4667073063a17987292cfdea278824e9888e52180581d7188d8fdea0b025e441996fc53f0191d649e68a200e752fb5f39e0d5617083408fa179ddc5c998fdeb0b0102fdf405000671394f72237d08a4277f4435e5b6edf7adc272f25effef27cdfe805ce71a81fdf50500262bccabec6c4af3ed00cc7a7414edea9c5efa92fb8623dd6160a001450a528201fdfb020101fd7c010093b3efca9b77ddec914f8effac691ecb54e2c81d0ab81cbc4c4b93befe418e8501bf01015e005881826eb6973c54003a02118fe270f03d46d02681c8bc71cd44c613e86302f8012e00e07a2bb8bb75e5accff266022e1e5e6e7b4d6d943a04faadcf2ab4a22f796ff30116008120cafa17309c0bb0e0ffce835286b3a2dcae48e4497ae2d2b7ced4f051507d010a00502e59ac92f46543c23006bff855d96f5e648043f0fb87a7a5949e6a9bebae430104001ccd9f8f64f4d0489b30cc815351cf425e0e78ad79a589350e4341ac165dbe45010301010000af8764ce7e1cc132ab5ed2229a005c87201c9a5ee15c0f91dd53eff31ab30cd4
```

- Block height: 813706
- Tree height: 12 levels
- Expected root (display hex): `57aab6e6fb1b697174ffb64e062c4728f2ffd33ddcfa02a43b64d8cd29b483b4`
- TXIDs at level 0 (display hex, reversed from wire):
  - Offset 3048: `11774f01d26412f0d16ea3f0447be0b5ebec67b0782e321a7a01cbdf7f734e30` → display: `304e737fdfcb017a1a322e78b067ecebb5e07b44f0a36ed1f01264d2014f7711`
  - Offset 3049 (txid=true): display `d888711d588021e588984e8278a2decf927298173a06737066e43f3e75534e00`
  - Offset 3050 (txid=true): display `98c9c5dd79a18f40837061d5e0395ffb52e700a2689e641d19f053fc9619445e`
  - Offset 3051: duplicate

### MerkleTreeParent test vector

All values in **internal byte order** (as stored in binary, NOT display-reversed):

```
Left:   d6c79a6ef05572f0cb8e9a450c561fc40b0a8a7d48faad95e20d93ddeb08c231
Right:  b1ed931b79056438b990d8981ba46fae97e5574b142445a74a44b978af284f98
Parent: b0d537b3ee52e472507f453df3d69561720346118a5a8c4d85ca0de73bc792be
```

### Tests

**`.merkle_tree_parent` (deterministic):**
- Matches Go SDK vector above

**Binary round-trip:**
- Parse BRC74Hex → MerklePath → to_hex → matches original

**Structure validation:**
- block_height == 813706
- path has 12 levels
- Level 0 has 4 leaves
- Offset 3051 is duplicate
- Offsets 3049, 3050 have txid=true

**Merkle root computation:**
- `compute_root_hex` with first leaf → `57aab6e6fb1b697174ffb64e062c4728f2ffd33ddcfa02a43b64d8cd29b483b4`
- Each txid-flagged leaf produces same root

**Combine:**
- Build two sub-paths manually → combine → root still matches

**Edge cases:**
- Txid not found → raises error
- from_binary returns correct bytes_consumed (for BEEF which reads multiple BUMPs sequentially)

---

## Wiring

Add to `lib/bsv/transaction.rb`:

```ruby
autoload :MerklePath, 'bsv/transaction/merkle_path'
```

---

## Commit

Single commit: `feat(transaction): add MerklePath (BRC-74) for merkle inclusion proofs`

---

## Verification

```bash
bundle exec rspec spec/bsv/transaction/merkle_path_spec.rb
bundle exec rubocop lib/bsv/transaction/merkle_path.rb
bundle exec rake
```
