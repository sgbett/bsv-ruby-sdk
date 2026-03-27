---
description: Analyses the current SDK codebase and compares it semantically to the BSV reference SDKs (Go, TypeScript, Python) to assess coverage, alignment, and novelty. Use when the user asks to "check divergence", "compare against reference SDKs", "how does our SDK compare", or "/divergence-analysis".
---

# SDK Divergence Analysis

Performs a semantic comparison of the current BSV Ruby SDK against the three official reference implementations: [go-sdk](https://github.com/bitcoin-sv/go-sdk), [ts-sdk](https://github.com/bitcoin-sv/ts-sdk), and [py-sdk](https://github.com/bitcoin-sv/py-sdk).

## Process

Use `ultrathink` for the analysis and synthesis steps.

### 1. Inventory the Ruby SDK (subagent)

Launch an **Explore** subagent to produce a complete semantic inventory of the Ruby SDK:

- Every module, class, and public method under `lib/`
- Constants and their values
- Algorithms implemented (RFC 6979, DER, Base58Check, BIP-143, etc.)
- What is scaffolded but empty vs fully implemented
- Spec coverage summary from `spec/`

### 2. Inventory the reference SDKs (3 parallel subagents)

Launch three **general-purpose** subagents in parallel, one per reference SDK. Each should fetch the repository from GitHub and analyse:

- Module/package/namespace organisation
- Key classes/types and their public methods
- Algorithms implemented (RFC 6979, BIP-32, BIP-39, Schnorr, ECIES, BEEF, etc.)
- Script templates available (P2PKH, RPuzzle, PushDrop, etc.)
- Higher-level features (BRC-42/77/78, wallet interface, broadcasters, SPV, overlay tools)
- Architecture pattern and design decisions

**Reference SDK repositories:**
- **TypeScript:** https://github.com/bitcoin-sv/ts-sdk (also check https://github.com/bsv-blockchain/ts-sdk)
- **Go:** https://github.com/bitcoin-sv/go-sdk (also check https://github.com/bsv-blockchain/go-sdk)
- **Python:** https://github.com/bitcoin-sv/py-sdk (also check https://github.com/bsv-blockchain/py-sdk)

### 3. Produce the comparison

Once all four inventories are complete, synthesise into a structured report with the following sections:

#### 3a. Coverage Matrix

A markdown table with these columns: **Layer | Component | TS SDK | Go SDK | Py SDK | Ruby SDK**

Use these status indicators:
- **Yes** (or details) = fully implemented
- **Partial** = scaffolded or incomplete
- **No** = not present

Group rows by layer:
- **Primitives** (curve, hashing, Base58, ECDSA, keys, symmetric encryption, ECDH, key derivation, Shamir, Schnorr)
- **Compat** (BIP-32, BIP-39, ECIES, BSM)
- **Script** (opcodes, script parsing, templates, interpreter)
- **Transaction** (build/serialise, sighash, signing, fees, BEEF, EF, MerklePath, SPV, broadcasters, chain trackers, fee models)
- **Higher-level** (BRC-42/77/78, wallet interface, auth, overlay, identity, storage)

#### 3b. Quantitative Assessment

Estimate what percentage of the reference SDK surface area the Ruby SDK covers. Break down by layer.

#### 3c. Alignment Assessment

For each implemented component, note whether the Ruby SDK's semantics faithfully match the reference SDKs or diverge. Flag any differences in:
- API shape (method names, signatures, return types)
- Algorithm correctness (tested against reference vectors?)
- Architectural decisions (e.g. OpenSSL vs custom curve)

#### 3d. Novelty Assessment

Identify anything in the Ruby SDK that is **not** a direct translation of a reference SDK feature. This includes:
- Novel classes, methods, or algorithms
- Different architectural patterns
- Ruby-specific additions

Be explicit: state whether anything novel exists or not.

#### 3e. Gap Analysis (prioritised)

List what's missing, organised into tiers:

- **Tier 1 — Needed for real-world use** (BEEF, SPV, broadcasters, chain trackers, fee models)
- **Tier 2 — Expected by the ecosystem** (script interpreter, ECDH, BRC-42, BRC-77/78, symmetric encryption)
- **Tier 3 — Compatibility** (BIP-32/39, ECIES, BSM, Shamir, RPuzzle, PushDrop)

#### 3f. Summary

A concise paragraph summarising the overall state: how far along the Ruby SDK is, whether it's faithfully aligned, and what the most impactful next steps would be.

### 4. Output

Present the full report directly in the conversation. Do not write to a file unless `$ARGUMENTS` includes `--save`, in which case also write the report to `.claude/reports/divergence-analysis-YYYYMMDD.md` (using today's date).

## Notes

- The reference SDK organisations may have moved from `bitcoin-sv` to `bsv-blockchain` on GitHub. Try both.
- The TypeScript SDK implements all cryptography from scratch (no external deps). The Go SDK uses a custom secp256k1. The Python SDK uses `coincurve` (libsecp256k1 bindings). The Ruby SDK uses OpenSSL stdlib. These are architectural choices, not divergences.
- Focus on **semantic** comparison (what capabilities exist), not syntactic (naming conventions, language idioms).
