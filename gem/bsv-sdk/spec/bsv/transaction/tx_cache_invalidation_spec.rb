# frozen_string_literal: true

require 'spec_helper'

# Locking scripts used across the invalidation contract specs.
# Defined at file scope to avoid RSpec/LeakyConstantDeclaration inside blocks.
INV_LOCK = BSV::Script::Script.from_asm(
  "OP_DUP OP_HASH160 #{'ab' * 20} OP_EQUALVERIFY OP_CHECKSIG"
)

# Shared examples for "warm a cache, mutate, assert cache missed".
# The caller must define `let(:mutate)` as a proc/lambda; each shared example
# invokes it as `mutate.call(tx)` to perform the mutation on the yielded tx.
# We use a proc parameter rather than a block to avoid the describe-time evaluation issue.

# rubocop:disable RSpec/DescribeClass, RSpec/MultipleDescribes
RSpec.describe 'Tx cache invalidation — §3 contract table' do
  # rubocop:enable RSpec/DescribeClass, RSpec/MultipleDescribes

  def make_input(sequence: 0xFFFFFFFF, wtxid_byte: "\x01")
    input = BSV::Transaction::TransactionInput.new(
      prev_wtxid: (wtxid_byte.b * 32),
      prev_tx_out_index: 0,
      sequence: sequence
    )
    input.source_satoshis = 1000
    input.source_locking_script = INV_LOCK
    input
  end

  def make_output(satoshis: 900)
    BSV::Transaction::TransactionOutput.new(satoshis: satoshis, locking_script: INV_LOCK)
  end

  def build_wired_tx
    tx = BSV::Transaction::Tx.new
    tx.add_input(make_input)
    tx.add_output(make_output)
    tx
  end

  # Shared examples -----------------------------------------------------------

  shared_examples 'invalidates L3 hash_sequence' do
    it 'next hash_sequence call recomputes (not the same object)' do
      tx = build_wired_tx
      tx.sighash(0, BSV::Transaction::Sighash::ALL_FORK_ID) # warm cache
      pre = tx.send(:hash_sequence, false, BSV::Transaction::Sighash::ALL)
      mutate.call(tx)
      post = tx.send(:hash_sequence, false, BSV::Transaction::Sighash::ALL)
      expect(pre).not_to equal(post)
    end
  end

  shared_examples 'does not invalidate L3 hash_sequence' do
    it 'hash_sequence is the same object (cache not invalidated)' do
      tx = build_wired_tx
      tx.sighash(0, BSV::Transaction::Sighash::ALL_FORK_ID) # warm cache
      pre = tx.send(:hash_sequence, false, BSV::Transaction::Sighash::ALL)
      mutate.call(tx)
      post = tx.send(:hash_sequence, false, BSV::Transaction::Sighash::ALL)
      expect(pre).to equal(post)
    end
  end

  shared_examples 'invalidates L3 hash_outputs_all' do
    it 'next hash_outputs(ALL) call recomputes (not the same object)' do
      tx = build_wired_tx
      tx.sighash(0, BSV::Transaction::Sighash::ALL_FORK_ID) # warm cache
      pre = tx.send(:hash_outputs, BSV::Transaction::Sighash::ALL, 0)
      mutate.call(tx)
      post = tx.send(:hash_outputs, BSV::Transaction::Sighash::ALL, 0)
      expect(pre).not_to equal(post)
    end
  end

  shared_examples 'does not invalidate L3 hash_outputs_all' do
    it 'hash_outputs(ALL) is the same object (cache not invalidated)' do
      tx = build_wired_tx
      tx.sighash(0, BSV::Transaction::Sighash::ALL_FORK_ID) # warm cache
      pre = tx.send(:hash_outputs, BSV::Transaction::Sighash::ALL, 0)
      mutate.call(tx)
      post = tx.send(:hash_outputs, BSV::Transaction::Sighash::ALL, 0)
      expect(pre).to equal(post)
    end
  end

  shared_examples 'invalidates L2 wire cache' do
    it 'to_binary is a new object after mutation' do
      tx = build_wired_tx
      pre = tx.to_binary
      mutate.call(tx)
      post = tx.to_binary
      expect(pre).not_to equal(post)
    end

    it 'wtxid is a new object after mutation' do
      tx = build_wired_tx
      pre = tx.wtxid
      mutate.call(tx)
      post = tx.wtxid
      expect(pre).not_to equal(post)
    end
  end

  # Contract row: Tx#add_input — all cache layers ----------------------------

  describe 'Tx#add_input — all cache layers' do
    let(:mutate) { ->(tx) { tx.add_input(make_input(wtxid_byte: "\x02")) } }

    it_behaves_like 'invalidates L3 hash_sequence'
    it_behaves_like 'invalidates L3 hash_outputs_all'
    it_behaves_like 'invalidates L2 wire cache'

    it 'recomputes hash_prevouts after add_input' do
      tx = build_wired_tx
      tx.sighash(0, BSV::Transaction::Sighash::ALL_FORK_ID)
      pre = tx.send(:hash_prevouts, false)
      tx.add_input(make_input(wtxid_byte: "\x02"))
      post = tx.send(:hash_prevouts, false)
      expect(pre).not_to equal(post)
    end
  end

  # Contract row: Tx#add_output — all cache layers ---------------------------

  describe 'Tx#add_output — all cache layers' do
    let(:mutate) { ->(tx) { tx.add_output(make_output(satoshis: 50)) } }

    it_behaves_like 'invalidates L3 hash_outputs_all'
    it_behaves_like 'invalidates L2 wire cache'
  end

  # Contract row: TransactionInput#sequence= — hash_sequence + L2 -----------

  describe 'TransactionInput#sequence=' do
    let(:mutate) { ->(tx) { tx.inputs[0].sequence = 0x00000001 } }

    it_behaves_like 'invalidates L3 hash_sequence'
    it_behaves_like 'invalidates L2 wire cache'
    it_behaves_like 'does not invalidate L3 hash_outputs_all'

    it 'calls invalidate_sequence_components_cache exactly once on owning Tx' do
      tx = build_wired_tx
      allow(tx).to receive(:invalidate_sequence_components_cache).and_call_original
      tx.inputs[0].sequence = 42
      expect(tx).to have_received(:invalidate_sequence_components_cache).once
    end

    it 'calls invalidate_wire_cache exactly once on owning Tx' do
      tx = build_wired_tx
      allow(tx).to receive(:invalidate_wire_cache).and_call_original
      tx.inputs[0].sequence = 42
      expect(tx).to have_received(:invalidate_wire_cache).once
    end

    it 'does NOT call invalidate_outputs_components_cache' do
      tx = build_wired_tx
      allow(tx).to receive(:invalidate_outputs_components_cache).and_call_original
      tx.inputs[0].sequence = 42
      expect(tx).not_to have_received(:invalidate_outputs_components_cache)
    end
  end

  # Contract row: TransactionInput#unlocking_script= — wire only -------------

  describe 'TransactionInput#unlocking_script= — wire only (NOT sighash)' do
    let(:mutate) { ->(tx) { tx.inputs[0].unlocking_script = BSV::Script::Script.from_asm('OP_1') } }

    it_behaves_like 'invalidates L2 wire cache'
    it_behaves_like 'does not invalidate L3 hash_sequence'
    it_behaves_like 'does not invalidate L3 hash_outputs_all'

    it 'signing input 0 does not change the sighash for input 1 (cross-input independence)' do
      tx = BSV::Transaction::Tx.new
      2.times { |i| tx.add_input(make_input(wtxid_byte: [i + 1].pack('C'))) }
      tx.add_output(make_output)

      pre = tx.sighash(1, BSV::Transaction::Sighash::ALL_FORK_ID)
      tx.inputs[0].unlocking_script = BSV::Script::Script.from_asm('OP_1')
      post = tx.sighash(1, BSV::Transaction::Sighash::ALL_FORK_ID)

      expect(post).to eq(pre)
    end

    it 'calls invalidate_wire_cache exactly once on owning Tx' do
      tx = build_wired_tx
      allow(tx).to receive(:invalidate_wire_cache).and_call_original
      tx.inputs[0].unlocking_script = BSV::Script::Script.from_asm('OP_1')
      expect(tx).to have_received(:invalidate_wire_cache).once
    end

    it 'does NOT call invalidate_sequence_components_cache' do
      tx = build_wired_tx
      allow(tx).to receive(:invalidate_sequence_components_cache).and_call_original
      tx.inputs[0].unlocking_script = BSV::Script::Script.from_asm('OP_1')
      expect(tx).not_to have_received(:invalidate_sequence_components_cache)
    end

    it 'does NOT call invalidate_outputs_components_cache' do
      tx = build_wired_tx
      allow(tx).to receive(:invalidate_outputs_components_cache).and_call_original
      tx.inputs[0].unlocking_script = BSV::Script::Script.from_asm('OP_1')
      expect(tx).not_to have_received(:invalidate_outputs_components_cache)
    end
  end

  # Contract row: TransactionOutput#satoshis= — outputs + L2 ----------------

  describe 'TransactionOutput#satoshis=' do
    let(:mutate) { ->(tx) { tx.outputs[0].satoshis = 1 } }

    it_behaves_like 'invalidates L3 hash_outputs_all'
    it_behaves_like 'invalidates L2 wire cache'

    it 'next hash_outputs(SINGLE, 0) recomputes after satoshis= mutation' do
      tx = build_wired_tx
      tx.sighash(0, BSV::Transaction::Sighash::SINGLE_FORK_ID) # warm SINGLE cache
      pre = tx.send(:hash_outputs, BSV::Transaction::Sighash::SINGLE, 0)
      tx.outputs[0].satoshis = 1
      post = tx.send(:hash_outputs, BSV::Transaction::Sighash::SINGLE, 0)
      expect(pre).not_to equal(post)
    end

    it 'calls invalidate_outputs_components_cache exactly once on owning Tx' do
      tx = build_wired_tx
      allow(tx).to receive(:invalidate_outputs_components_cache).and_call_original
      tx.outputs[0].satoshis = 5000
      expect(tx).to have_received(:invalidate_outputs_components_cache).once
    end

    it 'calls invalidate_wire_cache exactly once on owning Tx' do
      tx = build_wired_tx
      allow(tx).to receive(:invalidate_wire_cache).and_call_original
      tx.outputs[0].satoshis = 5000
      expect(tx).to have_received(:invalidate_wire_cache).once
    end
  end

  # Contract row: TransactionOutput#locking_script= — outputs + L2 ----------

  describe 'TransactionOutput#locking_script=' do
    let(:mutate) { ->(tx) { tx.outputs[0].locking_script = BSV::Script::Script.from_asm('OP_1') } }

    it_behaves_like 'invalidates L3 hash_outputs_all'
    it_behaves_like 'invalidates L2 wire cache'

    it 'next hash_outputs(SINGLE, 0) recomputes after locking_script= mutation' do
      tx = build_wired_tx
      tx.sighash(0, BSV::Transaction::Sighash::SINGLE_FORK_ID) # warm SINGLE cache
      pre = tx.send(:hash_outputs, BSV::Transaction::Sighash::SINGLE, 0)
      tx.outputs[0].locking_script = BSV::Script::Script.from_asm('OP_1')
      post = tx.send(:hash_outputs, BSV::Transaction::Sighash::SINGLE, 0)
      expect(pre).not_to equal(post)
    end

    it 'calls invalidate_outputs_components_cache exactly once on owning Tx' do
      tx = build_wired_tx
      allow(tx).to receive(:invalidate_outputs_components_cache).and_call_original
      tx.outputs[0].locking_script = BSV::Script::Script.from_asm('OP_1')
      expect(tx).to have_received(:invalidate_outputs_components_cache).once
    end

    it 'calls invalidate_wire_cache exactly once on owning Tx' do
      tx = build_wired_tx
      allow(tx).to receive(:invalidate_wire_cache).and_call_original
      tx.outputs[0].locking_script = BSV::Script::Script.from_asm('OP_1')
      expect(tx).to have_received(:invalidate_wire_cache).once
    end
  end

  # Contract row: Tx#invalidate_caches — everything -------------------------

  describe 'Tx#invalidate_caches (public escape hatch)' do
    let(:mutate) { lambda(&:invalidate_caches) }

    it_behaves_like 'invalidates L3 hash_sequence'
    it_behaves_like 'invalidates L3 hash_outputs_all'
    it_behaves_like 'invalidates L2 wire cache'

    it 'recomputes hash_prevouts after invalidate_caches' do
      tx = build_wired_tx
      tx.sighash(0, BSV::Transaction::Sighash::ALL_FORK_ID)
      pre = tx.send(:hash_prevouts, false)
      tx.invalidate_caches
      post = tx.send(:hash_prevouts, false)
      expect(pre).not_to equal(post)
    end

    it 'returns self for chaining' do
      tx = build_wired_tx
      expect(tx.invalidate_caches).to equal(tx)
    end
  end

  # Free-floating structs (no @owning_tx) ------------------------------------

  describe 'free-floating structs (no @owning_tx)' do
    it 'setting sequence= on a detached input does not raise' do
      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: "\x00".b * 32,
        prev_tx_out_index: 0
      )
      expect { input.sequence = 0 }.not_to raise_error
    end

    it 'setting unlocking_script= on a detached input does not raise' do
      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: "\x00".b * 32,
        prev_tx_out_index: 0
      )
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

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Sighash-cache docs page — anchor stability' do
  # rubocop:enable RSpec/DescribeClass

  it 'sighash-cache docs page contains anchors referenced by YARD @see clauses' do
    docs_path = File.expand_path('../../../../../docs/reference/sighash-cache.md', __dir__)
    content = File.read(docs_path)
    %w[one-owner escape-hatch invalidation-contract].each do |anchor|
      expect(content).to include(anchor)
    end
  end
end
