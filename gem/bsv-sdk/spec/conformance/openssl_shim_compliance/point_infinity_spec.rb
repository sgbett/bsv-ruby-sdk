# frozen_string_literal: true

require 'spec_helper'

require_relative 'compliance_helper'

RSpec.describe 'OpenSSL EC Shim Compliance: Point infinity' do
  let(:real_group) { OpenSSLCompliance.real_group }
  let(:shim_group) { OpenSSL::PKey::EC::Group.new('secp256k1') }

  describe '#infinity?' do
    it 'generator is not infinity for both' do
      expect(real_group.generator.infinity?).to be false
      expect(shim_group.generator.infinity?).to be false
    end

    it 'G * N is infinity for both' do
      n = OpenSSLCompliance::N
      real_inf = real_group.generator.mul(n)
      shim_inf = shim_group.generator.mul(n)
      expect(real_inf.infinity?).to be true
      expect(shim_inf.infinity?).to be true
    end

    it 'P + (-P) is infinity for both' do
      scalar = OpenSSL::BN.new('42')
      neg_scalar = OpenSSLCompliance::N - scalar

      real_result = real_group.generator.mul(scalar).add(real_group.generator.mul(neg_scalar))
      shim_result = shim_group.generator.mul(scalar).add(shim_group.generator.mul(neg_scalar))

      expect(real_result.infinity?).to be true
      expect(shim_result.infinity?).to be true
    end
  end

  describe '#set_to_infinity!' do
    it 'makes a point report infinity' do
      shim_pt = shim_group.generator
      shim_pt.set_to_infinity!
      expect(shim_pt.infinity?).to be true
    end
  end
end
