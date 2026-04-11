# frozen_string_literal: true

require 'spec_helper'

require_relative 'compliance_helper'

RSpec.describe 'OpenSSL EC Shim Compliance: Point#add' do
  let(:real_group) { OpenSSLCompliance.real_group }
  let(:shim_group) { OpenSSL::PKey::EC::Group.new('secp256k1') }
  let(:real_gen) { real_group.generator }
  let(:shim_gen) { shim_group.generator }

  context 'when adding two points' do
    it 'G + G matches real OpenSSL' do
      real_result = real_gen.add(real_gen)
      shim_result = shim_gen.add(shim_gen)
      expect(shim_result.to_octet_string(:compressed))
        .to eq(real_result.to_octet_string(:compressed))
    end

    OpenSSLCompliance::SCALARS.each do |label_a, scalar_a|
      OpenSSLCompliance::SCALARS.each do |label_b, scalar_b|
        next if label_a >= label_b # avoid duplicate pairs

        it "(#{label_a})*G + (#{label_b})*G matches real OpenSSL" do
          real_p = real_gen.mul(scalar_a)
          real_q = real_gen.mul(scalar_b)
          real_result = real_p.add(real_q)

          shim_p = shim_gen.mul(scalar_a)
          shim_q = shim_gen.mul(scalar_b)
          shim_result = shim_p.add(shim_q)

          if real_result.infinity?
            expect(shim_result.infinity?).to be true
          else
            expect(shim_result.to_octet_string(:compressed))
              .to eq(real_result.to_octet_string(:compressed))
          end
        end
      end
    end
  end

  context 'when adding a point to its additive inverse' do
    OpenSSLCompliance::SCALARS.each do |label, scalar|
      it "P + (-P) = infinity for #{label}" do
        n = OpenSSLCompliance::N
        neg_scalar = n - scalar

        real_p = real_gen.mul(scalar)
        real_neg = real_gen.mul(neg_scalar)
        real_result = real_p.add(real_neg)

        shim_p = shim_gen.mul(scalar)
        shim_neg = shim_gen.mul(neg_scalar)
        shim_result = shim_p.add(shim_neg)

        expect(shim_result.infinity?).to eq(real_result.infinity?)
        expect(shim_result.infinity?).to be true
      end
    end
  end

  context 'when verifying commutativity' do
    it 'P + Q == Q + P for both implementations' do
      a = OpenSSL::BN.new('42')
      b = OpenSSL::BN.new('99')

      shim_p = shim_gen.mul(a)
      shim_q = shim_gen.mul(b)
      expect(shim_p.add(shim_q).to_octet_string(:compressed))
        .to eq(shim_q.add(shim_p).to_octet_string(:compressed))
    end
  end

  context 'when comparing addition with scalar multiplication' do
    it '(k*G) + (m*G) == (k+m)*G' do
      k = OpenSSL::BN.new('12345')
      m = OpenSSL::BN.new('67890')
      km = k + m

      shim_sum = shim_gen.mul(k).add(shim_gen.mul(m))
      shim_direct = shim_gen.mul(km)
      real_direct = real_gen.mul(km)

      expect(shim_sum.to_octet_string(:compressed))
        .to eq(shim_direct.to_octet_string(:compressed))
      expect(shim_sum.to_octet_string(:compressed))
        .to eq(real_direct.to_octet_string(:compressed))
    end
  end
end
