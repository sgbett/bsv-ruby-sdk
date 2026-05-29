# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::Wallet::Serializer::GetHeight' do
  let(:mod_args) { BSV::Wallet::Serializer::GetHeight::Args }
  let(:mod_result) { BSV::Wallet::Serializer::GetHeight::Result }

  describe 'Args' do
    it 'serialises to empty bytes' do
      expect(mod_args.serialize).to eq(''.b)
    end

    it 'deserialises any bytes to empty hash' do
      expect(mod_args.deserialize('')).to eq({})
    end
  end

  describe 'Result' do
    it 'round-trips height 0' do
      result = { height: 0 }
      bytes = mod_result.serialize(result)
      expect(mod_result.deserialize(bytes)).to eq(result)
    end

    it 'round-trips a small height' do
      result = { height: 123 }
      bytes = mod_result.serialize(result)
      expect(mod_result.deserialize(bytes)).to eq(result)
    end

    it 'round-trips height 800_000' do
      result = { height: 800_000 }
      bytes = mod_result.serialize(result)
      expect(mod_result.deserialize(bytes)).to eq(result)
    end

    it 'round-trips a large height (123456789)' do
      result = { height: 123_456_789 }
      bytes = mod_result.serialize(result)
      expect(mod_result.deserialize(bytes)).to eq(result)
    end

    it 'round-trips max uint32 (0xFFFFFFFF)' do
      result = { height: 0xFFFFFFFF }
      bytes = mod_result.serialize(result)
      expect(mod_result.deserialize(bytes)).to eq(result)
    end

    it 'raises on empty payload' do
      expect { mod_result.deserialize('') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    context 'with go-sdk reference vectors' do
      it 'height 0 encodes as single varint byte 0x00' do
        bytes = mod_result.serialize({ height: 0 })
        expect(bytes.unpack1('H*')).to eq('00')
      end

      it 'height 123 encodes as single varint byte 0x7b' do
        bytes = mod_result.serialize({ height: 123 })
        expect(bytes.unpack1('H*')).to eq('7b')
      end

      it 'height 800_000 encodes as 5-byte varint (FE prefix + 4-byte LE)' do
        bytes = mod_result.serialize({ height: 800_000 })
        expect(bytes.unpack1('H*')).to eq('fe00350c00')
      end
    end
  end
end
