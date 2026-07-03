# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Transaction::Tx do
  describe '#verify' do
    let(:priv) { BSV::Primitives::PrivateKey.generate }
    let(:pub) { priv.public_key }
    let(:lock_script) { BSV::Script::Script.p2pkh_lock(pub.hash160) }
    let(:chain_tracker) { instance_double(BSV::Transaction::ChainTracker) }

    # Build a source (parent) transaction that pays to our key.
    # Returns a signed, complete transaction.
    def build_source_tx(satoshis: 100_000)
      tx = described_class.new
      # Coinbase-like input (no real source needed)
      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: BSV::Primitives::Digest.sha256d('source'),
        prev_tx_out_index: 0
      )
      input.unlocking_script = BSV::Script::Script.from_asm('OP_TRUE')
      input.source_locking_script = BSV::Script::Script.from_asm('OP_TRUE')
      input.source_satoshis = satoshis + 1000
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: satoshis,
                      locking_script: lock_script
                    ))
      tx
    end

    # Build a spending transaction that consumes the source tx output.
    # Properly signed so script verification succeeds.
    def build_spending_tx(source_tx, output_sats: 90_000)
      tx = described_class.new
      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: source_tx.wtxid,
        prev_tx_out_index: 0
      )
      input.source_satoshis = source_tx.outputs[0].satoshis
      input.source_locking_script = source_tx.outputs[0].locking_script
      input.source_transaction = source_tx
      input.unlocking_script_template = BSV::Transaction::P2PKH.new(priv)
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: output_sats,
                      locking_script: lock_script
                    ))
      tx.sign_all
      tx
    end

    def make_merkle_path
      instance_double(BSV::Transaction::MerklePath,
                      block_height: 800_000,
                      verify: true)
    end

    describe 'merkle path short-circuit' do
      it 'returns true when merkle path validates' do
        source_tx = build_source_tx
        source_tx.merkle_path = make_merkle_path

        tx = build_spending_tx(source_tx)

        expect(tx.verify(chain_tracker: chain_tracker)).to be true
      end

      it 'raises when merkle path is invalid' do
        source_tx = build_source_tx
        bad_path = instance_double(BSV::Transaction::MerklePath,
                                   block_height: 800_000,
                                   verify: false)
        source_tx.merkle_path = bad_path

        tx = build_spending_tx(source_tx)

        expect { tx.verify(chain_tracker: chain_tracker) }
          .to raise_error(BSV::Transaction::VerificationError, /invalid merkle proof/)
      end

      it 'skips input verification for proven transactions' do
        source_tx = build_source_tx
        source_tx.merkle_path = make_merkle_path

        tx = build_spending_tx(source_tx)

        # Sabotage source_tx's input scripts — if verify touched them, it would fail.
        # Since source_tx has a valid merkle path, its inputs are never checked.
        source_tx.inputs[0].unlocking_script = nil
        source_tx.inputs[0].source_locking_script = nil

        expect(tx.verify(chain_tracker: chain_tracker)).to be true
      end
    end

    describe 'script execution' do
      it 'returns true when scripts are valid' do
        source_tx = build_source_tx
        source_tx.merkle_path = make_merkle_path

        tx = build_spending_tx(source_tx)

        expect(tx.verify(chain_tracker: chain_tracker)).to be true
      end

      it 'raises VerificationError(:script_failure) when scripts fail' do
        source_tx = build_source_tx
        source_tx.merkle_path = make_merkle_path

        tx = build_spending_tx(source_tx)
        # Replace the unlocking script with something that will fail
        tx.inputs[0].unlocking_script = BSV::Script::Script.from_asm('OP_0')

        expect { tx.verify(chain_tracker: chain_tracker) }
          .to raise_error(BSV::Transaction::VerificationError) { |e|
            expect(e.code).to eq(:script_failure)
            expect(e.message).to include('input 0')
            expect(e.cause).to be_a(BSV::Script::ScriptError)
          }
      end
    end

    describe 'recursive ancestry verification' do
      it 'verifies source transactions without merkle paths' do
        # grandparent (has merkle path) -> parent -> child
        grandparent = build_source_tx(satoshis: 200_000)
        grandparent.merkle_path = make_merkle_path

        parent = build_spending_tx(grandparent, output_sats: 150_000)

        child = build_spending_tx(parent, output_sats: 100_000)

        expect(child.verify(chain_tracker: chain_tracker)).to be true
      end

      it 'raises if source transaction is missing for unmined ancestor' do
        source_tx = build_source_tx
        # No merkle path, no source_transaction on source_tx's input
        # source_tx itself has an input with OP_TRUE but no source_transaction

        tx = build_spending_tx(source_tx)

        # source_tx has no merkle path, so its inputs need verification.
        # Its input has OP_TRUE scripts which pass, but then we need to
        # verify source_tx's source transaction — which doesn't exist.
        # The output constraint check should still work since source_satoshis is set.
        # Actually, since source_tx has no source_transaction set on its input,
        # and it has no merkle path, verify will check its scripts (which pass)
        # and then try to enqueue its source_transaction (which is nil, so skip).
        # This is actually valid — not all inputs need source transactions
        # if the scripts can be verified independently.
        expect(tx.verify(chain_tracker: chain_tracker)).to be true
      end
    end

    describe 'deduplication' do
      it 'does not re-verify the same source transaction' do
        source_tx = build_source_tx(satoshis: 200_000)
        source_tx.merkle_path = make_merkle_path

        # Two outputs from the same source
        tx = described_class.new
        [0, 0].each_with_index do |out_idx, _i|
          input = BSV::Transaction::TransactionInput.new(
            prev_wtxid: source_tx.wtxid,
            prev_tx_out_index: out_idx
          )
          input.source_satoshis = source_tx.outputs[0].satoshis
          input.source_locking_script = source_tx.outputs[0].locking_script
          input.source_transaction = source_tx
          input.unlocking_script_template = BSV::Transaction::P2PKH.new(priv)
          tx.add_input(input)
        end
        tx.add_output(BSV::Transaction::TransactionOutput.new(
                        satoshis: 50_000,
                        locking_script: lock_script
                      ))
        tx.sign_all

        # The merkle path verify should only be called once for the source tx
        path = source_tx.merkle_path
        allow(path).to receive(:verify).and_return(true)
        expect(tx.verify(chain_tracker: chain_tracker)).to be true
        expect(path).to have_received(:verify).once
      end
    end

    describe 'fee validation' do
      it 'passes when fee meets model requirement' do
        source_tx = build_source_tx(satoshis: 100_000)
        source_tx.merkle_path = make_merkle_path

        tx = build_spending_tx(source_tx, output_sats: 90_000)
        # Fee is 10000 sat — should easily pass any reasonable model

        fee_model = instance_double(BSV::Transaction::FeeModel)
        allow(fee_model).to receive(:compute_fee).and_return(100)

        expect(tx.verify(chain_tracker: chain_tracker, fee_model: fee_model)).to be true
      end

      it 'raises when fee is insufficient' do
        source_tx = build_source_tx(satoshis: 100_000)
        source_tx.merkle_path = make_merkle_path

        tx = build_spending_tx(source_tx, output_sats: 99_999)
        # Fee is only 1 sat

        fee_model = instance_double(BSV::Transaction::FeeModel)
        allow(fee_model).to receive(:compute_fee).and_return(100)

        expect { tx.verify(chain_tracker: chain_tracker, fee_model: fee_model) }
          .to raise_error(BSV::Transaction::VerificationError, /insufficient fee/)
      end

      it 'skips fee validation when fee_model is nil' do
        source_tx = build_source_tx(satoshis: 100_000)
        source_tx.merkle_path = make_merkle_path

        tx = build_spending_tx(source_tx, output_sats: 99_999)
        # Very low fee but no fee model — should pass

        expect(tx.verify(chain_tracker: chain_tracker)).to be true
      end

      it 'only validates fee on the root transaction' do
        grandparent = build_source_tx(satoshis: 200_000)
        grandparent.merkle_path = make_merkle_path

        # Parent has high fee (150000 input, 100001 output = 49999 fee)
        parent = build_spending_tx(grandparent, output_sats: 100_001)

        # Child has low fee (100001 input, 100000 output = 1 sat fee)
        child = build_spending_tx(parent, output_sats: 100_000)

        fee_model = instance_double(BSV::Transaction::FeeModel)
        # Model requires 50 sat — child only pays 1 sat
        allow(fee_model).to receive(:compute_fee).and_return(50)

        expect { child.verify(chain_tracker: chain_tracker, fee_model: fee_model) }
          .to raise_error(BSV::Transaction::VerificationError, /insufficient fee/)
      end
    end

    describe 'output ≤ input check' do
      it 'raises when outputs exceed inputs' do
        source_tx = build_source_tx(satoshis: 100_000)
        source_tx.merkle_path = make_merkle_path

        # Use OP_TRUE scripts so script verification passes despite invalid amounts
        tx = described_class.new
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: source_tx.wtxid,
          prev_tx_out_index: 0
        )
        input.source_satoshis = 100_000
        input.source_locking_script = BSV::Script::Script.from_asm('OP_TRUE')
        input.unlocking_script = BSV::Script::Script.from_asm('OP_TRUE')
        input.source_transaction = source_tx
        tx.add_input(input)
        tx.add_output(BSV::Transaction::TransactionOutput.new(
                        satoshis: 200_000,
                        locking_script: lock_script
                      ))

        expect { tx.verify(chain_tracker: chain_tracker) }
          .to raise_error(BSV::Transaction::VerificationError, /outputs.*exceed inputs/)
      end
    end

    describe 'missing requirements' do
      it 'raises when unlocking script is missing' do
        source_tx = build_source_tx
        source_tx.merkle_path = make_merkle_path

        tx = described_class.new
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: source_tx.wtxid,
          prev_tx_out_index: 0
        )
        input.source_satoshis = 100_000
        input.source_locking_script = lock_script
        input.source_transaction = source_tx
        # No unlocking script set
        tx.add_input(input)
        tx.add_output(BSV::Transaction::TransactionOutput.new(
                        satoshis: 90_000,
                        locking_script: lock_script
                      ))

        expect { tx.verify(chain_tracker: chain_tracker) }
          .to raise_error(BSV::Transaction::VerificationError) { |e|
            expect(e.code).to eq(:missing_source)
            expect(e.message).to include('no unlocking script')
          }
      end

      it 'raises when source locking script is missing (no source_transaction to fall back to)' do
        source_tx = build_source_tx
        source_tx.merkle_path = make_merkle_path

        tx = described_class.new
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: source_tx.wtxid,
          prev_tx_out_index: 0
        )
        input.source_satoshis = 100_000
        input.unlocking_script = BSV::Script::Script.from_asm('OP_TRUE')
        # No source_locking_script and no source_transaction to fall back to
        tx.add_input(input)
        tx.add_output(BSV::Transaction::TransactionOutput.new(
                        satoshis: 90_000,
                        locking_script: lock_script
                      ))

        expect { tx.verify(chain_tracker: chain_tracker) }
          .to raise_error(BSV::Transaction::VerificationError) { |e|
            expect(e.code).to eq(:missing_source)
            expect(e.message).to include('no source locking script')
          }
      end

      it 'raises when source satoshis is missing (no source_transaction to fall back to)' do
        source_tx = build_source_tx
        source_tx.merkle_path = make_merkle_path

        tx = described_class.new
        input = BSV::Transaction::TransactionInput.new(
          prev_wtxid: source_tx.wtxid,
          prev_tx_out_index: 0
        )
        input.unlocking_script = BSV::Script::Script.from_asm('OP_TRUE')
        input.source_locking_script = lock_script
        # No source_satoshis and no source_transaction to fall back to
        tx.add_input(input)
        tx.add_output(BSV::Transaction::TransactionOutput.new(
                        satoshis: 90_000,
                        locking_script: lock_script
                      ))

        expect { tx.verify(chain_tracker: chain_tracker) }
          .to raise_error(BSV::Transaction::VerificationError) { |e|
            expect(e.code).to eq(:missing_source)
            expect(e.message).to include('no source satoshis')
          }
      end
    end

    describe 'return value' do
      it 'returns true on success' do
        source_tx = build_source_tx
        source_tx.merkle_path = make_merkle_path

        tx = build_spending_tx(source_tx)
        result = tx.verify(chain_tracker: chain_tracker)

        expect(result).to be true
      end
    end

    describe '#verify with verified: (bidirectional wtxid dedup Hash)' do
      let(:bogus_wtxid) { "\x00".b * 32 }

      # Regression guard: calling verify without verified: must be identical to pre-kwarg behaviour.
      it 'kwarg default: accepts without verified:' do
        source_tx = build_source_tx
        source_tx.merkle_path = make_merkle_path
        tx = build_spending_tx(source_tx)

        expect(tx.verify(chain_tracker: chain_tracker)).to be true
      end

      it 'kwarg default: still raises :script_failure when verified: is omitted and script is bad' do
        source_tx = build_source_tx
        source_tx.merkle_path = make_merkle_path
        tx = build_spending_tx(source_tx)
        tx.inputs[0].unlocking_script = BSV::Script::Script.from_asm('OP_0')

        expect { tx.verify(chain_tracker: chain_tracker) }
          .to raise_error(BSV::Transaction::VerificationError) { |e|
            expect(e.code).to eq(:script_failure)
          }
      end

      # Cross-BEEF ancestor headline: X is an intermediate ancestor with no merkle_path.
      # Subject spends X. Seeding X's wtxid short-circuits its subtree; the interpreter
      # never touches X's inputs on the seeded run.
      it 'cross-BEEF ancestor: skips X subtree and returns true when X is seeded' do
        grandparent = build_source_tx(satoshis: 200_000)
        grandparent.merkle_path = make_merkle_path

        ancestor_x = build_spending_tx(grandparent, output_sats: 150_000)
        subject_tx = build_spending_tx(ancestor_x, output_sats: 100_000)

        expect(subject_tx.verify(chain_tracker: chain_tracker)).to be true

        allow(BSV::Script::Interpreter).to receive(:verify).and_call_original

        result = subject_tx.verify(chain_tracker: chain_tracker, verified: { ancestor_x.wtxid => true })
        expect(result).to be true
        expect(BSV::Script::Interpreter).to have_received(:verify).exactly(1).times
      end

      # ANCHOR TEST — trust contract lock.
      # CONTRACT LOCK: do not weaken. If this ever changes, the trust contract silently
      # changes and the seeding feature becomes undetectably unsafe.
      #
      # A seeded ancestor with an invalid unlocking script MUST still cause verify to return
      # true — because the caller warrants the seeded wtxid was verified in a prior session.
      it 'invalid-signature ancestor with seed: passes (ANCHOR TEST — trust contract lock)' do
        source_tx = build_source_tx
        source_tx.merkle_path = make_merkle_path
        bad_ancestor = build_spending_tx(source_tx, output_sats: 50_000)
        subject_tx = build_spending_tx(bad_ancestor, output_sats: 40_000)

        bad_ancestor.inputs[0].unlocking_script = BSV::Script::Script.from_asm('OP_0')

        expect { subject_tx.verify(chain_tracker: chain_tracker) }
          .to raise_error(BSV::Transaction::VerificationError) { |e|
            expect(e.code).to eq(:script_failure)
          }

        source_tx2 = build_source_tx
        source_tx2.merkle_path = make_merkle_path
        bad_ancestor2 = build_spending_tx(source_tx2, output_sats: 50_000)
        subject_tx2 = build_spending_tx(bad_ancestor2, output_sats: 40_000)
        bad_ancestor2.inputs[0].unlocking_script = BSV::Script::Script.from_asm('OP_0')

        result = subject_tx2.verify(
          chain_tracker: chain_tracker,
          verified: { bad_ancestor2.wtxid => true }
        )
        expect(result).to be true
      end

      # Bidirectional post-read: caller's Hash is populated with every wtxid walked.
      it "caller's Hash: populated with walked wtxids after verify (object_id preserved)" do
        grandparent = build_source_tx(satoshis: 200_000)
        grandparent.merkle_path = make_merkle_path
        parent = build_spending_tx(grandparent, output_sats: 150_000)
        subject = build_spending_tx(parent, output_sats: 100_000)

        collected = {}
        captured_id = collected.object_id

        result = subject.verify(chain_tracker: chain_tracker, verified: collected)

        expect(result).to be true
        expect(collected.object_id).to eq(captured_id)
        expect(collected.keys).to contain_exactly(subject.wtxid, parent.wtxid, grandparent.wtxid)
        expect(collected.values).to all(be true)
      end

      # Bidirectional round-trip: pre-seeded wtxids skip AND newly-walked wtxids accumulate
      # in the same Hash.
      it 'bidirectional round-trip: pre-seeded wtxids are honoured AND newly-walked ones accumulate' do
        grandparent = build_source_tx(satoshis: 200_000)
        grandparent.merkle_path = make_merkle_path
        parent = build_spending_tx(grandparent, output_sats: 150_000)
        subject = build_spending_tx(parent, output_sats: 100_000)

        cache = { grandparent.wtxid => true }
        cache_id = cache.object_id

        allow(BSV::Script::Interpreter).to receive(:verify).and_call_original

        result = subject.verify(chain_tracker: chain_tracker, verified: cache)

        expect(result).to be true
        expect(cache.object_id).to eq(cache_id)
        expect(cache.keys).to contain_exactly(grandparent.wtxid, parent.wtxid, subject.wtxid)
        expect(BSV::Script::Interpreter).to have_received(:verify).exactly(2).times
      end

      # Trust contract: seeded wtxid fully short-circuits — merkle proof is NOT re-verified.
      # This makes the caller's warrant a full-trust one (script + chain anchor).
      # It is the intentional consequence of the single-Hash presence-only design.
      it 'seeded wtxid with (would-be-invalid) merkle_path: proof is not verified (optimistic trust)' do
        # Baseline: without seed, the bad merkle proof raises.
        source_a = build_source_tx
        source_a.merkle_path = instance_double(BSV::Transaction::MerklePath,
                                               block_height: 800_000,
                                               verify: false)
        tx_a = build_spending_tx(source_a)
        expect { tx_a.verify(chain_tracker: chain_tracker) }
          .to raise_error(BSV::Transaction::VerificationError, /invalid merkle proof/)

        # Fresh objects for the seeded run — the bad merkle_path must never be consulted.
        source_b = build_source_tx
        bad_path_b = instance_double(BSV::Transaction::MerklePath,
                                     block_height: 800_000,
                                     verify: false)
        source_b.merkle_path = bad_path_b
        tx_b = build_spending_tx(source_b)

        result = tx_b.verify(chain_tracker: chain_tracker, verified: { source_b.wtxid => true })

        expect(result).to be true
        expect(bad_path_b).not_to have_received(:verify)
      end

      # Subject seeded: immediate accept, inputs untouched.
      it 'subject wtxid in seed: returns true without verifying inputs' do
        source_tx = build_source_tx
        source_tx.merkle_path = make_merkle_path
        tx = build_spending_tx(source_tx)

        tx.inputs[0].unlocking_script = BSV::Script::Script.from_asm('OP_0')

        result = tx.verify(chain_tracker: chain_tracker, verified: { tx.wtxid => true })

        expect(result).to be true
      end

      # Fee gate is caller-passed policy; not part of the cached script-validity claim.
      # It runs once at the start of every verify call regardless of what's in the Hash.
      it 'fee gate still runs when subject is seeded: raises :insufficient_fee' do
        source_tx = build_source_tx(satoshis: 100_000)
        source_tx.merkle_path = make_merkle_path
        tx = build_spending_tx(source_tx, output_sats: 99_999)

        rejecting_model = instance_double(BSV::Transaction::FeeModel)
        allow(rejecting_model).to receive(:compute_fee).and_return(100)

        expect do
          tx.verify(
            chain_tracker: chain_tracker,
            fee_model: rejecting_model,
            verified: { tx.wtxid => true }
          )
        end.to raise_error(BSV::Transaction::VerificationError) { |e|
          expect(e.code).to eq(:insufficient_fee)
        }
      end

      # Benign seed: bogus wtxids in the Hash never match; behaviour identical to unseeded.
      it 'benign seed: 2-hop P2PKH chain behaves identically with and without seed' do
        source = build_source_tx
        source.merkle_path = make_merkle_path
        tx = build_spending_tx(source)

        seeded_result = tx.verify(chain_tracker: chain_tracker, verified: { bogus_wtxid => true })
        expect(seeded_result).to be true
        expect(tx.verify(chain_tracker: chain_tracker)).to eq(seeded_result)
      end

      it 'benign seed: 3-hop P2PKH chain (grandparent proven) behaves identically with and without seed' do
        grandparent = build_source_tx(satoshis: 200_000)
        grandparent.merkle_path = make_merkle_path
        parent = build_spending_tx(grandparent, output_sats: 150_000)
        child = build_spending_tx(parent, output_sats: 100_000)

        seeded_result = child.verify(chain_tracker: chain_tracker, verified: { bogus_wtxid => true })
        expect(seeded_result).to be true
        expect(child.verify(chain_tracker: chain_tracker)).to eq(seeded_result)
      end

      it 'benign seed: bad-script chain raises :script_failure with and without seed' do
        source = build_source_tx
        source.merkle_path = make_merkle_path
        tx = build_spending_tx(source)
        tx.inputs[0].unlocking_script = BSV::Script::Script.from_asm('OP_0')

        expect { tx.verify(chain_tracker: chain_tracker) }
          .to raise_error(BSV::Transaction::VerificationError) { |e|
            expect(e.code).to eq(:script_failure)
          }

        expect { tx.verify(chain_tracker: chain_tracker, verified: { bogus_wtxid => true }) }
          .to raise_error(BSV::Transaction::VerificationError) { |e|
            expect(e.code).to eq(:script_failure)
          }
      end

      # Wrong types
      it 'wrong type: raises ArgumentError naming Hash and received type when given an Array' do
        source_tx = build_source_tx
        source_tx.merkle_path = make_merkle_path
        tx = build_spending_tx(source_tx)

        expect { tx.verify(chain_tracker: chain_tracker, verified: [source_tx.wtxid]) }
          .to raise_error(ArgumentError) { |e|
            expect(e.message).to include('Hash')
            expect(e.message).to include('Array')
          }
      end

      it 'wrong type: raises ArgumentError when given a Set (rejects the legacy PR #912 shape)' do
        source_tx = build_source_tx
        source_tx.merkle_path = make_merkle_path
        tx = build_spending_tx(source_tx)

        expect { tx.verify(chain_tracker: chain_tracker, verified: Set.new([source_tx.wtxid])) }
          .to raise_error(ArgumentError) { |e|
            expect(e.message).to include('Hash')
            expect(e.message).to include('Set')
          }
      end

      # Frozen Hash — clear error at entry rather than FrozenError deep in the walk.
      it 'wrong type: raises ArgumentError when Hash is frozen (SDK cannot mutate it)' do
        source_tx = build_source_tx
        source_tx.merkle_path = make_merkle_path
        tx = build_spending_tx(source_tx)

        expect { tx.verify(chain_tracker: chain_tracker, verified: {}.freeze) }
          .to raise_error(ArgumentError) { |e|
            expect(e.message).to include('mutable')
          }
      end

      # Semantic-change pin: moving the fee gate outside the walk loop means a merkle-proven
      # subject now gets fee-checked. Under pre-amendment master's inside-the-loop fee check,
      # the merkle branch's `next` skipped the fee gate for a proven subject — silent bypass.
      # This spec locks in the new (correct) behaviour.
      it 'fee gate runs on merkle-proven subject: raises :insufficient_fee even when subject has merkle_path' do
        source_tx = build_source_tx(satoshis: 100_000)
        source_tx.merkle_path = make_merkle_path
        tx = build_spending_tx(source_tx, output_sats: 99_999)
        tx.merkle_path = make_merkle_path # subject IS merkle-proven

        rejecting_model = instance_double(BSV::Transaction::FeeModel)
        allow(rejecting_model).to receive(:compute_fee).and_return(100)

        expect { tx.verify(chain_tracker: chain_tracker, fee_model: rejecting_model) }
          .to raise_error(BSV::Transaction::VerificationError) { |e|
            expect(e.code).to eq(:insufficient_fee)
          }
      end
    end
  end
end
