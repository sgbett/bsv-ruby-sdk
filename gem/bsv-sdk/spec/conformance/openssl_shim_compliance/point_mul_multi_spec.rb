# frozen_string_literal: true

require 'spec_helper'

require_relative 'compliance_helper'

RSpec.describe 'OpenSSL EC Shim Compliance: Point#mul (multi-scalar)' do
  let(:shim_group) { OpenSSL::PKey::EC::Group.new('secp256k1') }
  let(:shim_gen) { shim_group.generator }
  let(:one) { OpenSSL::BN.new('1') }

  # The multi-scalar form: point.mul([bns], [points])
  # computes bns[0]*self + bns[1]*points[0] + ...
  #
  # Real OpenSSL removed this form in OpenSSL 3 / Ruby 3.x, so we cannot
  # compare against it directly. Instead we verify internal consistency:
  # multi-scalar must produce the same result as separate mul + add.

  context 'when using multi-scalar with a=1, b=1 to add two points' do
    # P.mul([1, 1], [Q]) should equal P.add(Q)
    OpenSSLCompliance::SCALARS.each do |label_a, scalar_a|
      OpenSSLCompliance::SCALARS.each do |label_b, scalar_b|
        next if label_a == label_b

        it "#{label_a} * G + #{label_b} * G" do
          shim_p = shim_gen.mul(scalar_a)
          shim_q = shim_gen.mul(scalar_b)

          multi = shim_p.mul([one, one], [shim_q])
          via_add = shim_p.add(shim_q)

          if via_add.infinity?
            expect(multi.infinity?).to be true
          else
            expect(multi.to_octet_string(:compressed))
              .to eq(via_add.to_octet_string(:compressed))
          end
        end
      end
    end
  end

  context 'when computing a weighted multi-scalar sum' do
    it 'a*P + b*Q via multi-scalar matches mul + add' do
      a = OpenSSL::BN.new('7')
      b = OpenSSL::BN.new('13')

      shim_p = shim_gen.mul(OpenSSL::BN.new('42'))
      shim_q = shim_gen.mul(OpenSSL::BN.new('99'))

      multi = shim_p.mul([a, b], [shim_q])
      separate = shim_p.mul(a).add(shim_q.mul(b))

      expect(multi.to_octet_string(:compressed))
        .to eq(separate.to_octet_string(:compressed))
    end
  end

  context 'when comparing multi-scalar add results to real OpenSSL' do
    # Since multi-scalar is just a way to do addition, verify the add
    # result matches what real OpenSSL produces via its add method.
    let(:real_group) { OpenSSLCompliance.real_group }
    let(:real_gen) { real_group.generator }

    OpenSSLCompliance::SCALARS.each do |label_a, scalar_a|
      OpenSSLCompliance::SCALARS.each do |label_b, scalar_b|
        next if label_a >= label_b

        it "shim multi-scalar P+Q matches real add for (#{label_a}, #{label_b})" do
          real_p = real_gen.mul(scalar_a)
          real_q = real_gen.mul(scalar_b)
          real_sum = real_p.add(real_q)

          shim_p = shim_gen.mul(scalar_a)
          shim_q = shim_gen.mul(scalar_b)
          shim_sum = shim_p.mul([one, one], [shim_q])

          if real_sum.infinity?
            expect(shim_sum.infinity?).to be true
          else
            expect(shim_sum.to_octet_string(:compressed))
              .to eq(real_sum.to_octet_string(:compressed))
          end
        end
      end
    end
  end
end
