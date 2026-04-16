# Draft comment for bsv-blockchain/wallet-toolbox#149

**Not yet posted.** Review before posting. Attribution note: same reporter
as upstream issue (sgbett / Simon Bettison), so tone can be direct and
technical.

---

## Comment body

Hi — just a note that I hit the same issue while porting the wallet to Ruby (sgbett/bsv-ruby-sdk, HLR #466), and the investigation turned up a slightly different shape to what I originally thought when I filed this.

My initial instinct (and the workaround in the fork) was that `internaliseAction` wasn't persisting BEEF ancestors. After going deeper, that turned out not to be quite right — `storeProofsFromBeef` was already walking the full BEEF and storing every ancestor transaction. The storage side was fine.

The real issue was in two other places:

**1. EF serialisation (`toHexEF` / `writeEF`)**

When a transaction is built using inputs from `fromBEEF`, those inputs have their `sourceTransaction` wired up but `sourceSatoshis` and `sourceLockingScript` aren't set as explicit properties on the input object. In the Ruby port, `toEF` wasn't falling back to `input.sourceTransaction.outputs[i]` when those explicit fields were missing — it just raised and the caller silently fell back to broadcasting plain hex. ARC then rejected that hex because the parent was unconfirmed.

I had a look at the TS `writeEF` (Transaction.ts ~L672–713) and it accesses `i.sourceTransaction.outputs[i.sourceOutputIndex]` directly, so it should handle this correctly. The Ruby implementation was the divergent one here — the fix was to derive from `sourceTransaction` when explicit fields aren't set, non-mutating, matching the TS behaviour.

**2. `fromBEEF` ancestry wiring**

The second, subtler issue: `Transaction.fromBEEF` (Ruby's `from_beef`) wasn't routing through `Beef#findAtomicTransaction` (our `find_atomic_transaction`). That method does the extra step of attaching late-bound BUMPs to `FORMAT_RAW_TX` ancestors whose txid appears as a leaf elsewhere in the BUMP tree — a pass that `wireSourceTransactions` alone doesn't cover. So the returned transaction had some ancestors without `merklePath` attached even when the BEEF contained the proof.

The fix was to go through `findAtomicTransaction` / `find_atomic_transaction` rather than the simpler path, so every ancestor in the returned tx has its proof wired before you try to broadcast.

---

The end-to-end symptom is: `internaliseAction` runs fine, the UTXO lands in the wallet, but when you try to spend it in a later `createAction`, the broadcast silently falls back to raw hex (or fails to build EF), and ARC rejects it with "must be valid transaction on chain".

The fix in the Ruby SDK is in [sgbett/bsv-ruby-sdk#473](https://github.com/sgbett/bsv-ruby-sdk/pull/473) if it's useful as a reference.

Whether the TS SDK has the same gap in `fromBEEF` / `fromAtomicBEEF` is worth a look — if `writeEF` already handles the `sourceTransaction` fallback correctly (which it looks like it does), the TS issue might be narrower than "persist ancestors in `internaliseAction`". Happy to dig into it further if that's useful.

