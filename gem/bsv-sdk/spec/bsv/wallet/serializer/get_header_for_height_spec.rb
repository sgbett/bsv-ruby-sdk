# frozen_string_literal: true

require 'spec_helper'

# Block header from go-sdk get_header_test.go (genesis block header)
GENESIS_HEADER_HEX = '010000006fe28c0ab6f1b372c1a6a246ae63f74f931e8365e15a089c68d619000' \
                     '0000000982051fd1e4ba744bbbe680e1fee14677ba1a3c3540bf7b1cdb606e857' \
                     '233e0e61bc6649ffff001d01e36299'

RSpec.describe 'BSV::Wallet::Serializer::GetHeaderForHeight' do
  let(:mod_args) { BSV::Wallet::Serializer::GetHeaderForHeight::Args }
  let(:mod_result) { BSV::Wallet::Serializer::GetHeaderForHeight::Result }
  let(:genesis_header) { [GENESIS_HEADER_HEX].pack('H*') }

  describe 'Args' do
    it 'round-trips height 1' do
      args = { height: 1 }
      bytes = mod_args.serialize(args)
      expect(mod_args.deserialize(bytes)).to eq(args)
    end

    it 'round-trips height 100_000' do
      args = { height: 100_000 }
      bytes = mod_args.serialize(args)
      expect(mod_args.deserialize(bytes)).to eq(args)
    end

    it 'round-trips height 800_000' do
      args = { height: 800_000 }
      bytes = mod_args.serialize(args)
      expect(mod_args.deserialize(bytes)).to eq(args)
    end

    it 'round-trips height 0' do
      args = { height: 0 }
      bytes = mod_args.serialize(args)
      expect(mod_args.deserialize(bytes)).to eq(args)
    end

    it 'raises on empty payload' do
      expect { mod_args.deserialize('') }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    context 'with go-sdk reference vectors' do
      it 'height 800_000 encodes as 5-byte varint' do
        bytes = mod_args.serialize({ height: 800_000 })
        expect(bytes.unpack1('H*')).to eq('fe00350c00')
      end

      it 'height 1 encodes as 1-byte varint' do
        bytes = mod_args.serialize({ height: 1 })
        expect(bytes.unpack1('H*')).to eq('01')
      end
    end
  end

  describe 'Result' do
    it 'round-trips the genesis block header' do
      result = { header: genesis_header }
      bytes = mod_result.serialize(result)
      expect(bytes.bytesize).to eq(80)
      expect(mod_result.deserialize(bytes)).to eq(result)
    end

    it 'serialises to exactly 80 bytes' do
      bytes = mod_result.serialize({ header: genesis_header })
      expect(bytes.bytesize).to eq(80)
    end

    it 'raises when header is not 80 bytes on serialize' do
      expect do
        mod_result.serialize({ header: 'short'.b })
      end.to raise_error(BSV::Wallet::InvalidParameterError, /80 bytes/)
    end

    it 'raises when payload is not 80 bytes on deserialize' do
      expect do
        mod_result.deserialize('x' * 79)
      end.to raise_error(BSV::Wallet::InvalidParameterError, /80 bytes/)
    end

    it 'raises on empty payload' do
      expect do
        mod_result.deserialize('')
      end.to raise_error(BSV::Wallet::InvalidParameterError, /80 bytes/)
    end

    context 'with go-sdk genesis header reference vector' do
      it 'preserves all 80 bytes verbatim' do
        bytes = mod_result.serialize({ header: genesis_header })
        expect(bytes.unpack1('H*')).to eq(GENESIS_HEADER_HEX)
      end
    end
  end
end
