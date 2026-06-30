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
