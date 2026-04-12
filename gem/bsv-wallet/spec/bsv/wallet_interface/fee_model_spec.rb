# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::FeeModel do
  # Derive sizes from constants so tests adapt automatically.
  let(:input_size) { described_class::P2PKH_INPUT_SIZE }
  let(:output_size) { described_class::P2PKH_OUTPUT_SIZE }
  let(:fixed) { described_class::FIXED_OVERHEAD }

  def byte_size(inputs, outputs)
    fixed + 1 + (inputs * input_size) + 1 + (outputs * output_size)
  end

  def expected_fee(inputs, outputs, rate)
    [(byte_size(inputs, outputs) / 1000.0 * rate).ceil, 1].max
  end

  describe '#initialize' do
    it 'defaults to DEFAULT_SATS_PER_KB' do
      model = described_class.new
      expect(model.sats_per_kb).to eq(BSV::Wallet::FeeEstimator::DEFAULT_SATS_PER_KB)
    end

    it 'accepts a custom rate' do
      model = described_class.new(sats_per_kb: 100)
      expect(model.sats_per_kb).to eq(100)
    end

    it 'raises ArgumentError when sats_per_kb is zero' do
      expect { described_class.new(sats_per_kb: 0) }.to raise_error(ArgumentError)
    end

    it 'raises ArgumentError when sats_per_kb is negative' do
      expect { described_class.new(sats_per_kb: -1) }.to raise_error(ArgumentError)
    end
  end

  describe 'size constants' do
    it 'defines OVERHEAD as 10' do
      expect(described_class::OVERHEAD).to eq(10)
    end

    it 'P2PKH_INPUT_SIZE includes EF overhead' do
      expect(described_class::P2PKH_INPUT_SIZE).to eq(
        described_class::P2PKH_RAW_INPUT_SIZE + described_class::EF_INPUT_OVERHEAD
      )
    end

    it 'defines P2PKH_OUTPUT_SIZE as 34' do
      expect(described_class::P2PKH_OUTPUT_SIZE).to eq(34)
    end
  end

  describe '#estimate' do
    subject(:model) { described_class.new(sats_per_kb: rate) }

    context 'with 1 sat/kB' do
      let(:rate) { 1 }

      it '1 input + 1 output returns correct fee' do
        expect(model.estimate(p2pkh_inputs: 1, p2pkh_outputs: 1)).to eq(expected_fee(1, 1, rate))
      end

      it '2 inputs + 3 outputs returns correct fee' do
        expect(model.estimate(p2pkh_inputs: 2, p2pkh_outputs: 3)).to eq(expected_fee(2, 3, rate))
      end

      it '0 inputs + 1 output returns minimum 1 sat' do
        expect(model.estimate(p2pkh_inputs: 0, p2pkh_outputs: 1)).to eq(1)
      end
    end

    context 'with 100 sat/kB' do
      let(:rate) { 100 }

      it '2 inputs + 3 outputs returns correct fee' do
        expect(model.estimate(p2pkh_inputs: 2, p2pkh_outputs: 3)).to eq(expected_fee(2, 3, rate))
      end
    end

    context 'with 50 sat/kB' do
      let(:rate) { 50 }

      it '10 inputs + 10 outputs returns correct fee' do
        expect(model.estimate(p2pkh_inputs: 10, p2pkh_outputs: 10)).to eq(expected_fee(10, 10, rate))
      end
    end

    it 'always returns at least 1 satoshi' do
      model = described_class.new(sats_per_kb: 1)
      expect(model.estimate(p2pkh_inputs: 0, p2pkh_outputs: 0)).to eq(1)
    end
  end

  describe '#compute' do
    it 'delegates to SatoshisPerKilobyte with the configured rate' do
      sdk_model = instance_double(BSV::Transaction::FeeModels::SatoshisPerKilobyte, compute_fee: 42)
      allow(BSV::Transaction::FeeModels::SatoshisPerKilobyte)
        .to receive(:new).with(value: 100).and_return(sdk_model)
      model = described_class.new(sats_per_kb: 100)

      transaction = instance_double(BSV::Transaction::Transaction)
      expect(model.compute(transaction)).to eq(42)
    end
  end
end
