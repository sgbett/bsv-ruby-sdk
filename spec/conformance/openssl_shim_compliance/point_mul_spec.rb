# frozen_string_literal: true

require_relative 'compliance_helper'

RSpec.describe 'OpenSSL EC Shim Compliance: Point#mul' do
  let(:real_group) { OpenSSLCompliance.real_group }
  let(:shim_group) { OpenSSL::PKey::EC::Group.new('secp256k1') }
  let(:real_gen) { real_group.generator }
  let(:shim_gen) { shim_group.generator }

  OpenSSLCompliance::SCALARS.each do |label, scalar|
    context "when multiplying with #{label}" do
      it 'produces identical compressed output for G * scalar' do
        real_result = real_gen.mul(scalar)
        shim_result = shim_gen.mul(scalar)
        expect(shim_result.to_octet_string(:compressed))
          .to eq(real_result.to_octet_string(:compressed))
      end

      it 'produces identical uncompressed output for G * scalar' do
        real_result = real_gen.mul(scalar)
        shim_result = shim_gen.mul(scalar)
        expect(shim_result.to_octet_string(:uncompressed))
          .to eq(real_result.to_octet_string(:uncompressed))
      end
    end
  end

  context 'when multiplying a non-generator point' do
    OpenSSLCompliance::SCALARS.each do |label, scalar|
      it "produces identical results for (2*G) * #{label}" do
        two = OpenSSL::BN.new('2')
        real_base = real_gen.mul(two)
        shim_base = shim_gen.mul(two)

        real_result = real_base.mul(scalar)
        shim_result = shim_base.mul(scalar)
        expect(shim_result.to_octet_string(:compressed))
          .to eq(real_result.to_octet_string(:compressed))
      end
    end
  end

  context 'with boundary scalars' do
    it 'G * N produces infinity for both' do
      n = OpenSSLCompliance::N
      real_result = real_gen.mul(n)
      shim_result = shim_gen.mul(n)
      expect(shim_result.infinity?).to eq(real_result.infinity?)
      expect(shim_result.infinity?).to be true
    end

    it 'G * (N-1) produces same point as real OpenSSL' do
      n_minus_1 = OpenSSLCompliance::N - OpenSSL::BN.new('1')
      real_result = real_gen.mul(n_minus_1)
      shim_result = shim_gen.mul(n_minus_1)
      expect(shim_result.to_octet_string(:uncompressed))
        .to eq(real_result.to_octet_string(:uncompressed))
    end

    it 'G * 1 equals the generator for both' do
      one = OpenSSL::BN.new('1')
      real_result = real_gen.mul(one)
      shim_result = shim_gen.mul(one)
      expect(shim_result.to_octet_string(:compressed))
        .to eq(real_result.to_octet_string(:compressed))
    end
  end
end
