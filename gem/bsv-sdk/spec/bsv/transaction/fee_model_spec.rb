# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Transaction::FeeModel do
  subject(:model) { described_class.new }

  describe '#compute_fee' do
    it 'raises NotImplementedError' do
      tx = BSV::Transaction::Transaction.new
      expect { model.compute_fee(tx) }
        .to raise_error(NotImplementedError, /compute_fee must be implemented/)
    end
  end

  context 'with a concrete subclass' do
    let(:concrete_class) do
      Class.new(described_class) do
        def compute_fee(_transaction)
          500
        end
      end
    end

    it 'returns the computed fee' do
      expect(concrete_class.new.compute_fee(nil)).to eq(500)
    end
  end
end
