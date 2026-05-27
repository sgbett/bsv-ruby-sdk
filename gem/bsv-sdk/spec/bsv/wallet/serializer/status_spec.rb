# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/MultipleDescribes
RSpec.describe 'BSV::Wallet::Serializer::IsAuthenticated' do
  let(:mod_args)   { BSV::Wallet::Serializer::IsAuthenticated::Args }
  let(:mod_result) { BSV::Wallet::Serializer::IsAuthenticated::Result }

  describe 'Args' do
    it 'serialises to empty bytes' do
      expect(mod_args.serialize).to eq(''.b)
    end

    it 'deserialises any bytes to empty hash' do
      expect(mod_args.deserialize('')).to eq({})
    end
  end

  describe 'Result' do
    it 'serialises true to 0x01' do
      expect(mod_result.serialize({ authenticated: true })).to eq("\x01".b)
    end

    it 'serialises false to 0x00' do
      expect(mod_result.serialize({ authenticated: false })).to eq("\x00".b)
    end

    it 'round-trips authenticated: true' do
      bytes = mod_result.serialize({ authenticated: true })
      expect(mod_result.deserialize(bytes)).to eq({ authenticated: true })
    end

    it 'round-trips authenticated: false' do
      bytes = mod_result.serialize({ authenticated: false })
      expect(mod_result.deserialize(bytes)).to eq({ authenticated: false })
    end

    it 'raises on empty payload' do
      expect { mod_result.deserialize('') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises on 2-byte payload' do
      expect { mod_result.deserialize("\x01\x00") }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    context 'with go-sdk reference vectors' do
      it 'true: 1 byte = 0x01' do
        bytes = mod_result.serialize({ authenticated: true })
        expect(bytes.bytesize).to eq(1)
        expect(bytes.unpack1('H*')).to eq('01')
      end

      it 'false: 1 byte = 0x00' do
        bytes = mod_result.serialize({ authenticated: false })
        expect(bytes.bytesize).to eq(1)
        expect(bytes.unpack1('H*')).to eq('00')
      end
    end
  end
end

RSpec.describe 'BSV::Wallet::Serializer::WaitForAuthentication' do
  let(:mod_args)   { BSV::Wallet::Serializer::WaitForAuthentication::Args }
  let(:mod_result) { BSV::Wallet::Serializer::WaitForAuthentication::Result }

  describe 'Args' do
    it 'serialises to empty bytes' do
      expect(mod_args.serialize).to eq(''.b)
    end

    it 'deserialises any bytes to empty hash' do
      expect(mod_args.deserialize('')).to eq({})
    end
  end

  describe 'Result' do
    it 'serialises to empty bytes regardless of input' do
      expect(mod_result.serialize({ authenticated: false })).to eq(''.b)
      expect(mod_result.serialize({ authenticated: true })).to eq(''.b)
      expect(mod_result.serialize).to eq(''.b)
    end

    it 'deserialises nil payload to authenticated: true' do
      expect(mod_result.deserialize(nil)).to eq({ authenticated: true })
    end

    it 'deserialises empty payload to authenticated: true' do
      expect(mod_result.deserialize('')).to eq({ authenticated: true })
    end

    it 'deserialises any payload to authenticated: true (matching go-sdk)' do
      expect(mod_result.deserialize("\x00")).to eq({ authenticated: true })
    end
  end
end
# rubocop:enable RSpec/MultipleDescribes
