# frozen_string_literal: true

require_relative 'compliance_helper'

RSpec.describe 'OpenSSL EC Shim Compliance: Point serialisation' do
  let(:real_group) { OpenSSLCompliance.real_group }
  let(:shim_group) { OpenSSL::PKey::EC::Group.new('secp256k1') }
  let(:real_gen) { real_group.generator }
  let(:shim_gen) { shim_group.generator }

  describe '#to_octet_string' do
    OpenSSLCompliance::SCALARS.each do |label, scalar|
      context "for #{label} * G" do
        let(:real_point) { real_gen.mul(scalar) }
        let(:shim_point) { shim_gen.mul(scalar) }

        it 'compressed output is byte-identical' do
          expect(shim_point.to_octet_string(:compressed))
            .to eq(real_point.to_octet_string(:compressed))
        end

        it 'uncompressed output is byte-identical' do
          expect(shim_point.to_octet_string(:uncompressed))
            .to eq(real_point.to_octet_string(:uncompressed))
        end

        it 'compressed is 33 bytes' do
          expect(shim_point.to_octet_string(:compressed).bytesize).to eq(33)
        end

        it 'uncompressed is 65 bytes' do
          expect(shim_point.to_octet_string(:uncompressed).bytesize).to eq(65)
        end

        it 'compressed prefix is 02 or 03' do
          prefix = shim_point.to_octet_string(:compressed).getbyte(0)
          expect(prefix).to be_between(0x02, 0x03)
        end

        it 'uncompressed prefix is 04' do
          expect(shim_point.to_octet_string(:uncompressed).getbyte(0)).to eq(0x04)
        end
      end
    end
  end

  describe '#to_bn' do
    OpenSSLCompliance::SCALARS.each do |label, scalar|
      context "for #{label} * G" do
        let(:real_point) { real_gen.mul(scalar) }
        let(:shim_point) { shim_gen.mul(scalar) }

        it 'to_bn(:compressed).to_s(16) is identical' do
          expect(shim_point.to_bn(:compressed).to_s(16))
            .to eq(real_point.to_bn(:compressed).to_s(16))
        end

        it 'to_bn(:uncompressed).to_s(16) is identical' do
          expect(shim_point.to_bn(:uncompressed).to_s(16))
            .to eq(real_point.to_bn(:uncompressed).to_s(16))
        end

        it 'to_bn(:compressed).to_s(2) is byte-identical' do
          expect(shim_point.to_bn(:compressed).to_s(2))
            .to eq(real_point.to_bn(:compressed).to_s(2))
        end

        it 'to_bn returns an OpenSSL::BN' do
          expect(shim_point.to_bn(:compressed)).to be_a(OpenSSL::BN)
        end
      end
    end
  end

  describe 'round-trip' do
    OpenSSLCompliance::SCALARS.each do |label, scalar|
      it "serialise → deserialise round-trips for #{label}" do
        real_point = real_gen.mul(scalar)
        compressed = real_point.to_octet_string(:compressed)

        bn = OpenSSL::BN.new(compressed, 2)
        shim_point = OpenSSL::PKey::EC::Point.new(shim_group, bn)

        expect(shim_point.to_octet_string(:compressed)).to eq(compressed)
        expect(shim_point.to_octet_string(:uncompressed))
          .to eq(real_point.to_octet_string(:uncompressed))
      end
    end
  end
end
