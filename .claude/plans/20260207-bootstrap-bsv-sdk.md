# BSV Ruby SDK — Project Bootstrap Plan

## Goal

Get the skeleton at `/opt/ruby/bsv-ruby-sdk` to a proper, buildable, testable, committable Ruby gem project. No BSV implementation yet — just infrastructure.

## Pre-requisites

1. **Install Ruby 4.0.1** via rvm (`rvm install 4.0.1 && rvm use 4.0.1`)
2. **Rename branch** `main` → `master` (`git branch -m main master`)

## Files to Create/Populate

### Infrastructure files (new)

| File | Purpose |
|------|---------|
| `.ruby-version` | Contains `4.0.1` — rvm reads this on `cd` |
| `.rspec` | `--require spec_helper`, `--format documentation`, `--colour` |
| `.rubocop.yml` | Minimal config: target Ruby 2.7, disable `Style/Documentation`, exclude specs from block length |
| `LICENCE` | Open BSV License Version 5 (full text from Go SDK) |
| `README.md` | Minimal: status, install, dev setup, licence link |
| `CHANGELOG.md` | Just `## [Unreleased]` |
| `spec/spec_helper.rb` | Standard RSpec config + `require "bsv-sdk"` |
| `spec/bsv_spec.rb` | Smoke test: `expect(BSV::VERSION).not_to be_nil` |

### Existing files to populate

| File | Content |
|------|---------|
| `bsv-sdk.gemspec` | Full metadata: name `bsv-sdk`, version from `BSV::VERSION`, `required_ruby_version >= 2.7`, licence `"Open BSV"`, homepage, source URIs, `rubygems_mfa_required`, `spec.files` via `Dir.glob("lib/**/*")` + docs. No runtime dependencies. |
| `lib/bsv/version.rb` | `BSV::VERSION = "0.1.0"` |
| `lib/bsv-sdk.rb` | Entry point: defines `module BSV` with `autoload` for `:Primitives`, `:Script`, `:Transaction` |
| `Gemfile` | Keep existing `gemspec name: "bsv-sdk"`. Add `group :development, :test` with `rspec`, `rubocop`, `rubocop-rspec`. |
| `Rakefile` | Add `RSpec::Core::RakeTask` and `task default: :spec` |
| `.gitignore` | Comprehensive: `*.gem`, `pkg/`, `/.bundle/`, `Gemfile.lock`, `/coverage/`, `/.rspec_status`, IDE files, OS files, `/tmp/` |

### Module stubs (new, empty module definitions)

| File | Module |
|------|--------|
| `lib/bsv/primitives.rb` | `BSV::Primitives` — future: keys, curves, hashing, encryption |
| `lib/bsv/script.rb` | `BSV::Script` — future: script parsing, opcodes, templates |
| `lib/bsv/transaction.rb` | `BSV::Transaction` — future: building, signing, BEEF, merkle |

These are empty modules with autoload stubs pointing to files that don't exist yet. Autoload only triggers on access, so this is safe.

## Key Design Decisions

### Ruby version strategy
- **`.ruby-version`** containing `4.0.1` for developer convenience (rvm/rbenv/asdf all honour it)
- **No `ruby` directive in Gemfile** — that's a hard Bundler constraint, inappropriate for libraries
- **`required_ruby_version >= 2.7`** in gemspec — allows use with legacy apps (e.g., portfoliobuilder on Rails 4 / Ruby 2.7.4)
- **Coding constraint**: avoid Ruby 3.0+ features (pattern matching, `Hash#except`, `Data.define`, endless methods) until the minimum is raised. CI should test 2.7 to enforce this.
- **Plan to raise minimum to >= 3.1** once the legacy consumers have upgraded

### Gemfile.lock — do NOT commit
Standard practice for gems (unlike applications). Library consumers resolve their own dependency tree.

### Dev dependencies in Gemfile, not gemspec
Modern Bundler convention. `add_development_dependency` in gemspec is legacy.

### Cryptography approach (informational — not in this commit)
Ruby's stdlib `openssl` supports secp256k1 natively — confirmed with `OpenSSL::PKey::EC.builtin_curves`. This covers ECDSA, SHA-256, RIPEMD-160, AES, HMAC, ECDH with zero external dependencies. Things needing custom implementation later: RFC 6979 deterministic signing, Schnorr signatures, Base58Check, BIP-32/39.

### Licence
Open BSV License Version 5 — matching all official BSV SDKs (Go, TS, Py). Full text sourced from the Go SDK's `LICENSE` file.

## Verification

After implementation, run:
```bash
bundle install                    # dependencies resolve
bundle exec rake                  # rspec passes (1 example, 0 failures)
bundle exec rubocop               # no offences
gem build bsv-sdk.gemspec         # produces bsv-sdk-0.1.0.gem
```

## What Comes After This

1. **Run `/init`** to generate project `CLAUDE.md`. Ensure it captures: Ruby 2.7 compat constraint (no 3.0+ features), monorepo structure, gem name `bsv-sdk`, `BSV::` namespace, reference SDKs (go-sdk/ts-sdk/py-sdk), stdlib openssl for crypto, no Gemfile.lock in git.
2. **GitHub remote**: `git remote add origin git@github.com:sgbett/bsv-ruby-sdk.git` + push
3. **CI** (optional second commit): GitHub Actions across Ruby 2.7, 3.1, 3.4, 4.0
4. **Begin BSV implementation**: Start with `BSV::Primitives` — PrivateKey, PublicKey, hash functions. This is the foundation all three official SDKs build on: primitives → script → transaction → everything else
