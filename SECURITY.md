# Security policy

The `bsv-sdk` and `bsv-wallet` gems are published from this repository
and treated as a single security domain — a fix in one usually means a
paired release of both.

## Reporting a vulnerability

Please report security issues via GitHub's private vulnerability
reporting:

- Go to the [Security tab](https://github.com/sgbett/bsv-ruby-sdk/security)
- Click **Report a vulnerability**

This opens a private draft advisory that only maintainers can see.
Please do **not** open a public issue or PR for anything security-relevant.

If you cannot use GitHub's reporting flow, email simon@bettison.org
with "bsv-ruby-sdk security" in the subject line. I will acknowledge
within a few working days.

## Supported versions

This project is pre-1.0 and moves quickly. Only the **latest released
version of each gem** receives security fixes. If you are pinned to an
older version, please upgrade before reporting — the fix for most
issues is "use the current release".

When a security fix lands, both gems are typically released together:

| Gem          | Latest                                                                    | Receives security fixes |
| ------------ | ------------------------------------------------------------------------- | ----------------------- |
| `bsv-sdk`    | see [rubygems.org/gems/bsv-sdk](https://rubygems.org/gems/bsv-sdk)       | yes                     |
| `bsv-wallet` | see [rubygems.org/gems/bsv-wallet](https://rubygems.org/gems/bsv-wallet) | yes                     |

## What to expect

- Acknowledgment of your report within a few working days
- An initial assessment — accepted, needs more information, or out of
  scope — shortly after
- For accepted reports, a coordinated disclosure: we will keep the
  issue embargoed while developing and testing a fix, file a GitHub
  Security Advisory with a CVE ID, and publish the advisory at the
  same time as the patched gems reach RubyGems
- Credit in the published advisory if you would like it (or anonymous
  if you prefer)

## Scope

In scope:

- Cryptographic correctness (key derivation, signing, verification,
  encryption, HMAC)
- Protocol conformance where a divergence has security consequences
  (BRC-52, BEEF, BRC-100, script interpreter, sighash)
- Wire-format parsers (VarInt, scripts, transactions, BEEF, wallet wire)
- Network clients where the response can influence a security-relevant
  decision (ARC broadcaster, chain provider, lookup resolvers)
- Credential and certificate handling in the wallet interface

Out of scope:

- DoS via resource exhaustion in parsers unless a realistic attack
  path exists
- Issues requiring a compromised local environment (stolen private
  keys, malicious Gemfile dependencies, hostile developer tooling)
- Weaknesses in the BSV protocol itself — those belong upstream

## Past advisories

Published advisories are tracked in [`.security/advisories/`](.security/advisories/)
and on the [GitHub Security Advisories tab](https://github.com/sgbett/bsv-ruby-sdk/security/advisories).
