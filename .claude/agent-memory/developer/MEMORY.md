# Developer Memory

## Key Architecture Notes

- Namespace: `BSV::` → `BSV::Primitives`, `BSV::Script`, `BSV::Transaction`
- Entry point: `lib/bsv-sdk.rb`
- All files: `# frozen_string_literal: true`, single-quoted strings
- Ruby 2.7 compat required — no `Random::DEFAULT` (removed in 3.0), no pattern matching, `Hash#except`, `Data.define`, endless methods

## Ruby Version Gotchas

- `Random::DEFAULT` is NOT available in Ruby 3.x — use `Random` (the class itself) as default RNG
  - Pattern: `def foo(rng: nil); rng ||= Random; ...`
  - `Random.rand(range)` works via the class method

## Project Patterns

### Autoloading
- New classes/modules must be registered in `lib/bsv/primitives.rb` via `autoload`
- Pattern: `autoload :ClassName, 'bsv/primitives/file_name'`

### File structure
- Source: `lib/bsv/primitives/<name>.rb`
- Specs: `spec/bsv/primitives/<name>_spec.rb` (or subdirectory with RuboCop exclusion)
- All files must start with `# frozen_string_literal: true` and `require 'openssl'` if using OpenSSL

### OpenSSL::BN gotchas
- No `#mod` method — use `%` operator instead
- `#mod_sub` returns positive values (already in [0, P))
- `#mod_inverse` for field inverse
- `#mod_mul`, `#mod_add` for field arithmetic
- Single-letter params `x`, `y` allowed — added to `.rubocop.yml` AllowedNames

## Test Conventions

- Non-class `RSpec.describe` blocks: add `# rubocop:disable RSpec/DescribeClass` inline
- Top-level constants in spec files: define OUTSIDE the `RSpec.describe` block to avoid `Lint/ConstantDefinitionInBlock`
- Max `describe` nesting: 3 levels (`RSpec/NestedGroups`) — flatten or use descriptive `it` names instead of inner `describe` blocks
- `verify_partial_doubles = true` is set in spec_helper — cannot stub methods that don't exist

## RuboCop Config

- `.rubocop.yml` has `Naming/MethodParameterName.AllowedNames` for short crypto names
- Add new spec subdirectories to `RSpec/SpecFilePathFormat.Exclude` if not matching class path
- All metric cops excluded for `lib/bsv/primitives/**/*`
- `Lint/AmbiguousOperatorPrecedence` — add parens around `(max - min) * Math.log10(...)`
- `-A` autocorrects most; check for remaining after autocorrect

## SSS Implementation (Shamirs Secret Sharing)

- Files: `point_in_finite_field.rb`, `polynomial.rb`, `key_shares.rb`
- PrivateKey methods: `to_key_shares`, `to_backup_shares`, `from_key_shares`, `from_backup_shares`
- Field prime P = secp256k1 field prime (NOT curve order N)
- Integrity = `public_key.hash160[0,4].unpack1('H*')` (first 8 hex chars of Hash160)
- Backup format: `"Base58(x).Base58(y).threshold.integrity"` (4 dot-separated parts)
- CRITICAL: use `split('.', -1)` not `split('.')` when parsing — Ruby drops trailing empty fields without -1 limit
- X-coords generated via HMAC-SHA-512 over 64-byte seed with per-share counter
- Cross-SDK static vectors verified against go-sdk polynomial_test.go
- Specs in `spec/bsv/primitives/shamir/` (excluded from RSpec/SpecFilePathFormat)
- TS SDK example backup strings in docstring are fabricated — not real vectors for the known test key
- `String#split` Ruby gotcha: `"a.b.".split('.')` → `["a", "b"]` (3 not 4); use `split('.', -1)`

## Transaction Fee API

- `Transaction#fee(model_or_fee = nil, change_distribution: :equal, rng: nil)`
- `:equal` = equal split (default, matching TS SDK), `:random` = Benford-inspired
- `benford_number(min, max, rng)` is private — access via `send` in specs
- Remainder from floor-rounding in random distribution → last transaction output (TS SDK match)

## Statistical Testing Notes

- `benford_number` produces exactly 9 distinct outputs (one per d in 1..9, chosen uniformly)
- The "Benford" property is in the *scaling factors*, NOT leading digit distribution
- Chi-squared test should test uniform d selection (df=8, critical=20.09 at p=0.01), NOT leading digits
- All 9 outputs from `benford_number(0, max)` are below `max/2` (log10(2) ≈ 0.301 < 0.5)
