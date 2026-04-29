# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Primitives::Curve do
  describe 'constants' do
    it 'defines GROUP as secp256k1' do
      expect(described_class::GROUP).to be_a(OpenSSL::PKey::EC::Group)
      expect(described_class::GROUP.curve_name).to eq('secp256k1')
    end

    it 'defines N as the curve order' do
      expected = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141'
      expect(described_class::N.to_s(16)).to eq(expected)
    end

    it 'defines G as the generator point' do
      expected = '0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798'
      expect(described_class::G.to_bn(:compressed).to_s(16)).to eq(expected)
    end

    it 'defines HALF_N as N >> 1' do
      expect(described_class::HALF_N).to eq(described_class::N >> 1)
    end
  end

  describe '.multiply_generator' do
    it 'multiplies the generator by a scalar' do
      # 2G is a well-known point
      result = described_class.multiply_generator(OpenSSL::BN.new('2', 10))
      expected = '02C6047F9441ED7D6D3045406E95C07CD85C778E4B8CEF3CA7ABAC09B95C709EE5'
      expect(result.to_bn(:compressed).to_s(16)).to eq(expected)
    end
  end

  describe '.multiply_point' do
    it 'multiplies a point by a scalar' do
      p2 = described_class.multiply_generator(OpenSSL::BN.new('2', 10))
      result = described_class.multiply_point(p2, OpenSSL::BN.new('3', 10))
      # 2G * 3 = 6G
      expected = described_class.multiply_generator(OpenSSL::BN.new('6', 10))
      expect(result.to_bn(:compressed).to_s(16)).to eq(expected.to_bn(:compressed).to_s(16))
    end
  end

  describe '.add_points' do
    it 'adds two points together' do
      p2 = described_class.multiply_generator(OpenSSL::BN.new('2', 10))
      p3 = described_class.multiply_generator(OpenSSL::BN.new('3', 10))
      result = described_class.add_points(p2, p3)
      expected = described_class.multiply_generator(OpenSSL::BN.new('5', 10))
      expect(result.to_bn(:compressed).to_s(16)).to eq(expected.to_bn(:compressed).to_s(16))
    end
  end

  describe '.point_x' do
    it 'extracts the x coordinate of a point' do
      # Generator x coordinate
      x = described_class.point_x(described_class::G)
      expected = '79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798'
      expect(x.to_s(16)).to eq(expected)
    end

    it 'handles x-coordinates with leading zero bytes' do
      # 153*G has x = 00e3ae... (leading zero byte)
      point = described_class.multiply_generator(OpenSSL::BN.new('153'))
      x = described_class.point_x(point)
      # BN#to_s(16) strips leading zeros, so we verify via raw bytes instead
      x_bytes = x.to_s(2)
      x_padded = (("\x00" * (32 - x_bytes.bytesize)) + x_bytes).b
      expect(x_padded.bytesize).to eq(32)
      expect(x_padded.getbyte(0)).to eq(0)
      expect(x_padded.unpack1('H*')).to eq('00e3ae1974566ca06cc516d47e0fb165a674a3dabcfca15e722f0e3450f45889')
    end
  end

  describe '.point_from_bytes' do
    it 'reconstructs a point from compressed bytes' do
      compressed = ['0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798'].pack('H*')
      point = described_class.point_from_bytes(compressed)
      expect(point.to_bn(:compressed).to_s(16)).to eq(described_class::G.to_bn(:compressed).to_s(16))
    end

    it 'reconstructs a point from uncompressed bytes' do
      uncompressed = described_class::G.to_octet_string(:uncompressed)
      point = described_class.point_from_bytes(uncompressed)
      expect(point.to_bn(:compressed).to_s(16)).to eq(described_class::G.to_bn(:compressed).to_s(16))
    end
  end

  describe '.multiply_generator_ct' do
    it 'produces the same result as multiply_generator (both are CT)' do
      scalar = OpenSSL::BN.new('2', 10)
      default = described_class.multiply_generator(scalar)
      ct = described_class.multiply_generator_ct(scalar)
      expect(ct.to_bn(:compressed).to_s(16)).to eq(default.to_bn(:compressed).to_s(16))
    end

    it 'matches a well-known point' do
      scalar = OpenSSL::BN.new('7', 10)
      expected = described_class.multiply_generator(scalar)
      result = described_class.multiply_generator_ct(scalar)
      expect(result.to_bn(:compressed).to_s(16)).to eq(expected.to_bn(:compressed).to_s(16))
    end
  end

  describe '.multiply_generator_vt' do
    it 'produces the same result as multiply_generator' do
      scalar = OpenSSL::BN.new('2', 10)
      default = described_class.multiply_generator(scalar)
      vt = described_class.multiply_generator_vt(scalar)
      expect(vt.to_bn(:compressed).to_s(16)).to eq(default.to_bn(:compressed).to_s(16))
    end

    it 'matches a well-known point' do
      scalar = OpenSSL::BN.new('7', 10)
      expected = described_class.multiply_generator(scalar)
      result = described_class.multiply_generator_vt(scalar)
      expect(result.to_bn(:compressed).to_s(16)).to eq(expected.to_bn(:compressed).to_s(16))
    end
  end

  describe '.multiply_point_ct' do
    it 'produces the same result as multiply_point (both are CT)' do
      p2 = described_class.multiply_generator(OpenSSL::BN.new('2', 10))
      scalar = OpenSSL::BN.new('5', 10)
      default = described_class.multiply_point(p2, scalar)
      ct = described_class.multiply_point_ct(p2, scalar)
      expect(ct.to_bn(:compressed).to_s(16)).to eq(default.to_bn(:compressed).to_s(16))
    end
  end

  describe '.multiply_point_vt' do
    it 'produces the same result as multiply_point' do
      p2 = described_class.multiply_generator(OpenSSL::BN.new('2', 10))
      scalar = OpenSSL::BN.new('5', 10)
      default = described_class.multiply_point(p2, scalar)
      vt = described_class.multiply_point_vt(p2, scalar)
      expect(vt.to_bn(:compressed).to_s(16)).to eq(default.to_bn(:compressed).to_s(16))
    end
  end
end
