# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/DescribeClass, RSpec/MultipleDescribes
RSpec.describe 'Tx Phase A: owning-Tx backref, #initialize_copy, invalidator stubs' do
  # rubocop:enable RSpec/DescribeClass, RSpec/MultipleDescribes

  let(:wtxid) { "\x00".b * 32 }

  def make_input
    BSV::Transaction::TransactionInput.new(prev_wtxid: wtxid, prev_tx_out_index: 0)
  end

  def make_output(satoshis: 1000)
    script = BSV::Script::Script.from_asm('OP_RETURN')
    BSV::Transaction::TransactionOutput.new(satoshis: satoshis, locking_script: script)
  end

  def make_tx
    BSV::Transaction::Tx.new
  end

  describe 'Tx#add_input — owning-Tx backref' do
    it 'sets @owning_tx on the input when added' do
      tx = make_tx
      input = make_input
      tx.add_input(input)
      expect(input.instance_variable_get(:@owning_tx)).to equal(tx)
    end

    it 'raises ArgumentError when the input is already attached to a different Tx' do
      tx1 = make_tx
      tx2 = make_tx
      input = make_input
      tx1.add_input(input)
      expect { tx2.add_input(input) }.to raise_error(ArgumentError, /already attached/)
    end

    it 'does NOT raise when the same input is re-added to the same Tx (idempotent)' do
      tx = make_tx
      input = make_input
      tx.add_input(input)
      expect { tx.add_input(input) }.not_to raise_error
    end
  end

  describe 'Tx#add_output — owning-Tx backref' do
    it 'sets @owning_tx on the output when added' do
      tx = make_tx
      output = make_output
      tx.add_output(output)
      expect(output.instance_variable_get(:@owning_tx)).to equal(tx)
    end

    it 'raises ArgumentError when the output is already attached to a different Tx' do
      tx1 = make_tx
      tx2 = make_tx
      output = make_output
      tx1.add_output(output)
      expect { tx2.add_output(output) }.to raise_error(ArgumentError, /already attached/)
    end

    it 'does NOT raise when the same output is re-added to the same Tx (idempotent)' do
      tx = make_tx
      output = make_output
      tx.add_output(output)
      expect { tx.add_output(output) }.not_to raise_error
    end
  end

  describe 'Tx#initialize_copy (#dup)' do
    let(:tx) do
      t = make_tx
      t.add_input(make_input)
      t.add_input(make_input)
      t.add_output(make_output(satoshis: 100))
      t.add_output(make_output(satoshis: 200))
      t
    end

    it 'produces independent inputs — mutating the dup does not affect the original' do
      dup_tx = tx.dup
      dup_tx.inputs[0].sequence = 42
      expect(tx.inputs[0].sequence).not_to eq(42)
    end

    it 'produces independent inputs — mutating the original does not affect the dup' do
      dup_tx = tx.dup
      tx.inputs[0].sequence = 99
      expect(dup_tx.inputs[0].sequence).not_to eq(99)
    end

    it 'produces independent outputs — mutating the dup does not affect the original' do
      dup_tx = tx.dup
      dup_tx.outputs[0].satoshis = 9999
      expect(tx.outputs[0].satoshis).to eq(100)
    end

    it 'produces independent outputs — mutating the original does not affect the dup' do
      dup_tx = tx.dup
      tx.outputs[1].satoshis = 8888
      expect(dup_tx.outputs[1].satoshis).to eq(200)
    end

    it 'rebinds @owning_tx on duplicated inputs to the new Tx' do
      dup_tx = tx.dup
      dup_tx.inputs.each do |i|
        expect(i.instance_variable_get(:@owning_tx)).to equal(dup_tx)
      end
    end

    it 'rebinds @owning_tx on duplicated outputs to the new Tx' do
      dup_tx = tx.dup
      dup_tx.outputs.each do |o|
        expect(o.instance_variable_get(:@owning_tx)).to equal(dup_tx)
      end
    end

    it 'leaves the original inputs still owned by the original Tx' do
      dup_tx = tx.dup # rubocop:disable Lint/UselessAssignment
      tx.inputs.each do |i|
        expect(i.instance_variable_get(:@owning_tx)).to equal(tx)
      end
    end
  end

  describe 'TransactionInput#initialize_copy' do
    it 'clears @owning_tx on a duped input' do
      tx = make_tx
      input = make_input
      tx.add_input(input)
      duped = input.dup
      expect(duped.instance_variable_get(:@owning_tx)).to be_nil
    end
  end

  describe 'TransactionOutput#initialize_copy' do
    it 'clears @owning_tx on a duped output' do
      tx = make_tx
      output = make_output
      tx.add_output(output)
      duped = output.dup
      expect(duped.instance_variable_get(:@owning_tx)).to be_nil
    end
  end

  describe 'Tx#invalidate_caches' do
    it 'returns self' do
      tx = make_tx
      expect(tx.invalidate_caches).to equal(tx)
    end
  end

  describe 'private slice-invalidator stubs' do
    it 'defines invalidate_sequence_components_cache as a private method' do
      expect(BSV::Transaction::Tx.private_method_defined?(:invalidate_sequence_components_cache)).to be(true)
    end

    it 'defines invalidate_outputs_components_cache as a private method' do
      expect(BSV::Transaction::Tx.private_method_defined?(:invalidate_outputs_components_cache)).to be(true)
    end

    it 'defines invalidate_wire_cache as a private method' do
      expect(BSV::Transaction::Tx.private_method_defined?(:invalidate_wire_cache)).to be(true)
    end
  end
