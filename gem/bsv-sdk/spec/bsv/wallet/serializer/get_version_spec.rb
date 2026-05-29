# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::Wallet::Serializer::GetVersion' do
  let(:mod_args) { BSV::Wallet::Serializer::GetVersion::Args }
  let(:mod_result) { BSV::Wallet::Serializer::GetVersion::Result }

  describe 'Args' do
    it 'serialises to empty bytes' do
      expect(mod_args.serialize).to eq(''.b)
    end

    it 'deserialises any bytes to empty hash' do
      expect(mod_args.deserialize('')).to eq({})
    end
  end

  describe 'Result' do
    it 'round-trips a standard version string' do
      result = { version: '1.0.0' }
      bytes = mod_result.serialize(result)
      expect(mod_result.deserialize(bytes)).to eq(result)
    end

    it 'round-trips a longer version string' do
      result = { version: 'v2.5.1-beta+12345' }
      bytes = mod_result.serialize(result)
      expect(mod_result.deserialize(bytes)).to eq(result)
    end

    it 'round-trips an empty version string' do
      result = { version: '' }
      bytes = mod_result.serialize(result)
      expect(mod_result.deserialize(bytes)).to eq(result)
    end

    it 'serialises "1.0.0" to its ASCII bytes (no varint prefix)' do
      bytes = mod_result.serialize({ version: '1.0.0' })
      expect(bytes).to eq('1.0.0'.b)
      expect(bytes.bytesize).to eq(5)
    end

    context 'with go-sdk reference vectors' do
      it '"1.2.3" round-trips correctly' do
        bytes = mod_result.serialize({ version: '1.2.3' })
        expect(bytes.unpack1('H*')).to eq('312e322e33')
        expect(mod_result.deserialize(bytes)).to eq({ version: '1.2.3' })
      end

      it 'empty version round-trips to empty string' do
        bytes = mod_result.serialize({ version: '' })
        expect(bytes).to eq(''.b)
        expect(mod_result.deserialize(bytes)).to eq({ version: '' })
      end
    end
  end
end
