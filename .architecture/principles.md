# Architectural Principles

This document outlines the core architectural principles that guide all design decisions in the BSV Ruby SDK. These principles should be referenced when making architectural decisions, evaluating designs, and conducting reviews.

## Core Principles

### 1. Clarity over Cleverness

**Description**: Prefer simple, clear designs over clever, complex solutions, even when the latter might be more elegant or slightly more efficient.

**Rationale**: Clear designs are easier to understand, maintain, extend, and debug. They reduce cognitive load and make onboarding new contributors faster.

**Application**:
- Favour straightforward implementations over complex abstractions
- Use established patterns over novel approaches when possible
- Document the "why" behind design decisions, not just the "how"
- If you have to explain how it works, it's probably too complex

### 2. Separation of Concerns

**Description**: The SDK is divided into distinct modules with minimal overlap. Each module has a clear responsibility.

**Rationale**: Well-separated modules can be developed, tested, and maintained independently, reducing cognitive load and simplifying changes.

**Application**:
- `BSV::Primitives` owns keys, curves, hashing, and encryption
- `BSV::Script` owns parsing, opcodes, and templates
- `BSV::Transaction` owns building, signing, and serialisation
- Avoid shared mutable state and hidden dependencies between modules
- Build order follows the dependency chain: primitives -> script -> transaction

### 3. Testability

**Description**: All code should be designed to be easily testable. Tests are a first-class artefact, not an afterthought.

**Rationale**: A cryptographic SDK demands high confidence in correctness. Tests provide that confidence and enable safe refactoring.

**Application**:
- Write specs before or alongside implementation (TDD)
- Use known test vectors from BIPs, BRCs, and reference SDKs
- Keep classes and methods small enough to test in isolation
- Avoid global state that complicates test setup

### 4. Security by Default

**Description**: Security must be inherent in the design, not bolted on afterwards.

**Rationale**: This is a cryptographic library handling private keys and signatures. Security flaws have direct financial consequences.

**Application**:
- Never log or expose private key material
- Use constant-time comparison for security-sensitive operations
- Validate all inputs at module boundaries
- Prefer stdlib OpenSSL over custom implementations where possible
- Use secure random number generation for nonces

### 5. Evolvability

**Description**: The architecture should facilitate change and evolution over time without requiring complete rewrites.

**Rationale**: Requirements change as the BSV protocol evolves and as the SDK matures. The ability to adapt is essential.

**Application**:
- Design stable public APIs that can grow without breaking changes
- Use `autoload` for deferred loading and module organisation
- Create clear interfaces between layers
- Follow semantic versioning to communicate change impact

### 6. Pragmatic Simplicity

**Description**: Favour practical, working solutions over theoretical perfection.

**Rationale**: The SDK should solve real problems simply. Over-engineering adds complexity without proportional benefit.

**Application**:
- Value working code over comprehensive documentation
- Make incremental improvements rather than seeking perfection
- Question abstractions that don't demonstrably simplify the system
- Three similar lines of code is better than a premature abstraction

## Project-Specific Principles

### 7. Faithful Port, Ruby Idioms

**Description**: Match the semantics and behaviour of the reference BSV SDKs (Go, TypeScript, Python) while expressing them in idiomatic Ruby.

**Rationale**: This SDK is part of an official family. Consumers moving between languages expect consistent behaviour. But a line-for-line transliteration produces poor Ruby — the port must feel native.

**Application**:
- Method signatures and class hierarchies should mirror reference SDKs where sensible
- Use Ruby conventions: snake_case, question-mark predicates, blocks, enumerables
- All cryptography through stdlib `OpenSSL` — no external gems
- Maintain Ruby 3.3 compatibility (no Ruby 3.4+ features, e.g. `it` block parameter; pattern matching, `Hash#except`, `Data.define`, and endless methods are available)
- When reference SDKs disagree, prefer the Go SDK as canonical
- When reference SDKs lack coverage or are ambiguous, consult the [BSV Hub protocol documentation](https://hub.bsvblockchain.org/bitcoin-protocol-documentation) as the canonical protocol reference

### 8. Declarative Core, Imperative Companions

**Description**: The SDK defines what things *are* (data structures, serialisation, protocol rules). Companion gems define what to *do* (workflows, orchestration, use-cases).

**Rationale**: Keeping the SDK declarative makes it a stable foundation that multiple companion gems can build upon without colliding. Mixing orchestration into the SDK creates coupling between unrelated use-cases.

**Application**:
- SDK classes should model protocol concepts: transactions, scripts, keys, proofs
- Avoid workflow methods that assume a specific use-case (e.g. "broadcast and wait")
- Network access, wallet state, and UI concerns belong in companion gems
- Grey areas exist (e.g. `BSV::Wallet`, `BSV::Network`); the principle is directional, not absolute

### 9. Recognise Everything, Construct Only What's Valid

**Description**: The SDK provides full parsing and detection of all script types (including legacy and historical outputs), but does not provide constructors for protocol features BSV has removed or never adopted.

**Rationale**: BSV preserves the original Bitcoin protocol design. Users need to read historical data, but should not construct invalid transactions.

**Application**:
- `p2sh?` detection and `script_hash` extraction are supported (read-only)
- `p2sh_lock` / `p2sh_unlock` constructors are not provided (P2SH is not valid on BSV)
- SegWit, Taproot (BIP-340), Replace-by-Fee, and bech32 addresses are not implemented
- When reference SDKs include features that conflict with BSV protocol, protocol takes precedence

## Implementation Guidelines

### Documentation

All significant architectural decisions should be documented in Architectural Decision Records (ADRs) that explain:
- The context and problem being addressed
- The decision that was made
- The consequences (positive and negative)
- Alternatives that were considered

### Review Process

Architectural changes should be reviewed against these principles. Reviews should explicitly address:
- How the change upholds or challenges each principle
- Trade-offs made between principles when they conflict
- Measures to mitigate any negative consequences

### Exceptions

Exceptions to these principles may be necessary in specific circumstances. When making exceptions:
- Document the exception and its justification
- Define the scope and boundaries of the exception
- Create a plan to eliminate or reduce the exception over time if possible