end

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Tx Phase B: Layer 1 per-struct binary memos' do
  # rubocop:enable RSpec/DescribeClass

  let(:wtxid) { "\x00".b * 32 }

  def make_input(sequence: 0xFFFFFFFF)
    BSV::Transaction::TransactionInput.new(prev_wtxid: wtxid, prev_tx_out_index: 0, sequence: sequence)
  end

  def make_output(satoshis: 1000)
    script = BSV::Script::Script.from_asm('OP_RETURN')
    BSV::Transaction::TransactionOutput.new(satoshis: satoshis, locking_script: script)
  end

  def make_tx_with_input_and_output
    tx = BSV::Transaction::Tx.new
    input = make_input
    output = make_output
    tx.add_input(input)
    tx.add_output(output)
    [tx, input, output]
  end

  describe 'TransactionInput#outpoint_binary' do
    let(:input) { make_input }

    it 'memoises — returns the same object on repeated calls' do
      first = input.outpoint_binary
      second = input.outpoint_binary
      expect(first).to equal(second)
    end

    it 'returns a frozen binary string' do
      result = input.outpoint_binary
      expect(result).to be_frozen
      expect(result.encoding).to eq(Encoding::BINARY)
    end

    it 'is 36 bytes (32-byte wtxid + 4-byte index)' do
      expect(input.outpoint_binary.bytesize).to eq(36)
    end
  end

  describe 'TransactionInput#to_binary' do
    let(:input) { make_input }

    it 'memoises — returns the same object on repeated calls' do
      first = input.to_binary
      second = input.to_binary
      expect(first).to equal(second)
    end

    it 'returns a frozen binary string' do
      expect(input.to_binary).to be_frozen
    end
  end

  describe 'TransactionOutput#to_binary' do
    let(:output) { make_output }

    it 'memoises — returns the same object on repeated calls' do
      first = output.to_binary
      second = output.to_binary
      expect(first).to equal(second)
    end

    it 'returns a frozen binary string' do
      expect(output.to_binary).to be_frozen
    end
  end

  describe 'L1 memo invalidation on mutation' do
    describe 'TransactionInput#sequence=' do
      it 'invalidates #to_binary so the next call recomputes' do
        input = make_input(sequence: 0xFFFFFFFF)
        before = input.to_binary
        input.sequence = 0x00000001
        after = input.to_binary
        expect(before).not_to equal(after)
      end

      it 'new #to_binary encodes the updated sequence' do
        input = make_input(sequence: 0xFFFFFFFF)
        input.sequence = 0x00000001
        expect(input.to_binary[-4..]).to eq([0x00000001].pack('V'))
      end
    end

    describe 'TransactionInput#unlocking_script=' do
      it 'invalidates #to_binary so the next call recomputes' do
        input = make_input
        before = input.to_binary
        new_script = BSV::Script::Script.from_asm('OP_1')
        input.unlocking_script = new_script
        after = input.to_binary
        expect(before).not_to equal(after)
      end

      it 'new #to_binary encodes the updated unlocking script bytes' do
        input = make_input
        new_script = BSV::Script::Script.from_asm('OP_1')
        input.unlocking_script = new_script
        expect(input.to_binary).to include(new_script.to_binary)
      end
    end

    describe 'TransactionOutput#satoshis=' do
      it 'invalidates #to_binary so the next call recomputes' do
        output = make_output(satoshis: 1000)
        before = output.to_binary
        output.satoshis = 9999
        after = output.to_binary
        expect(before).not_to equal(after)
      end

      it 'new #to_binary encodes the updated satoshi value' do
        output = make_output(satoshis: 1000)
        output.satoshis = 9999
        expect(output.to_binary[0, 8]).to eq([9999].pack('Q<'))
      end
    end

    describe 'TransactionOutput#locking_script=' do
      it 'invalidates #to_binary so the next call recomputes' do
        output = make_output
        before = output.to_binary
        new_script = BSV::Script::Script.from_asm('OP_1')
        output.locking_script = new_script
        after = output.to_binary
        expect(before).not_to equal(after)
      end

      it 'new #to_binary encodes the updated locking script bytes' do
        output = make_output
        new_script = BSV::Script::Script.from_asm('OP_1')
        output.locking_script = new_script
        expect(output.to_binary).to include(new_script.to_binary)
      end
    end
  end

  describe 'setter bubble verification (spy assertions)' do
    let(:tx) { BSV::Transaction::Tx.new }
    let(:input) do
      i = make_input
      tx.add_input(i)
      i
    end
    let(:output) do
      o = make_output
      tx.add_output(o)
      o
    end

    before do
      # Force lazy let evaluation BEFORE installing spies so that add_input /
      # add_output (which now call invalidate_caches) are not counted by the spy.
      input
      output
      allow(tx).to receive(:invalidate_sequence_components_cache).and_call_original
      allow(tx).to receive(:invalidate_outputs_components_cache).and_call_original
      allow(tx).to receive(:invalidate_wire_cache).and_call_original
    end

    describe 'input.sequence=' do
      it 'calls invalidate_sequence_components_cache exactly once on owning Tx' do
        input.sequence = 42
        expect(tx).to have_received(:invalidate_sequence_components_cache).once
      end

      it 'calls invalidate_wire_cache exactly once on owning Tx' do
        input.sequence = 42
        expect(tx).to have_received(:invalidate_wire_cache).once
      end

      it 'does NOT call invalidate_outputs_components_cache' do
        input.sequence = 42
        expect(tx).not_to have_received(:invalidate_outputs_components_cache)
      end
    end

    describe 'input.unlocking_script=' do
      it 'calls invalidate_wire_cache exactly once on owning Tx' do
        input.unlocking_script = BSV::Script::Script.from_asm('OP_1')
        expect(tx).to have_received(:invalidate_wire_cache).once
      end

      it 'does NOT call invalidate_sequence_components_cache' do
        input.unlocking_script = BSV::Script::Script.from_asm('OP_1')
        expect(tx).not_to have_received(:invalidate_sequence_components_cache)
      end

      it 'does NOT call invalidate_outputs_components_cache' do
        input.unlocking_script = BSV::Script::Script.from_asm('OP_1')
        expect(tx).not_to have_received(:invalidate_outputs_components_cache)
      end
    end

    describe 'output.satoshis=' do
      it 'calls invalidate_outputs_components_cache exactly once on owning Tx' do
        the_output = output
        the_output.satoshis = 5000
        expect(tx).to have_received(:invalidate_outputs_components_cache).once
      end

      it 'calls invalidate_wire_cache exactly once on owning Tx' do
        the_output = output
        the_output.satoshis = 5000
        expect(tx).to have_received(:invalidate_wire_cache).once
      end
    end

    describe 'output.locking_script=' do
      it 'calls invalidate_outputs_components_cache exactly once on owning Tx' do
        the_output = output
        the_output.locking_script = BSV::Script::Script.from_asm('OP_1')
        expect(tx).to have_received(:invalidate_outputs_components_cache).once
      end

      it 'calls invalidate_wire_cache exactly once on owning Tx' do
        the_output = output
        the_output.locking_script = BSV::Script::Script.from_asm('OP_1')
        expect(tx).to have_received(:invalidate_wire_cache).once
      end
    end
  end

  describe 'free-floating struct (no @owning_tx)' do
    it 'setting sequence= on a detached input does not raise' do
      input = make_input
      expect { input.sequence = 0 }.not_to raise_error
    end

    it 'setting unlocking_script= on a detached input does not raise' do
      input = make_input
      expect { input.unlocking_script = BSV::Script::Script.from_asm('OP_1') }.not_to raise_error
    end

    it 'setting satoshis= on a detached output does not raise' do
      output = make_output
      expect { output.satoshis = 0 }.not_to raise_error
    end

    it 'setting locking_script= on a detached output does not raise' do
      output = make_output
      expect { output.locking_script = BSV::Script::Script.from_asm('OP_1') }.not_to raise_error
    end
  end
