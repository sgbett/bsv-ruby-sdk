# frozen_string_literal: true

require_relative 'compliance_helper'

RSpec.describe 'OpenSSL EC Shim Compliance: EC key construction' do
  let(:real_group) { OpenSSLCompliance.real_group }
  let(:shim_group) { OpenSSL::PKey::EC::Group.new('secp256k1') }
  let(:real_gen) { real_group.generator }

  # Build a SEC 1 private key DER (same logic as Curve.ec_key_from_private_bytes).
  def build_private_der(private_bytes, pub_point_bytes)
    OpenSSL::ASN1::Sequence.new([
      OpenSSL::ASN1::Integer.new(1),
      OpenSSL::ASN1::OctetString.new(private_bytes),
      OpenSSL::ASN1::ObjectId.new('secp256k1', 0, :EXPLICIT),
      OpenSSL::ASN1::BitString.new(pub_point_bytes, 1, :EXPLICIT)
    ]).to_der
  end

  # Build a SPKI public key DER (same logic as Curve.ec_key_from_public_bytes).
  def build_public_der(public_bytes)
    OpenSSL::ASN1::Sequence.new([
      OpenSSL::ASN1::Sequence.new([
        OpenSSL::ASN1::ObjectId.new('id-ecPublicKey'),
        OpenSSL::ASN1::ObjectId.new('secp256k1')
      ]),
      OpenSSL::ASN1::BitString.new(public_bytes)
    ]).to_der
  end

  describe 'private key DER' do
    OpenSSLCompliance::SCALARS.each do |label, scalar|
      it "extracts correct public key for #{label}" do
        priv_bytes = scalar.to_s(2)
        priv_bytes = ("\x00".b * (32 - priv_bytes.bytesize)) + priv_bytes if priv_bytes.bytesize < 32
        pub_point = real_gen.mul(scalar)
        pub_bytes = pub_point.to_octet_string(:compressed)

        der = build_private_der(priv_bytes, pub_bytes)
        shim_key = OpenSSL::PKey::EC.new(der)

        expect(shim_key.public_key.to_octet_string(:compressed)).to eq(pub_bytes)
      end
    end
  end

  describe 'public key DER (compressed)' do
    OpenSSLCompliance::SCALARS.each do |label, scalar|
      it "round-trips compressed public key for #{label}" do
        pub_point = real_gen.mul(scalar)
        compressed = pub_point.to_octet_string(:compressed)
        der = build_public_der(compressed)

        shim_key = OpenSSL::PKey::EC.new(der)
        expect(shim_key.public_key.to_octet_string(:compressed)).to eq(compressed)
      end
    end
  end

  describe 'public key DER (uncompressed)' do
    OpenSSLCompliance::SCALARS.each do |label, scalar|
      it "round-trips uncompressed public key for #{label}" do
        pub_point = real_gen.mul(scalar)
        uncompressed = pub_point.to_octet_string(:uncompressed)
        compressed = pub_point.to_octet_string(:compressed)
        der = build_public_der(uncompressed)

        shim_key = OpenSSL::PKey::EC.new(der)
        # Should produce the same compressed key regardless of input format
        expect(shim_key.public_key.to_octet_string(:compressed)).to eq(compressed)
      end
    end
  end
end
