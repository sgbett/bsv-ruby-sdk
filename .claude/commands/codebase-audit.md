---
description: Performs a comprehensive codebase correctness audit — finds bugs, semantic errors, and test gaps, then creates an HLR with implementation tasks. Use when the user asks to "audit the codebase", "check for bugs", "correctness audit", or "/codebase-audit".
---

# Codebase Correctness Audit

Systematically audits the current codebase for bugs, semantic errors, and test gaps, then organises findings into a trackable HLR with prioritised implementation tasks.

## Arguments

- `$ARGUMENTS` may contain focus areas (e.g., "primitives", "transaction", "script") to narrow scope
- If empty, audit the entire codebase

## Process

Use `ultrathink` for all analysis steps.

### 1. Gather Context

Before auditing, understand what you're working with:

- Read `CLAUDE.md` for project conventions, architecture, and constraints
- Run `bundle exec rake` to confirm current test suite state (pass count, failures, pending)
- Check `git log --oneline -20` for recent changes
- If reference SDKs exist (check CLAUDE.md), note their location for cross-checking

### 2. Audit the Codebase (parallel subagents)

Launch **Explore** subagents in parallel, one per layer/module. Each auditor should examine:

#### 2a. Bug Detection
- **Ruby version compatibility** — features used vs minimum Ruby version declared in gemspec
- **Nil safety** — unguarded method calls on potentially nil values
- **Encoding issues** — binary string handling, missing `.b` calls, encoding mismatches
- **Numeric edge cases** — integer overflow, off-by-one, division by zero, leading zeros
- **Error handling** — bare `rescue`, swallowed exceptions, missing error paths

#### 2b. Semantic Correctness
- **Protocol conformance** — does the implementation match the protocol specification? Use MCP protocol docs if available
- **Reference SDK alignment** — compare behaviour against reference implementations where available
- **Algorithm correctness** — verify crypto, hashing, encoding against known test vectors
- **State machine bugs** — incorrect flow control, missing state transitions, wrong condition checks

#### 2c. Test Quality
- **Missing coverage** — public methods or code paths with no test
- **Weak assertions** — tests that pass trivially or don't verify the right thing
- **Missing edge cases** — boundary values, empty inputs, error paths not tested
- **Missing cross-SDK vectors** — deterministic test vectors that should match reference implementations
- **Test infrastructure** — are test failures tracked properly? Are there flaky tests?

#### 2d. Defensive Coding
- **Input validation** — are public API boundaries validated?
- **Truncated/malformed input** — do parsers fail gracefully with descriptive errors?
- **Silent failures** — operations that silently return wrong results instead of raising

### 3. Classify Findings

Organise all findings into tiers by severity:

| Tier | Category | Description |
|------|----------|-------------|
| **B** | Bugs | Code that produces incorrect results or crashes |
| **S** | Semantic Errors | Code that works but doesn't match protocol/specification |
| **T** | Test Gaps | Missing or weak test coverage |

Within each tier, rank by impact (HIGH / MEDIUM / LOW).

### 4. Validate Findings

Before creating issues, validate each finding:

- **Bugs**: Confirm the bug exists by reading the code carefully. Check if there's a test that would catch it. If uncertain, write a minimal reproduction
- **Semantic errors**: Cross-reference against protocol docs or reference SDKs. Note when the analysis might be wrong — flag uncertainty
- **Test gaps**: Verify the test is actually missing, not just in a different file or tested indirectly

**Critical**: Discard any finding you cannot substantiate with evidence. False positives waste more time than they save. When in doubt, note the uncertainty in the finding description rather than asserting incorrectness.

### 5. Present Findings

Output a structured report:

```
## Codebase Correctness Audit — [date]

### Summary
[1-2 sentence overview: X findings across Y files, Z are high priority]

### Bugs (B)
B1. [HIGH] Title — file:line
    Finding: [what's wrong]
    Impact: [what breaks]
    Fix: [proposed fix]

### Semantic Errors (S)
S1. [MEDIUM] Title — file:line
    ...

### Test Gaps (T)
T1. [LOW] Title
    ...
```

### 6. Create HLR and Tasks

After presenting findings, ask the user if they want to proceed with creating issues. If yes:

1. **Create the HLR issue** on GitHub:
   - Title: `[HLR] Codebase correctness audit — [brief scope description]`
   - Label: `project:hlr`
   - Body: The full audit report from step 5

2. **Create sub-issues** for each finding:
   - Title format: `[Tier][Number]: [Brief description]` (e.g., `B1: Fix Ruby 2.7 compatibility in signature parsing`)
   - Body: Finding details, proposed fix, acceptance criteria
   - Link as sub-issues to the HLR using the GraphQL API

3. **Output the task list** so the user can run `/do-hlr <number>` to execute

## Lessons from Previous Audits

These patterns have been validated across prior audit runs:

### Things that are commonly wrong
- Ruby version features (e.g., `Integer#nobits?` is Ruby 3.2+, `Data.define` is 3.2+)
- Leading-zero byte handling in cryptographic operations (x-coordinates, DER encoding)
- Script interpreter flow control edge cases (OP_RETURN inside conditionals, multiple ELSE)
- Silent nil coercion hiding real bugs (`value || 0` instead of raising)
- Non-minimal push encoding being normalised away (breaks sighash integrity)

### Things that are commonly NOT wrong (avoid false positives)
- **Post-genesis single-ELSE enforcement** — BSV post-genesis correctly allows only one ELSE per IF block
- **SIGPUSHONLY** — this is a configurable flag, NOT automatically enforced post-genesis. Don't add unconditional enforcement
- **Pre-genesis vs post-genesis test vectors** — Bitcoin Core script vectors contain both. Failures on pre-genesis vectors are expected when the interpreter only implements post-genesis rules. Track these as known failures, not bugs

### Effective validation techniques
- Run `bundle exec rake` before and after every change to catch regressions immediately
- For script interpreter changes, count mismatches against the full vector suite — the count should go down, never up
- For crypto changes, use exact-match test vectors from reference SDKs (deterministic nonces, known keys)
- For parser changes, test with truncated input at every field boundary

## Notes

- This command is reusable — run it periodically as the codebase evolves
- Previous audit results may exist in closed GitHub issues; check before duplicating findings
- The audit is non-destructive — it only reads code and creates issues, never modifies source files
- If `$ARGUMENTS` includes `--save`, also write the report to `.claude/reports/codebase-audit-YYYYMMDD.md`
