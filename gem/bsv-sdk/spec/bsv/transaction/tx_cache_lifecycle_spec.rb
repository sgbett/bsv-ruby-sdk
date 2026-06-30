# frozen_string_literal: true

require 'spec_helper'

# Phase A: owning-Tx backref, #initialize_copy, and public invalidator stubs.
# Tests the lifecycle of inputs and outputs bound to a Tx instance.

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Tx cache lifecycle — backref, dup, and invalidator stubs' do
  # rubocop:enable RSpec/DescribeClass

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

    it 'is idempotent on same-Tx re-add — does not raise and does not duplicate' do
      tx = make_tx
      input = make_input
      tx.add_input(input)
      expect { tx.add_input(input) }.not_to raise_error
      expect(tx.inputs.length).to eq(1)
      expect(tx.inputs.first).to equal(input)
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

    it 'is idempotent on same-Tx re-add — does not raise and does not duplicate' do
      tx = make_tx
      output = make_output
      tx.add_output(output)
      expect { tx.add_output(output) }.not_to raise_error
      expect(tx.outputs.length).to eq(1)
      expect(tx.outputs.first).to equal(output)
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

    it 'isolates cache ivars — dup mutation does not evict original per-index cache' do
      # Warm @hash_outputs_single on the original by reading per-index entries
      tx.send(:hash_outputs, BSV::Transaction::Sighash::SINGLE, 0)
      tx.send(:hash_outputs, BSV::Transaction::Sighash::SINGLE, 1)
      original_per_index = tx.instance_variable_get(:@hash_outputs_single)
      expect(original_per_index.keys).to contain_exactly(0, 1)

      # Dup, then mutate the dup. The mutation triggers
      # invalidate_outputs_components_cache which calls .clear on the dup's
      # @hash_outputs_single. Pre-fix this would clear the SHARED Hash and
      # evict the original's entries. Post-fix the dup starts cold (its
      # @hash_outputs_single is nil), so .clear is a no-op on the dup and
      # the original's Hash is untouched.
      dup_tx = tx.dup
      dup_tx.outputs[0].satoshis = 9999

      expect(original_per_index).to equal(tx.instance_variable_get(:@hash_outputs_single))
      expect(original_per_index.keys).to contain_exactly(0, 1)
    end

    it 'isolates cache ivars — dup starts with cold caches' do
      tx.send(:hash_prevouts, false)
      tx.send(:hash_outputs, BSV::Transaction::Sighash::ALL, 0)

      dup_tx = tx.dup

      expect(dup_tx.instance_variable_get(:@hash_prevouts)).to be_nil
      expect(dup_tx.instance_variable_get(:@hash_outputs_all)).to be_nil
      expect(dup_tx.instance_variable_get(:@hash_outputs_single)).to be_nil
      expect(dup_tx.instance_variable_get(:@to_binary)).to be_nil
      expect(dup_tx.instance_variable_get(:@wtxid)).to be_nil
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

  # Direct L1 unit asserts. The Phase C/D regression spec proves these
  # invariants indirectly through the sha256d call count, but a regression
  # that broke per-struct freezing or object identity without touching the
  # count would slip past the structural test. These specs lock the
  # invariants in directly.
  describe 'L1 per-struct memo invariants' do
    it 'TransactionInput#outpoint_binary returns the same object across calls' do
      input = make_input
      expect(input.outpoint_binary).to equal(input.outpoint_binary)
    end

    it 'TransactionInput#outpoint_binary returns a frozen binary' do
      input = make_input
      expect(input.outpoint_binary).to be_frozen
    end

    it 'external mutation of the constructor wtxid argument cannot stale outpoint_binary' do
      mutable_wtxid = "\x00".b * 32
      input = BSV::Transaction::TransactionInput.new(prev_wtxid: mutable_wtxid, prev_tx_out_index: 0)
      cached = input.outpoint_binary
      mutable_wtxid[0] = "\xFF".b
      # Cache returns the same frozen object; defensive copy means external
      # mutation cannot reach @prev_wtxid.
      expect(input.outpoint_binary).to equal(cached)
      expect(input.outpoint_binary.bytes.first).to eq(0x00)
    end

    it 'TransactionInput#to_binary returns a frozen binary' do
      input = make_input
      expect(input.to_binary).to be_frozen
    end

    it 'TransactionOutput#to_binary returns a frozen binary' do
      output = make_output
      expect(output.to_binary).to be_frozen
    end

    it 'Tx#hash_prevouts caches a frozen result' do
      tx = make_tx
      tx.add_input(make_input)
      expect(tx.send(:hash_prevouts, false)).to be_frozen
    end

    it 'Tx#hash_outputs caches a frozen result (ALL branch)' do
      tx = make_tx
      tx.add_output(make_output)
      expect(tx.send(:hash_outputs, BSV::Transaction::Sighash::ALL, 0)).to be_frozen
    end
  end
end
