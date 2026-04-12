# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::FeeEstimator do
  # Reference the constant so tests adapt if the default changes.
  let(:default_rate) { described_class::DEFAULT_SATS_PER_KB }

  # Helper: compute the expected fee for a given byte size at a given rate.
  def expected_fee(bytes, rate)
    [(bytes / 1000.0 * rate).ceil, 1].max
  end

  # Compute expected byte sizes from the class constants so tests adapt
  # if input/output sizes or overhead change.
  let(:input_size) { described_class::P2PKH_INPUT_SIZE }
  let(:output_size) { described_class::P2PKH_OUTPUT_SIZE }
  let(:fixed) { described_class::FIXED_OVERHEAD }
  # size = FIXED_OVERHEAD + varint(inputs) + inputs*INPUT + varint(outputs) + outputs*OUTPUT
  let(:size_1_1) { fixed + 1 + (1 * input_size) + 1 + (1 * output_size) }
  let(:size_2_3) { fixed + 1 + (2 * input_size) + 1 + (3 * output_size) }

  describe '#initialize' do
    it 'defaults to DEFAULT_SATS_PER_KB' do
      estimator = described_class.new
      expect(estimator.sats_per_kb).to eq(default_rate)
    end

    it 'accepts a custom rate' do
      estimator = described_class.new(sats_per_kb: 50)
      expect(estimator.sats_per_kb).to eq(50)
    end

    it 'raises ArgumentError for zero' do
      expect { described_class.new(sats_per_kb: 0) }
        .to raise_error(ArgumentError, /greater than zero/)
    end

    it 'raises ArgumentError for negative' do
      expect { described_class.new(sats_per_kb: -1) }
        .to raise_error(ArgumentError, /greater than zero/)
    end
  end

  describe 'size constants' do
    it 'P2PKH_RAW_INPUT_SIZE matches the SDK constant' do
      expect(described_class::P2PKH_RAW_INPUT_SIZE).to eq(
        BSV::Transaction::Transaction::UNSIGNED_P2PKH_INPUT_SIZE
      )
    end

    it 'P2PKH_INPUT_SIZE includes EF overhead' do
      expect(described_class::P2PKH_INPUT_SIZE).to eq(
        described_class::P2PKH_RAW_INPUT_SIZE + described_class::EF_INPUT_OVERHEAD
      )
    end

    it 'P2PKH_OUTPUT_SIZE is 34 bytes' do
      expect(described_class::P2PKH_OUTPUT_SIZE).to eq(34)
    end
  end

  describe '#estimate' do
    subject(:estimator) { described_class.new }

    context 'with 1 input and 1 output at default rate' do
      it 'returns the correct fee' do
        expect(estimator.estimate(p2pkh_inputs: 1, p2pkh_outputs: 1)).to eq(expected_fee(size_1_1, default_rate))
      end

      it 'byte size matches computed size at 1000 sat/kB' do
        high_rate = described_class.new(sats_per_kb: 1000)
        expect(high_rate.estimate(p2pkh_inputs: 1, p2pkh_outputs: 1)).to eq(size_1_1)
      end
    end

    context 'with 2 inputs and 3 outputs at default rate' do
      it 'returns the correct fee' do
        expect(estimator.estimate(p2pkh_inputs: 2, p2pkh_outputs: 3)).to eq(expected_fee(size_2_3, default_rate))
      end

      it 'byte size matches computed size at 1000 sat/kB' do
        high_rate = described_class.new(sats_per_kb: 1000)
        expect(high_rate.estimate(p2pkh_inputs: 2, p2pkh_outputs: 3)).to eq(size_2_3)
      end
    end

    context 'with extra_bytes' do
      it 'adds extra bytes to the estimated size' do
        high_rate = described_class.new(sats_per_kb: 1000)
        expect(high_rate.estimate(p2pkh_inputs: 1, p2pkh_outputs: 1, extra_bytes: 100)).to eq(size_1_1 + 100)
      end

      it 'defaults extra_bytes to 0' do
        expect(estimator.estimate(p2pkh_inputs: 1, p2pkh_outputs: 1)).to eq(
          estimator.estimate(p2pkh_inputs: 1, p2pkh_outputs: 1, extra_bytes: 0)
        )
      end
    end

    context 'with zero inputs' do
      it 'handles zero inputs without error' do
        expect { estimator.estimate(p2pkh_inputs: 0, p2pkh_outputs: 1) }.not_to raise_error
      end

      it 'returns at least 1 satoshi' do
        expect(estimator.estimate(p2pkh_inputs: 0, p2pkh_outputs: 1)).to be >= 1
      end
    end

    context 'with a custom rate of 50 sat/kB' do
      it 'scales the fee proportionally' do
        estimator_50 = described_class.new(sats_per_kb: 50)
        expect(estimator_50.estimate(p2pkh_inputs: 1, p2pkh_outputs: 1)).to eq(expected_fee(size_1_1, 50))
      end
    end

    context 'with very large input count (>252) requiring a 3-byte varint' do
      it 'uses correct 3-byte varint for 253 inputs' do
        expected_bytes = (253 * input_size) + (1 * output_size) + fixed + 3 + 1
        estimator_1k = described_class.new(sats_per_kb: 1000)
        expect(estimator_1k.estimate(p2pkh_inputs: 253, p2pkh_outputs: 1)).to eq(expected_bytes)
      end
    end

    context 'when the transaction exceeds 1000 bytes' do
      it 'returns fee proportional to size' do
        size_7_1 = fixed + 1 + (7 * input_size) + 1 + (1 * output_size)
        expect(estimator.estimate(p2pkh_inputs: 7, p2pkh_outputs: 1)).to eq(expected_fee(size_7_1, default_rate))
      end
    end
  end

  describe '#estimate_for_tx' do
    it 'delegates to the underlying SatoshisPerKilobyte model' do
      estimator = described_class.new(sats_per_kb: 1)
      sdk_model = BSV::Transaction::FeeModels::SatoshisPerKilobyte.new(value: 1)

      private_key = BSV::Primitives::PrivateKey.generate
      lock_script = BSV::Script::Script.p2pkh_lock(private_key.public_key.hash160)
      tx = BSV::Transaction::Transaction.new

      input = BSV::Transaction::TransactionInput.new(
        prev_tx_id: BSV::Primitives::Digest.sha256d('test'),
        prev_tx_out_index: 0
      )
      input.source_satoshis = 5000
      input.source_locking_script = lock_script
      input.unlocking_script_template = BSV::Transaction::P2PKH.new(private_key)
      tx.add_input(input)
      tx.add_output(BSV::Transaction::TransactionOutput.new(
                      satoshis: 4999,
                      locking_script: lock_script
                    ))

      expect(estimator.estimate_for_tx(tx)).to eq(sdk_model.compute_fee(tx))
    end

    it 'uses the configured rate when delegating' do
      estimator_50 = described_class.new(sats_per_kb: 50)
      estimator_1  = described_class.new(sats_per_kb: 1)

      tx = instance_double(BSV::Transaction::Transaction, estimated_size: 1000)

      expect(estimator_50.estimate_for_tx(tx)).to eq(50)
      expect(estimator_1.estimate_for_tx(tx)).to eq(1)
    end
  end

  describe '#dust_floor' do
    context 'with default rate' do
      it 'returns twice the cost to spend one P2PKH input' do
        estimator = described_class.new
        cost = expected_fee(size_1_1, default_rate)
        expect(estimator.dust_floor).to eq([1, cost * 2].max)
      end
    end

    context 'with 50 sat/kB' do
      it 'returns twice the cost to spend one input' do
        estimator = described_class.new(sats_per_kb: 50)
        cost = (size_1_1 / 1000.0 * 50).ceil
        expect(estimator.dust_floor).to eq([1, cost * 2].max)
      end
    end

    context 'with 1000 sat/kB' do
      it 'returns twice the cost to spend one input' do
        estimator = described_class.new(sats_per_kb: 1000)
        cost = (size_1_1 / 1000.0 * 1000).ceil
        expect(estimator.dust_floor).to eq([1, cost * 2].max)
      end
    end
  end
end
