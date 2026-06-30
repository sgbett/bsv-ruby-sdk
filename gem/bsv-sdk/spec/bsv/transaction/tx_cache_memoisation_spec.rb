# frozen_string_literal: true

require 'spec_helper'

# Minimal P2PKH-shaped locking script (no real key needed for sighash probing).
# Defined at file scope to avoid RSpec/LeakyConstantDeclaration inside the block.
CACHE_SPEC_LOCK = BSV::Script::Script.from_asm(
  "OP_DUP OP_HASH160 #{'00' * 20} OP_EQUALVERIFY OP_CHECKSIG"
)

# Script used by Phase D wire-cache specs; defined at file scope to avoid
# RSpec/LeakyConstantDeclaration inside the describe block.
WIRE_SPEC_LOCK = BSV::Script::Script.from_asm(
  "OP_DUP OP_HASH160 #{'cd' * 20} OP_EQUALVERIFY OP_CHECKSIG"
)

# rubocop:disable RSpec/DescribeClass, RSpec/MultipleDescribes
RSpec.describe 'Tx sighash cache — structural regression (Phase C)' do
  # rubocop:enable RSpec/DescribeClass, RSpec/MultipleDescribes

  # Builds an n_inputs/n_outputs Tx with all source data wired so that
  # #sighash can be called for every input without external dependencies.
  def build_tx(n_inputs:, n_outputs:)
    tx = BSV::Transaction::Tx.new

    n_inputs.times do |i|
      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: ([i].pack('V') + ("\x00".b * 28)),
        prev_tx_out_index: 0
      )
      input.source_satoshis = 1000
      input.source_locking_script = CACHE_SPEC_LOCK
      tx.add_input(input)
    end

    n_outputs.times do |i|
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 100 + i,
                      locking_script: CACHE_SPEC_LOCK
                    ))
    end

    tx
  end

  describe 'linear sha256d call count (O(N+M) not O(N×(N+M)))' do
    # Count sha256d calls across N sighash invocations on a 10×10 tx.
    # Expected: 3 component-buffer hashes + 10 preimage hashes = 13 total.
    #   - hash_prevouts: 1 (memoised for inputs 1..9)
    #   - hash_sequence: 1 (memoised for inputs 1..9)
    #   - hash_outputs(ALL): 1 (memoised for inputs 1..9)
    #   - per-input preimage digest: 10 (one per sighash call, never memoised at this layer)
    it 'computes each component hash exactly once across N=10 sighash calls (3 components + 10 preimage = 13 total)' do
      tx = build_tx(n_inputs: 10, n_outputs: 10)
      allow(BSV::Primitives::Digest).to receive(:sha256d).and_call_original

      10.times { |i| tx.sighash(i, BSV::Transaction::Sighash::ALL_FORK_ID) }

      expect(BSV::Primitives::Digest).to have_received(:sha256d).exactly(13).times
    end
  end

  describe 'recomputation after invalidation' do
    it 'recomputes all component hashes after invalidate_caches (another 3 components + 10 preimages = 13 more)' do
      tx = build_tx(n_inputs: 10, n_outputs: 10)

      # Warm the cache
      10.times { |i| tx.sighash(i, BSV::Transaction::Sighash::ALL_FORK_ID) }

      allow(BSV::Primitives::Digest).to receive(:sha256d).and_call_original

      tx.invalidate_caches

      10.times { |i| tx.sighash(i, BSV::Transaction::Sighash::ALL_FORK_ID) }

      expect(BSV::Primitives::Digest).to have_received(:sha256d).exactly(13).times
    end
  end

  describe 'recomputation after add_input' do
    it 'recomputes component hashes after adding an input (cache invalidated by add_input)' do
      tx = build_tx(n_inputs: 3, n_outputs: 3)

      # Warm the cache
      3.times { |i| tx.sighash(i, BSV::Transaction::Sighash::ALL_FORK_ID) }

      allow(BSV::Primitives::Digest).to receive(:sha256d).and_call_original

      new_input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: "\xAB".b * 32,
        prev_tx_out_index: 0
      )
      new_input.source_satoshis = 500
      new_input.source_locking_script = CACHE_SPEC_LOCK
      tx.add_input(new_input)

      # All 4 inputs × sighash → 3 fresh component hashes + 4 preimage hashes = 7
      4.times { |i| tx.sighash(i, BSV::Transaction::Sighash::ALL_FORK_ID) }

      expect(BSV::Primitives::Digest).to have_received(:sha256d).exactly(7).times
    end
  end

  describe 'FORKID gate sits before any cache lookup' do
    it 'raises on non-FORKID type even when a FORKID variant was cached' do
      tx = build_tx(n_inputs: 2, n_outputs: 2)
      tx.sighash(0, BSV::Transaction::Sighash::ALL_FORK_ID) # populate cache

      expect do
        tx.sighash(0, BSV::Transaction::Sighash::ALL)
      end.to raise_error(ArgumentError, /FORKID/)
    end
  end

  describe 'cross-input independence (unlocking_script does not enter L3 cache)' do
    it 'signing input 0 (setting unlocking_script) does not change sighash for input 1' do
      tx = build_tx(n_inputs: 2, n_outputs: 1)

      pre_sighash_1 = tx.sighash(1, BSV::Transaction::Sighash::ALL_FORK_ID)

      # Simulate signing: set an unlocking script on input 0
      tx.inputs[0].unlocking_script = BSV::Script::Script.from_asm('OP_1')

      post_sighash_1 = tx.sighash(1, BSV::Transaction::Sighash::ALL_FORK_ID)

      expect(post_sighash_1).to eq(pre_sighash_1)
    end
  end

  describe 'SIGHASH_SINGLE out-of-range — no stale ZERO_HASH cached' do
    it 'returns a different (real) hash for idx 2 after add_output makes it in-range' do
      tx = build_tx(n_inputs: 3, n_outputs: 1)

      # Input index 2 is out-of-range (only 1 output at index 0) — should behave
      # like ZERO_HASH internally (BIP-143 spec). We compare the sighash before
      # and after add_output to confirm the cache is not stale.
      sighash_before = tx.sighash(2, BSV::Transaction::Sighash::SINGLE_FORK_ID)

      # Add outputs at index 1 and 2 to bring index 2 in range
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 200,
                      locking_script: CACHE_SPEC_LOCK
                    ))
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 300,
                      locking_script: CACHE_SPEC_LOCK
                    ))

      sighash_after = tx.sighash(2, BSV::Transaction::Sighash::SINGLE_FORK_ID)

      expect(sighash_after).not_to eq(sighash_before)
    end
  end
