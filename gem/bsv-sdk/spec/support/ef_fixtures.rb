# frozen_string_literal: true

# Builds a real Extended Format (BRC-30) transaction for specs that need
# service-acceptable broadcast bytes.
module EfFixtures
  module_function

  def sample_output
    BSV::Transaction::TransactionOutput.new(satoshis: 900, locking_script: BSV::Script::Script.from_asm('OP_1'))
  end

  # @return [BSV::Transaction::Tx] a two-input, one-output transaction whose
  #   inputs carry source_satoshis and source_locking_script
  def ef_tx
    tx = BSV::Transaction::Tx.new
    2.times do |index|
      input = BSV::Transaction::TransactionInput.new(
        prev_wtxid: ([index + 1].pack('C') * 32).b,
        prev_tx_out_index: index
      )
      input.source_satoshis = 1000
      input.source_locking_script = BSV::Script::Script.from_asm('OP_1')
      tx.add_input(input)
    end
    tx.add_output(sample_output)
    tx
  end

  def ef_hex
    ef_tx.to_ef_hex
  end

  # @return [BSV::Transaction::Tx] a transaction whose input has no source data
  def tx_without_source_data
    tx = BSV::Transaction::Tx.new
    tx.add_input(BSV::Transaction::TransactionInput.new(prev_wtxid: ("\x01".b * 32), prev_tx_out_index: 0))
    tx.add_output(sample_output)
    tx
  end
end
