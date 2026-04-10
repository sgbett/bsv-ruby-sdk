# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::FeeEstimator do
  describe '#initialize' do
    it 'defaults to 1 sat/kB' do
      estimator = described_class.new
      expect(estimator.sats_per_kb).to eq(1)
    end

    it 'accepts a custom rate' do
      estimator = described_class.new(sats_per_kb: 50)
      expect(estimator.sats_per_kb).to eq(50)
    end
  end

  describe 'size constants' do
    it 'P2PKH_INPUT_SIZE matches the SDK constant' do
      expect(described_class::P2PKH_INPUT_SIZE).to eq(
        BSV::Transaction::Transaction::UNSIGNED_P2PKH_INPUT_SIZE
      )
    end

    it 'P2PKH_INPUT_SIZE is 148 bytes' do
      expect(described_class::P2PKH_INPUT_SIZE).to eq(148)
    end

    it 'P2PKH_OUTPUT_SIZE is 34 bytes' do
      expect(described_class::P2PKH_OUTPUT_SIZE).to eq(34)
    end
  end

  describe '#estimate' do
    subject(:estimator) { described_class.new }

    context 'with 1 input and 1 output at 1 sat/kB' do
      # Hand-calculation: 148 + 34 + 4(version) + 1(varint inputs) + 1(varint outputs) + 4(locktime)
      #                 = 148 + 34 + 10 = 192 bytes
      # Fee: ceil(192 / 1000.0 * 1) = ceil(0.192) = 1 satoshi
      it 'returns 1 satoshi' do
        expect(estimator.estimate(p2pkh_inputs: 1, p2pkh_outputs: 1)).to eq(1)
      end

      it 'byte size is exactly 192' do
        # At 1000 sat/kB, fee equals the byte count exactly (no rounding artefact).
        high_rate_estimator = described_class.new(sats_per_kb: 1000)
        expect(high_rate_estimator.estimate(p2pkh_inputs: 1, p2pkh_outputs: 1)).to eq(192)
      end
    end

    context 'with 2 inputs and 3 outputs at 1 sat/kB' do
      # Hand-calculation: 2*148 + 3*34 + 4 + 1 + 1 + 4
      #                 = 296 + 102 + 10 = 408 bytes
      # Fee: ceil(408 / 1000.0 * 1) = ceil(0.408) = 1 satoshi
      it 'returns 1 satoshi' do
        expect(estimator.estimate(p2pkh_inputs: 2, p2pkh_outputs: 3)).to eq(1)
      end

      it 'byte size is exactly 408 at 1000 sat/kB' do
        high_rate_estimator = described_class.new(sats_per_kb: 1000)
        expect(high_rate_estimator.estimate(p2pkh_inputs: 2, p2pkh_outputs: 3)).to eq(408)
      end
    end

    context 'with extra_bytes' do
      it 'adds extra bytes to the estimated size' do
        # At 1000 sat/kB: base 192 bytes + 100 extra = 292 bytes → 292 sat
        high_rate_estimator = described_class.new(sats_per_kb: 1000)
        expect(high_rate_estimator.estimate(p2pkh_inputs: 1, p2pkh_outputs: 1, extra_bytes: 100)).to eq(292)
      end

      it 'defaults extra_bytes to 0' do
        expect(estimator.estimate(p2pkh_inputs: 1, p2pkh_outputs: 1)).to eq(
          estimator.estimate(p2pkh_inputs: 1, p2pkh_outputs: 1, extra_bytes: 0)
        )
      end
    end

    context 'with zero inputs (output-only estimation before inputs are known)' do
      # Valid for pre-funding size estimation before inputs are known.
      # Overhead: 4 + 1(varint 0) + 1(varint 1) + 4 = 10; 0*148 + 1*34 = 34; total = 44
      it 'handles zero inputs without error' do
        expect { estimator.estimate(p2pkh_inputs: 0, p2pkh_outputs: 1) }.not_to raise_error
      end

      it 'returns at least 1 satoshi' do
        expect(estimator.estimate(p2pkh_inputs: 0, p2pkh_outputs: 1)).to be >= 1
      end
    end

    context 'with a custom rate of 50 sat/kB' do
      let(:estimator_50) { described_class.new(sats_per_kb: 50) }

      it 'scales the fee proportionally' do
        # 192 bytes → ceil(192/1000 * 50) = ceil(9.6) = 10
        expect(estimator_50.estimate(p2pkh_inputs: 1, p2pkh_outputs: 1)).to eq(10)
      end
    end

    context 'with very large input count (>252) requiring a 3-byte varint' do
      # At 253 inputs, varint requires 3 bytes (0xFD prefix + 2-byte little-endian value)
      # instead of the 1-byte form used for 0..252.
      it 'uses correct 3-byte varint for 253 inputs' do
        # Expected: (253 * 148) + (1 * 34) + 8(fixed) + 3(varint inputs) + 1(varint outputs)
        expected_bytes = (253 * 148) + (1 * 34) + 8 + 3 + 1
        estimator_1k = described_class.new(sats_per_kb: 1000)
        expect(estimator_1k.estimate(p2pkh_inputs: 253, p2pkh_outputs: 1)).to eq(expected_bytes)
      end
    end

    context 'when the calculated fee rounds down to zero' do
      it 'returns at least 1 satoshi' do
        # With a 0 sat/kB rate, ceil(anything * 0) = 0, but minimum is 1.
        zero_rate_estimator = described_class.new(sats_per_kb: 0)
        expect(zero_rate_estimator.estimate(p2pkh_inputs: 1, p2pkh_outputs: 1)).to eq(1)
      end
    end

    context 'when the transaction exceeds 1000 bytes' do
      it 'returns fee > 1 sat at 1 sat/kB' do
        # 7 inputs × 148 + 1 output × 34 + 10 = 1036 + 34 + 10 = 1080 bytes → ceil(1.08) = 2 sat
        expect(estimator.estimate(p2pkh_inputs: 7, p2pkh_outputs: 1)).to be > 1
      end
    end
  end

  describe '#estimate_for_tx' do
    it 'delegates to the underlying SatoshisPerKilobyte model' do
      estimator = described_class.new(sats_per_kb: 1)
      sdk_model = BSV::Transaction::FeeModels::SatoshisPerKilobyte.new(value: 1)

      # Build a minimal real transaction with a P2PKH template so estimated_size works.
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

      expect(estimator_50.estimate_for_tx(tx)).to eq(50) # 1000/1000 * 50 = 50
      expect(estimator_1.estimate_for_tx(tx)).to eq(1)   # 1000/1000 * 1 = 1
    end
  end

  describe '#dust_floor' do
    context 'with 1 sat/kB (default rate)' do
      # spend_one_p2pkh_bytes = 1*148 + 1*34 + 4 + 1 + 1 + 4 = 192 bytes
      # cost = ceil(192/1000 * 1) = 1
      # dust_floor = max(1, 1 * 2) = 2
      it 'returns 2 satoshis' do
        estimator = described_class.new
        expect(estimator.dust_floor).to eq(2)
      end
    end

    context 'with 50 sat/kB' do
      # cost = ceil(192/1000 * 50) = ceil(9.6) = 10
      # dust_floor = max(1, 10 * 2) = 20
      it 'returns 20 satoshis' do
        estimator = described_class.new(sats_per_kb: 50)
        expect(estimator.dust_floor).to eq(20)
      end
    end

    context 'with 0 sat/kB' do
      # cost = ceil(192/1000 * 0) = 0; dust_floor = max(1, 0 * 2) = 1
      it 'returns at least 1 satoshi' do
        estimator = described_class.new(sats_per_kb: 0)
        expect(estimator.dust_floor).to eq(1)
      end
    end

    context 'with 1000 sat/kB' do
      # cost = ceil(192/1000 * 1000) = 192
      # dust_floor = max(1, 192 * 2) = 384
      it 'returns 384 satoshis' do
        estimator = described_class.new(sats_per_kb: 1000)
        expect(estimator.dust_floor).to eq(384)
      end
    end
  end
end
