# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'BSV::Primitives::Secp256k1Native scaffold' do
  # The native extension is only available when compiled. Skip gracefully if
  # the .bundle/.so has not been built yet.
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    require 'bsv/secp256k1_native'
  rescue LoadError
    skip 'Native extension not compiled — run `bundle exec rake compile` first'
  end

  describe 'BSV::Primitives::Secp256k1Native' do
    it 'is defined as a Module' do
      expect(BSV::Primitives::Secp256k1Native).to be_a(Module)
    end

    it 'is nested under BSV::Primitives' do
      expect(BSV::Primitives.const_defined?(:Secp256k1Native)).to be true
    end
  end

  describe 'BSV::Primitives::Secp256k1 (regression)' do
    let(:s) { BSV::Primitives::Secp256k1 }

    it 'still computes fmul correctly after extension load' do
      expect(s.fmul(2, 3)).to eq(6)
    end

    it 'still computes field inverse correctly' do
      a = s::P - 1
      expect(s.fmul(a, s.finv(a))).to eq(1)
    end

    it 'still multiplies the generator point correctly' do
      g = BSV::Primitives::Secp256k1::Point.generator
      result = g.mul(2)
      expect(result.on_curve?).to be true
      expect(result.x).to eq(
        0xC6047F9441ED7D6D3045406E95C07CD85C778E4B8CEF3CA7ABAC09B95C709EE5
      )
    end
  end
end
# rubocop:enable RSpec/DescribeClass