end

# Simple locking script used in Phase C contract-table specs.
# Defined at file scope to avoid RSpec/LeakyConstantDeclaration inside the block.
PHC_LOCK = BSV::Script::Script.from_asm(
  "OP_DUP OP_HASH160 #{'ab' * 20} OP_EQUALVERIFY OP_CHECKSIG"
)

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Tx Phase C: Layer 3 component-hash memos — §3 contract table' do
  # rubocop:enable RSpec/DescribeClass

  def make_input(sequence: 0xFFFFFFFF)
    input = BSV::Transaction::TransactionInput.new(
      prev_wtxid: "\x01".b * 32,
      prev_tx_out_index: 0,
      sequence: sequence
    )
    input.source_satoshis = 1000
    input.source_locking_script = PHC_LOCK
    input
  end

  def make_output(satoshis: 900)
    BSV::Transaction::TransactionOutput.new(satoshis: satoshis, locking_script: PHC_LOCK)
  end

  def build_wired_tx
    tx = BSV::Transaction::Tx.new
    tx.add_input(make_input)
    tx.add_output(make_output)
    tx
  end

  describe 'hash_sequence invalidation on input.sequence=' do
    it 'next hash_sequence call recomputes (not the same object) after sequence mutation' do
      tx = build_wired_tx

      # Warm the L3 cache
      tx.sighash(0, BSV::Transaction::Sighash::ALL_FORK_ID)
      pre = tx.send(:hash_sequence, false, BSV::Transaction::Sighash::ALL)

      tx.inputs[0].sequence = 0x00000001

      post = tx.send(:hash_sequence, false, BSV::Transaction::Sighash::ALL)

      expect(pre).not_to equal(post)
    end
  end

  describe 'hash_outputs ALL invalidation on output.satoshis=' do
    it 'next hash_outputs(ALL) call recomputes after satoshis mutation' do
      tx = build_wired_tx

      tx.sighash(0, BSV::Transaction::Sighash::ALL_FORK_ID)
      pre = tx.send(:hash_outputs, BSV::Transaction::Sighash::ALL, 0)

      tx.outputs[0].satoshis = 1

      post = tx.send(:hash_outputs, BSV::Transaction::Sighash::ALL, 0)

      expect(pre).not_to equal(post)
    end
  end

  describe 'hash_outputs ALL invalidation on output.locking_script=' do
    it 'next hash_outputs(ALL) call recomputes after locking_script mutation' do
      tx = build_wired_tx

      tx.sighash(0, BSV::Transaction::Sighash::ALL_FORK_ID)
      pre = tx.send(:hash_outputs, BSV::Transaction::Sighash::ALL, 0)

      tx.outputs[0].locking_script = BSV::Script::Script.from_asm('OP_1')

      post = tx.send(:hash_outputs, BSV::Transaction::Sighash::ALL, 0)

      expect(pre).not_to equal(post)
    end
  end

  describe 'hash_outputs SINGLE invalidation on output.locking_script=' do
    it 'next hash_outputs(SINGLE, 0) call recomputes after locking_script mutation' do
      tx = build_wired_tx

      # Warm SINGLE cache for idx 0
      tx.sighash(0, BSV::Transaction::Sighash::SINGLE_FORK_ID)
      pre = tx.send(:hash_outputs, BSV::Transaction::Sighash::SINGLE, 0)

      tx.outputs[0].locking_script = BSV::Script::Script.from_asm('OP_1')

      post = tx.send(:hash_outputs, BSV::Transaction::Sighash::SINGLE, 0)

      expect(pre).not_to equal(post)
    end
  end

  describe 'add_input — all three components recompute' do
    it 'recomputes hash_prevouts after add_input' do
      tx = build_wired_tx

      tx.sighash(0, BSV::Transaction::Sighash::ALL_FORK_ID)
      pre = tx.send(:hash_prevouts, false)

      new_input = make_input
      tx.add_input(new_input)

      post = tx.send(:hash_prevouts, false)

      expect(pre).not_to equal(post)
    end

    it 'recomputes hash_sequence after add_input' do
      tx = build_wired_tx

      tx.sighash(0, BSV::Transaction::Sighash::ALL_FORK_ID)
      pre = tx.send(:hash_sequence, false, BSV::Transaction::Sighash::ALL)

      new_input = make_input
      tx.add_input(new_input)

      post = tx.send(:hash_sequence, false, BSV::Transaction::Sighash::ALL)

      expect(pre).not_to equal(post)
    end
  end

  describe 'add_output — hash_outputs recomputes' do
    it 'recomputes hash_outputs(ALL) after add_output' do
      tx = build_wired_tx

      tx.sighash(0, BSV::Transaction::Sighash::ALL_FORK_ID)
      pre = tx.send(:hash_outputs, BSV::Transaction::Sighash::ALL, 0)

      tx.add_output(make_output(satoshis: 50))

      post = tx.send(:hash_outputs, BSV::Transaction::Sighash::ALL, 0)

      expect(pre).not_to equal(post)
    end
  end

  describe 'invalidate_caches — public escape hatch clears everything' do
    it 'after invalidate_caches, hash_prevouts recomputes' do
      tx = build_wired_tx

      tx.sighash(0, BSV::Transaction::Sighash::ALL_FORK_ID)
      pre = tx.send(:hash_prevouts, false)

      tx.invalidate_caches

      post = tx.send(:hash_prevouts, false)

      expect(pre).not_to equal(post)
    end

    it 'after invalidate_caches, hash_sequence recomputes' do
      tx = build_wired_tx

      tx.sighash(0, BSV::Transaction::Sighash::ALL_FORK_ID)
      pre = tx.send(:hash_sequence, false, BSV::Transaction::Sighash::ALL)

      tx.invalidate_caches

      post = tx.send(:hash_sequence, false, BSV::Transaction::Sighash::ALL)

      expect(pre).not_to equal(post)
    end

    it 'after invalidate_caches, hash_outputs(ALL) recomputes' do
      tx = build_wired_tx

      tx.sighash(0, BSV::Transaction::Sighash::ALL_FORK_ID)
      pre = tx.send(:hash_outputs, BSV::Transaction::Sighash::ALL, 0)

      tx.invalidate_caches

      post = tx.send(:hash_outputs, BSV::Transaction::Sighash::ALL, 0)

      expect(pre).not_to equal(post)
    end

    it 'returns self' do
      tx = build_wired_tx
      expect(tx.invalidate_caches).to equal(tx)
    end
  end

  describe 'memoisation — same object returned on repeated calls (cache hit)' do
    it 'hash_prevouts returns the same object on second call' do
      tx = build_wired_tx

      first = tx.send(:hash_prevouts, false)
      second = tx.send(:hash_prevouts, false)

      expect(first).to equal(second)
    end

    it 'hash_sequence returns the same object on second call' do
      tx = build_wired_tx

      first = tx.send(:hash_sequence, false, BSV::Transaction::Sighash::ALL)
      second = tx.send(:hash_sequence, false, BSV::Transaction::Sighash::ALL)

      expect(first).to equal(second)
    end

    it 'hash_outputs(ALL) returns the same object on second call' do
      tx = build_wired_tx

      first = tx.send(:hash_outputs, BSV::Transaction::Sighash::ALL, 0)
      second = tx.send(:hash_outputs, BSV::Transaction::Sighash::ALL, 0)

      expect(first).to equal(second)
    end

    it 'ZERO_HASH branches (anyone_can_pay=true) are never cached — each call returns frozen ZERO_HASH' do
      tx = build_wired_tx

      first = tx.send(:hash_prevouts, true)
      second = tx.send(:hash_prevouts, true)

      expect(first).to eq("\x00".b * 32)
      expect(first).to be_frozen
      expect(first).to equal(second) # same constant object, not independently memoised
    end

    it 'cached hashes are frozen' do
      tx = build_wired_tx

      expect(tx.send(:hash_prevouts, false)).to be_frozen
      expect(tx.send(:hash_sequence, false, BSV::Transaction::Sighash::ALL)).to be_frozen
      expect(tx.send(:hash_outputs, BSV::Transaction::Sighash::ALL, 0)).to be_frozen
    end
  end
end
