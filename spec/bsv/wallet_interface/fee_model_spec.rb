# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::FeeModel do
  describe '#initialize' do
    it 'defaults to 1 sat/kB' do
      model = described_class.new
      expect(model.sats_per_kb).to eq(1)
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

    it 'defines P2PKH_INPUT_SIZE as 148' do
      expect(described_class::P2PKH_INPUT_SIZE).to eq(148)
    end

    it 'defines P2PKH_OUTPUT_SIZE as 34' do
      expect(described_class::P2PKH_OUTPUT_SIZE).to eq(34)
    end
  end

  describe '#estimate' do
    subject(:model) { described_class.new(sats_per_kb: rate) }

    context 'with 1 sat/kB (default rate)' do
      let(:rate) { 1 }

      it '1 input + 1 output: 192 bytes → 1 sat (minimum)' do
        # 10 + 148 + 34 = 192; ceil(192/1000.0 * 1) = 1
        expect(model.estimate(p2pkh_inputs: 1, p2pkh_outputs: 1)).to eq(1)
      end

      it '2 inputs + 3 outputs: 408 bytes → 1 sat (minimum)' do
        # 10 + 296 + 102 = 408; ceil(408/1000.0 * 1) = 1
        expect(model.estimate(p2pkh_inputs: 2, p2pkh_outputs: 3)).to eq(1)
      end

      it '0 inputs + 1 output: 44 bytes → 1 sat (minimum enforced)' do
        # 10 + 0 + 34 = 44; ceil(44/1000.0 * 1) = 1
        expect(model.estimate(p2pkh_inputs: 0, p2pkh_outputs: 1)).to eq(1)
      end
    end

    context 'with 100 sat/kB' do
      let(:rate) { 100 }

      it '2 inputs + 3 outputs: 408 bytes → 41 sats' do
        # 10 + 296 + 102 = 408; ceil(408/1000.0 * 100) = 41
        expect(model.estimate(p2pkh_inputs: 2, p2pkh_outputs: 3)).to eq(41)
      end
    end

    context 'with 50 sat/kB' do
      let(:rate) { 50 }

      it '10 inputs + 10 outputs: 1830 bytes → 92 sats' do
        # 10 + 1480 + 340 = 1830; ceil(1830/1000.0 * 50) = 92
        expect(model.estimate(p2pkh_inputs: 10, p2pkh_outputs: 10)).to eq(92)
      end
    end

    it 'always returns at least 1 satoshi' do
      model = described_class.new(sats_per_kb: 1)
      expect(model.estimate(p2pkh_inputs: 0, p2pkh_outputs: 0)).to eq(1)
    end
  end

  describe '#compute' do
    it 'delegates to SatoshisPerKilobyte with the configured rate' do
      model = described_class.new(sats_per_kb: 100)
      sdk_model = instance_double(BSV::Transaction::FeeModels::SatoshisPerKilobyte, compute_fee: 42)
      allow(BSV::Transaction::FeeModels::SatoshisPerKilobyte)
        .to receive(:new).with(value: 100).and_return(sdk_model)

      transaction = instance_double(BSV::Transaction::Transaction)
      expect(model.compute(transaction)).to eq(42)
    end
  end
end
