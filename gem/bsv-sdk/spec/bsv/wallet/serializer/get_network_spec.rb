# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::Wallet::Serializer::GetNetwork' do
  let(:mod_args) { BSV::Wallet::Serializer::GetNetwork::Args }
  let(:mod_result) { BSV::Wallet::Serializer::GetNetwork::Result }

  describe 'Args' do
    it 'serialises to empty bytes' do
      expect(mod_args.serialize).to eq(''.b)
    end

    it 'deserialises any bytes to empty hash' do
      expect(mod_args.deserialize('')).to eq({})
    end
  end

  describe 'Result' do
    context 'when mainnet' do
      it 'serialises to 0x00' do
        expect(mod_result.serialize({ network: :mainnet })).to eq("\x00".b)
      end

      it 'round-trips mainnet' do
        bytes = mod_result.serialize({ network: :mainnet })
        expect(mod_result.deserialize(bytes)).to eq({ network: :mainnet })
      end
    end

    context 'when testnet' do
      it 'serialises to 0x01' do
        expect(mod_result.serialize({ network: :testnet })).to eq("\x01".b)
      end

      it 'round-trips testnet' do
        bytes = mod_result.serialize({ network: :testnet })
        expect(mod_result.deserialize(bytes)).to eq({ network: :testnet })
      end
    end

    it 'raises on an unknown network symbol when serialising' do
      expect { mod_result.serialize({ network: :unknown }) }
        .to raise_error(BSV::Wallet::InvalidParameterError, /:mainnet or :testnet/)
    end

    it 'raises on a nil network when serialising' do
      expect { mod_result.serialize({ network: nil }) }
        .to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises on empty payload' do
      expect { mod_result.deserialize('') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises on 2-byte payload' do
      expect { mod_result.deserialize("\x00\x01") }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises on an unknown byte when deserialising' do
      expect { mod_result.deserialize("\x02".b) }
        .to raise_error(BSV::Wallet::InvalidParameterError, /0x00 \(mainnet\) or 0x01 \(testnet\), got 0x02/)
    end

    context 'with go-sdk reference vectors' do
      it 'mainnet: 1 byte = 0x00' do
        bytes = mod_result.serialize({ network: :mainnet })
        expect(bytes.bytesize).to eq(1)
        expect(bytes.unpack1('H*')).to eq('00')
      end

      it 'testnet: 1 byte = 0x01' do
        bytes = mod_result.serialize({ network: :testnet })
        expect(bytes.bytesize).to eq(1)
        expect(bytes.unpack1('H*')).to eq('01')
      end
    end
  end
end
