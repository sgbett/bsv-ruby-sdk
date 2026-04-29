# Wycheproof Bitcoin Vectors and Signature Malleability

This document records the design reasoning behind how the SDK handles
Wycheproof's Bitcoin-specific ECDSA test vectors, particularly those
flagged `SignatureMalleabilityBitcoin`. The analysis is relevant to
[#652](https://github.com/sgbett/bsv-ruby-sdk/issues/652) and to any
future work on script interpretation or transaction validation.

## Background: two Wycheproof vector sets

The [C2SP/wycheproof](https://github.com/C2SP/wycheproof) project
provides two distinct ECDSA secp256k1/SHA-256 vector sets:

| Vector set | File | Cases | Purpose |
|---|---|---|---|
| Standard | `ecdsa_secp256k1_sha256_test.json` | 474 | General ECDSA verification correctness |
| Bitcoin | `ecdsa_secp256k1_sha256_bitcoin_test.json` | 463 | ECDSA verification **with Bitcoin's non-malleability rule** |

The standard vectors are already vendored and exercised by
`secp256k1_wycheproof_spec.rb` (see
[vectors/README.md](../../gem/bsv-sdk/spec/bsv/primitives/vectors/README.md)).

The Bitcoin vectors describe themselves in their header as testing an
*"ECDSA variant used for Bitcoin, that add signature non-malleability."*
They include a `SignatureMalleabilityBitcoin` flag on test cases where a
signature has `S > N/2` (high-S), marking such signatures as `invalid`.

## The key distinction: mathematical validity vs protocol policy

A high-S ECDSA signature is **mathematically valid**. Given `(r, s)` where
`0 < s < N`, the ECDSA verification equation holds regardless of whether
`s` is above or below `N/2`. The signature `(r, N - s)` is equally valid
for the same message and public key --- this is an inherent property of
the elliptic curve discrete logarithm relationship, not a bug.

Low-S enforcement (BIP-62 rule 5, BIP-146) is a **protocol policy
decision**: by convention, Bitcoin implementations restrict the valid
signature space to `s <= N/2` to eliminate one axis of third-party
malleability. This makes transaction IDs stable before confirmation,
which is useful for transaction chaining and UTXO management.

These are different questions:

- **"Is this a valid ECDSA signature?"** --- mathematical, answered by the
  raw ECDSA verify algorithm.
- **"Does this signature meet BSV standardness rules?"** --- policy,
  answered by the script interpreter or transaction validator.

Conflating these two layers --- treating a protocol policy as an inherent
property of the signature algorithm --- is precisely the conceptual error
that led to SegWit on BTC.

## The SegWit cautionary tale

Wright (2025) argues that SegWit was justified by mischaracterising
transaction malleability as an "attack":

> Malleability did not compromise security or integrity --- it merely
> allowed the same transaction content to be re-encoded. In systems where
> ordering and duplicate suppression matter, this is a protocol
> constraint to manage, not a threat to eliminate.
>
> --- Wright, C. S. (2025). *False Premises, Failed Promises: BTC's
> Market Illusion and the Abandonment of Bitcoin's Design.* University of
> Exeter, Department of Economics, Discussion Paper 2502, Section 3.1.
> Available at:
> <https://exetereconomics.github.io/RePEc/dpapers/DP2502.pdf>

The paper demonstrates that treating malleability as a defect rather than
a manageable property of the signature scheme enabled a rhetorical
pathway to SegWit --- which broke the chain of digital signatures that
defined Bitcoin's security model. The "fix" caused more structural damage
than the "problem" it claimed to address.

This history is directly relevant to SDK design. If we reflexively "fix"
every Wycheproof failure related to malleability by tightening
`ECDSA.verify`, we risk:

1. **Conflating layers** --- embedding protocol policy in the
   mathematical primitive, where it does not belong.
2. **Breaking legitimate use cases** --- signature recovery, historical
   transaction analysis, forensic verification of pre-policy
   transactions.
3. **Diverging from reference SDK architecture** --- the Go SDK
   deliberately separates these concerns (see below).

## Reference SDK architecture: where low-S is enforced

The Go SDK (the most architecturally mature reference) maintains a clean
two-layer separation:

### Mathematical layer (accepts high-S)

```go
// primitives/ecdsa/ecdsa.go:77-79
func Verify(msg []byte, signature *ec.Signature, publicKey *e.PublicKey) bool {
    return e.Verify(publicKey, msg, signature.R, signature.S)
}
```

This calls Go's `crypto/ecdsa.Verify()` directly. No low-S check.

### Policy layer (rejects high-S when flag is set)

```go
// script/interpreter/thread.go:14-15
var halfOrder = new(big.Int).Rsh(ec.S256().N, 1)

// script/interpreter/thread.go:749-754
if t.hasFlag(scriptflag.VerifyLowS) {
    sValue := new(big.Int).SetBytes(sig[sOffset : sOffset+sLen])
    if sValue.Cmp(halfOrder) > 0 {
        return errs.NewError(errs.ErrSigHighS, "...")
    }
}
```

Low-S enforcement is gated on `scriptflag.VerifyLowS` and lives in the
script interpreter's `checkSignatureEncoding()`, called during
`OP_CHECKSIG` execution.

The TypeScript SDK follows the same pattern: raw `ECDSA.verify()` accepts
any `s` in `(0, N)`, and `TransactionSignature.hasLowS()` exists as a
utility but is not enforced during raw verification.

### Summary across SDKs

| SDK | Raw ECDSA verify accepts high-S | Policy enforcement location |
|---|---|---|
| Go | Yes | `script/interpreter/thread.go` (scriptflag) |
| TypeScript | Yes | `TransactionSignature.hasLowS()` (utility, not enforced in verify) |
| Python | Depends on coincurve | `utils.serialize_ecdsa_der()` (serialisation, not verification) |
| **Ruby (ours)** | **Yes** | **Not yet built (will be in script interpreter)** |

## Our SDK's current position

- **`ECDSA.verify`** accepts high-S signatures. This is correct at the
  mathematical level and matches Go and TypeScript.
- **`ECDSA.sign` / `sign_raw`** always produce low-S signatures. This is
  correct for BSV --- we never create malleable signatures.
- **`Signature#low_s?` / `Signature#to_low_s`** exist as utilities for
  callers that need to check or normalise.

When the script interpreter is built (`BSV::Script::Interpreter`), low-S
enforcement will be implemented there, gated on the appropriate script
flags, matching the Go SDK's architecture.

## How to handle the Bitcoin Wycheproof vectors

When vendoring `ecdsa_secp256k1_sha256_bitcoin_test.json`:

1. **Add the vectors and run them** --- they provide valuable coverage for
   DER strictness, edge cases, and arithmetic correctness beyond what the
   standard vectors test.

2. **Categorise `SignatureMalleabilityBitcoin` failures explicitly** ---
   these are not bugs in `ECDSA.verify`. They are cases where a
   mathematically valid signature is rejected by Bitcoin's non-malleability
   policy. The spec should document this distinction:

   ```ruby
   when 'invalid'
     if tc['flags'].include?('SignatureMalleabilityBitcoin')
       # High-S signature: mathematically valid ECDSA, but rejected by
       # Bitcoin's low-S policy (BIP-62 rule 5). Raw ECDSA.verify
       # correctly accepts this; low-S enforcement belongs in the script
       # interpreter, not the primitive. See:
       # docs/testing/wycheproof-malleability-analysis.md
     else
       # Genuinely invalid: malformed DER, bad encoding, wrong values
     end
   ```

3. **Do not modify `ECDSA.verify`** to reject high-S. The mathematical
   primitive must remain pure. Protocol policy enforcement will be added
   when the script interpreter is implemented.

4. **Track the policy-layer work separately** --- a future issue for the
   script interpreter should reference this document and implement low-S
   enforcement there, gated on script flags, matching Go's architecture.

## References

- Wright, C. S. (2025). *False Premises, Failed Promises: BTC's Market
  Illusion and the Abandonment of Bitcoin's Design.* University of Exeter,
  Department of Economics, Discussion Paper 2502. Available at:
  <https://exetereconomics.github.io/RePEc/dpapers/DP2502.pdf>
- BIP-62: Dealing with malleability (Pieter Wuille, 2014). Withdrawn.
- BIP-146: Dealing with signature encoding malleability (Johnson Lau,
  Pieter Wuille, 2016).
- Wycheproof Bitcoin ECDSA vectors:
  `C2SP/wycheproof/testvectors_v1/ecdsa_secp256k1_sha256_bitcoin_test.json`
- Go SDK layer separation:
  `go-sdk/primitives/ecdsa/ecdsa.go` (raw verify) vs
  `go-sdk/script/interpreter/thread.go` (policy enforcement)
- Tracking issue:
  [sgbett/bsv-ruby-sdk#652](https://github.com/sgbett/bsv-ruby-sdk/issues/652)
