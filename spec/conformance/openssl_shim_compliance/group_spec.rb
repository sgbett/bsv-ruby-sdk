# frozen_string_literal: true

require_relative 'compliance_helper'

RSpec.describe 'OpenSSL EC Shim Compliance: Group' do
  let(:real_group) { OpenSSLCompliance::RealGroup.new('secp256k1') }
  let(:shim_group) { OpenSSL::PKey::EC::Group.new('secp256k1') }

  describe '.new' do
    it 'accepts secp256k1 for both implementations' do
      expect(real_group).to be_a(OpenSSLCompliance::RealGroup)
      expect(shim_group).to be_a(OpenSSL::PKey::EC::Group)
    end
  end

  describe '#order' do
    it 'returns identical curve order N' do
      expect(shim_group.order.to_s(16)).to eq(real_group.order.to_s(16))
    end

    it 'returns an OpenSSL::BN' do
      expect(shim_group.order).to be_a(OpenSSL::BN)
    end
  end

  describe '#generator' do
    it 'returns a point with identical compressed encoding' do
      real_bytes = real_group.generator.to_octet_string(:compressed)
      shim_bytes = shim_group.generator.to_octet_string(:compressed)
      expect(shim_bytes).to eq(real_bytes)
    end

    it 'returns a point with identical uncompressed encoding' do
      real_bytes = real_group.generator.to_octet_string(:uncompressed)
      shim_bytes = shim_group.generator.to_octet_string(:uncompressed)
      expect(shim_bytes).to eq(real_bytes)
    end
  end

  describe '#curve_name' do
    it 'returns secp256k1 for both' do
      expect(shim_group.curve_name).to eq(real_group.curve_name)
    end
  end
end