end

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Tx Phase D: Layer 2 wire memos (Tx#to_binary, Tx#wtxid)' do
  # rubocop:enable RSpec/DescribeClass

  def build_wire_tx
    tx = BSV::Transaction::Tx.new
    input = BSV::Transaction::TransactionInput.new(
      prev_wtxid: "\x01".b * 32,
      prev_tx_out_index: 0
    )
    tx.add_input(input)
    tx.add_output(BSV::Transaction::TransactionOutput.new(
                    satoshis: 900,
                    locking_script: WIRE_SPEC_LOCK
                  ))
    tx
  end

  describe 'Tx#to_binary memoisation' do
    it 'returns the same object on repeated calls' do
      tx = build_wire_tx
      first = tx.to_binary
      second = tx.to_binary
      expect(first).to equal(second)
    end

    it 'returns a binary-encoded string' do
      expect(build_wire_tx.to_binary.encoding).to eq(Encoding::BINARY)
    end

    it 'returns a frozen string' do
      expect(build_wire_tx.to_binary).to be_frozen
    end

    it 'returns a new object after invalidate_caches' do
      tx = build_wire_tx
      before = tx.to_binary
      tx.invalidate_caches
      after = tx.to_binary
      expect(before).not_to equal(after)
    end
  end

  describe 'Tx#wtxid memoisation' do
    it 'returns the same object on repeated calls' do
      tx = build_wire_tx
      first = tx.wtxid
      second = tx.wtxid
      expect(first).to equal(second)
    end

    it 'is 32 bytes' do
      expect(build_wire_tx.wtxid.bytesize).to eq(32)
    end

    it 'is frozen' do
      expect(build_wire_tx.wtxid).to be_frozen
    end

    it 'dtxid_hex is the display-order (reversed) hex of wtxid' do
      tx = build_wire_tx
      expect(tx.dtxid_hex).to eq(tx.wtxid.reverse.unpack1('H*'))
    end
  end

  describe 'wire invalidation from mutation' do
    it 'wtxid changes after input.unlocking_script= (signing flow)' do
      tx = build_wire_tx
      pre = tx.wtxid
      tx.inputs[0].unlocking_script = BSV::Script::Script.from_asm('OP_1')
      post = tx.wtxid
      expect(pre).not_to equal(post)
      expect(pre).not_to eq(post)
    end

    it 'to_binary changes after input.unlocking_script=' do
      tx = build_wire_tx
      pre = tx.to_binary
      tx.inputs[0].unlocking_script = BSV::Script::Script.from_asm('OP_1')
      post = tx.to_binary
      expect(pre).not_to equal(post)
    end

    it 'wtxid changes after output.satoshis=' do
      tx = build_wire_tx
      pre = tx.wtxid
      tx.outputs[0].satoshis = 1
      post = tx.wtxid
      expect(pre).not_to equal(post)
    end
  end
end
