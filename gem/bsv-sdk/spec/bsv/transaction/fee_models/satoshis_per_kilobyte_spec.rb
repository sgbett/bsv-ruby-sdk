# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Transaction::FeeModels::SatoshisPerKilobyte do
  describe '#compute_fee' do
    it 'computes fee for a 1 KB transaction at default rate' do
      tx = instance_double(BSV::Transaction::Transaction, estimated_size: 1000)
      model = described_class.new

      expect(model.compute_fee(tx)).to eq(100) # 1000/1000 * 100
    end

    it 'computes fee for a 250 byte transaction at default rate' do
      tx = instance_double(BSV::Transaction::Transaction, estimated_size: 250)
      model = described_class.new

      expect(model.compute_fee(tx)).to eq(25) # ceil(250/1000 * 100) = 25
    end

    it 'computes fee with custom rate' do
      tx = instance_double(BSV::Transaction::Transaction, estimated_size: 500)
      model = described_class.new(value: 100)

      expect(model.compute_fee(tx)).to eq(50) # 500/1000 * 100 = 50
    end

    it 'rounds up to ensure minimum 1 satoshi fee' do
      tx = instance_double(BSV::Transaction::Transaction, estimated_size: 1)
      model = described_class.new(value: 1)

      expect(model.compute_fee(tx)).to eq(1) # ceil(1/1000 * 1) = ceil(0.001) = 1
    end

    it 'computes correct fee for large transaction' do
      tx = instance_double(BSV::Transaction::Transaction, estimated_size: 10_000)
      model = described_class.new(value: 50)

      expect(model.compute_fee(tx)).to eq(500) # 10000/1000 * 50 = 500
    end
  end

  describe '#value' do
    it 'defaults to 100 sat/kB' do
      expect(described_class.new.value).to eq(100)
    end

    it 'accepts a custom rate' do
      expect(described_class.new(value: 200).value).to eq(200)
    end
  end

  describe 'inheritance' do
    it 'inherits from FeeModel' do
      expect(described_class.superclass).to eq(BSV::Transaction::FeeModel)
    end
  end
end
