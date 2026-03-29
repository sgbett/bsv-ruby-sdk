# Copilot Code Review Instructions

## Project Context

bsv-ruby-sdk is a Ruby gem implementing the BSV Blockchain protocol — keys, scripts, transactions, BEEF serialisation, and the BRC-100 wallet interface. It is a **funds-handling library**: applications use it to construct, sign, and broadcast Bitcoin transactions. Any bug in transaction construction, signing, key derivation, or script generation can cause **permanent, irrecoverable loss of funds**.

Key architecture:
- `BSV::Primitives` — secp256k1 curve, ECDSA (RFC 6979), AES-256-GCM, ECDH, BRC-42 key derivation, Schnorr ZKP, Shamir's SSS
- `BSV::Script` — script parsing, templates (P2PKH, PushDrop, RPuzzle, OpCat), full interpreter
- `BSV::Transaction` — transaction building, BIP-143 sighash, BEEF (BRC-62/95/96), MerklePath (BRC-74), SPV verification
- `BSV::Wallet` — BRC-100 wallet interface (28 methods), ProtoWallet (crypto), WalletClient (transactions + storage)
- `BSV::Auth` — BRC-31 mutual authentication with nonce-based challenges
- All cryptography uses Ruby stdlib OpenSSL — no external crypto gems

## Threat Model

**Funds at risk** is the guiding principle. Any code path that could cause a user to lose satoshis is critical.

Primary threats:
- **Incorrect transaction construction**: wrong sighash, malformed scripts, invalid BEEF — produces transactions that miners reject (funds stuck in unspendable UTXOs)
- **Key derivation errors**: wrong child key derived for a payment — funds sent to an address nobody controls
- **Signing bugs**: wrong hash signed, signature over wrong data — invalid transactions or signatures that reveal private key material (nonce reuse)
- **BEEF/SPV verification bypass**: accepting invalid merkle proofs — wallet accepts counterfeit transactions as valid
- **Wire protocol deserialisation**: malformed binary input from untrusted peers could crash the wallet or corrupt state

Secondary threats:
- **Private key leakage**: keys, shared secrets, or keyrings exposed in return values, error messages, or storage
- **Nonce reuse in ECDSA**: two signatures with the same k-value over different messages reveals the private key
- **Certificate subject confusion**: storing certificates with the wrong identity key enables impersonation
- **Authentication bypass**: forged handshakes or replayed messages in the auth module

## Review Focus Areas

### Transaction Construction (Critical — funds at risk)

- **Sighash computation**: `Transaction#sighash` implements BIP-143 with BSV FORKID. Any error in the preimage (wrong field order, wrong endianness, missing FORKID byte) produces an invalid signature. The transaction broadcasts but the UTXO becomes permanently unspendable.
- **Input/output wiring**: `source_satoshis` and `source_locking_script` on `TransactionInput` must match the actual UTXO being spent. Mismatches cause sighash to compute over wrong data → invalid signature → unspendable.
- **Fee calculation**: `estimated_size` and `compute_fee` determine how much the miner gets. Underestimation → transaction rejected. Overestimation → overpaid fees (funds lost to miner). Check rounding direction (should always `ceil`, never `floor`).
- **Change output handling**: `Transaction#fee` distributes change. Verify that change is never negative, never below dust threshold (1 sat), and that the change address is derived from the wallet's own key (not an attacker-controlled address).
- **Output randomisation**: `WalletClient#shuffle_outputs` reorders outputs after construction. Verify that `store_tracked_outputs` uses the post-shuffle index for outpoints, not the pre-shuffle array position (bug previously found and fixed).

### Key Derivation (Critical — funds at risk)

- **BRC-42 child keys**: `PrivateKey#derive_child` and `PublicKey#derive_child` use ECDH + HMAC-SHA256. The derived key must match across sender and receiver — if not, funds are sent to an unrecoverable address.
- **Invoice number format**: `KeyDeriver#compute_invoice_number` produces `"#{level}-#{name}-#{key_id}"`. Any deviation from the reference SDKs (ts-sdk, go-sdk) breaks cross-SDK compatibility — payments between SDKs fail silently.
- **Counterparty resolution**: `KeyDeriver#resolve_counterparty` dispatches 'self' → own pubkey, 'anyone' → PrivateKey(1).pubkey, hex string → PublicKey.from_hex. Confusion here means deriving the wrong key → funds lost.
- **BRC-29 payment derivation**: `internalize_payment` uses `protocol_id: [2, '3241645161d8']` and `key_id: "#{prefix} #{suffix}"`. These must match the ts-sdk's `BasicBRC29` module exactly, or wallet payment internalization silently rejects valid payments.

### ECDSA Signing (Critical — private key at risk)

- **RFC 6979 nonce**: `ECDSA#sign` uses deterministic nonce generation. Any deviation from RFC 6979 (wrong HMAC inputs, wrong truncation, wrong loop termination) could produce a biased or repeated k-value. Two signatures with the same k over different messages → private key fully recoverable.
- **Low-S normalisation**: Signatures must be low-S normalised (BIP-62 rule 5). High-S signatures are valid but non-standard — miners may reject them, leaving funds stuck.
- **DER encoding**: `Signature#to_der` must produce strict BIP-66 DER. Malformed DER → transaction rejected → funds stuck.

