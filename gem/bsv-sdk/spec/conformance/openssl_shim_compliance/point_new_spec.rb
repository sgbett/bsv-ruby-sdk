# frozen_string_literal: true

require 'spec_helper'

require_relative 'compliance_helper'

RSpec.describe 'OpenSSL EC Shim Compliance: Point.new' do
  let(:real_group) { OpenSSLCompliance.real_group }
  let(:shim_group) { OpenSSL::PKey::EC::Group.new('secp256k1') }

  OpenSSLCompliance::SCALARS.each do |label, scalar|
    context "with #{label} scalar" do
      let(:real_point) { OpenSSLCompliance.real_mul_generator(scalar) }
      let(:compressed_bytes) { real_point.to_octet_string(:compressed) }
      let(:uncompressed_bytes) { real_point.to_octet_string(:uncompressed) }

      it 'constructs from compressed bytes identically' do
        bn = OpenSSL::BN.new(compressed_bytes, 2)
        shim_pt = OpenSSL::PKey::EC::Point.new(shim_group, bn)
        expect(shim_pt.to_octet_string(:compressed)).to eq(compressed_bytes)
      end

      it 'constructs from uncompressed bytes identically' do
        bn = OpenSSL::BN.new(uncompressed_bytes, 2)
        shim_pt = OpenSSL::PKey::EC::Point.new(shim_group, bn)
        expect(shim_pt.to_octet_string(:uncompressed)).to eq(uncompressed_bytes)
      end

      it 'compressed round-trip matches uncompressed round-trip' do
        bn_c = OpenSSL::BN.new(compressed_bytes, 2)
        bn_u = OpenSSL::BN.new(uncompressed_bytes, 2)
        pt_c = OpenSSL::PKey::EC::Point.new(shim_group, bn_c)
        pt_u = OpenSSL::PKey::EC::Point.new(shim_group, bn_u)
        expect(pt_c.to_octet_string(:compressed)).to eq(pt_u.to_octet_string(:compressed))
      end
    end
  end

  context 'with invalid input' do
    it 'raises on bytes that are not a valid point' do
      # x=1, y=2 is not on the curve
      bad = "\x04".b + "#{"\x00" * 31}\u0001".b + "#{"\x00" * 31}\u0002".b
      bn = OpenSSL::BN.new(bad, 2)
      expect { OpenSSL::PKey::EC::Point.new(shim_group, bn) }
        .to raise_error(OpenSSL::PKey::EC::Point::Error)
    end
  end
end