### Script Interpreter (High — consensus divergence)

- **Opcode correctness**: The interpreter must match BSV consensus rules exactly. An opcode that behaves differently from the network means scripts that the SDK considers valid may be rejected by miners (or vice versa). This is a consensus-level bug.
- **Post-Genesis semantics**: BSV restored opcodes (OP_MUL, OP_CAT, OP_SPLIT, etc.) and removed size limits. The interpreter must enforce post-Genesis rules, not pre-Genesis.
- **OP_RETURN handling**: OP_RETURN as the first opcode means the output is provably unspendable. The interpreter must not try to execute beyond OP_RETURN in a locking script.

### BEEF / SPV Verification (High — counterfeit transaction risk)

- **Merkle path verification**: `MerklePath#compute_root` must correctly recompute the block merkle root from the transaction's position. A bug here means accepting transactions that were never mined.
- **BEEF parsing**: `Beef.from_binary` processes untrusted binary data. Malformed BEEF could cause out-of-bounds reads, incorrect transaction wiring, or acceptance of invalid ancestry proofs.
- **Source transaction wiring**: When parsing BEEF, `source_transaction` must be correctly linked to each input. Incorrect wiring means the sighash is computed against the wrong source output → invalid signatures.

### Wire Protocol Deserialisation (High — crash/corruption from untrusted input)

- **VarInt decoding**: `Reader#read_varint` and `read_signed_varint` process untrusted binary. Verify bounds checking in `require_bytes`, especially for the -1 sentinel (MaxUint64).
- **Length-prefixed reads**: Any `read_bytes(n)` where `n` comes from the wire must be validated as non-negative and within remaining buffer bounds. A negative length causes `byteslice` to return nil → crash.
- **Counterparty dispatch**: `read_counterparty` dispatches on the first byte (0=nil, 11='self', 12='anyone', 0x02/0x03=pubkey). Any other byte value must not silently produce garbage.
- **String encoding**: `force_encoding('UTF-8')` does not validate UTF-8 validity. Invalid byte sequences create strings that may cause downstream encoding exceptions.

### Wallet Storage (Medium — state corruption)

- **Outpoint format**: Outpoints are stored as `"#{txid}.#{index}"`. Verify that `txid` is always 64-char lowercase hex and `index` is a non-negative integer. Malformed outpoints break output lookup and spending.
- **Certificate subject pinning**: `acquire_via_issuance` must pin `subject` to the wallet's own identity key, never accepting it from a remote certifier response.
- **Basket/label/tag validation**: All user-facing names must be validated per BRC-100 rules (length, character set, reserved prefixes) before storage.

### Encryption / HMAC (Medium — data confidentiality)

- **AES-256-GCM IV**: `SymmetricKey#encrypt` generates a 32-byte random IV per encryption. Verify the IV is never reused (would completely break GCM confidentiality and authentication).
- **Constant-time HMAC comparison**: `ProtoWallet#secure_compare` must use constant-time comparison. The early-return on length mismatch is acceptable (HMAC length is always 32 bytes, not secret).
- **Key linkage proofs**: `reveal_counterparty_key_linkage` generates a Schnorr ZKP. Verify the proof is encrypted for the verifier using protocol-derived keys, not raw ECDH.

## What NOT to Flag

- **Ruby 2.7 compatibility warnings**: The gem targets Ruby >= 2.7. Pattern matching, `Hash#except`, endless methods, and `Data.define` are intentionally avoided.
- **`instance_variable_set` in WalletClient**: Used to tag TransactionOutputs with their spec for post-shuffle outpoint tracking. This is intentional.
- **`is_authenticated` naming**: The `is_` prefix is the BRC-100 wire protocol method name and cannot be renamed.
- **`MemoryStore` thread safety**: MemoryStore is documented as test-only. Production adapters are the caller's responsibility.
- **`'anyone'` counterparty in signatures**: BRC-43 explicitly supports `'anyone'` for publicly verifiable signatures. The derived key still requires the signer's private key.
- **Auth/Peer TOFU model**: BRC-31 is Trust-on-First-Use by design. The responder marking `is_authenticated = true` before initiator proves key possession matches all reference SDKs.
- **No replay protection on general auth messages**: BRC-31 delegates replay protection to the application layer, same as TLS. All reference SDKs have the same design.
- **`Gemfile.lock` not committed**: Standard practice for gems — consumers resolve their own dependency tree.

## Style

- Be specific: cite file paths and line numbers.
- Lead with **funds impact**, not description. "This causes funds loss because..." not "This doesn't follow best practice because..."
- Provide fix recommendations with code, not just problem statements.
- Skip cosmetic issues, style preferences, and general best practices unless they have a funds-at-risk or key-leakage implication.
- Focus on the diff, not the entire codebase. Pre-existing patterns are not new findings.
