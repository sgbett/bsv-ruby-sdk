# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Primitives::Base58 do
  describe '.encode / .decode' do
    it 'round-trips arbitrary bytes' do
      bytes = ['0123456789abcdef'].pack('H*')
      encoded = described_class.encode(bytes)
      expect(described_class.decode(encoded)).to eq(bytes)
    end

    it 'preserves leading zero bytes' do
      bytes = "\x00\x00\x01".b
      encoded = described_class.encode(bytes)
      expect(encoded).to start_with('11')
      expect(described_class.decode(encoded)).to eq(bytes)
    end

    it 'encodes empty bytes to empty string' do
      expect(described_class.encode('')).to eq('')
    end

    it 'decodes empty string to empty bytes' do
      expect(described_class.decode('')).to eq(''.b)
    end

    it 'raises on invalid characters' do
      expect { described_class.decode('0OIl') }.to raise_error(ArgumentError, /invalid Base58 character/)
    end

    # Known vector: hex "00" -> "1"
    it 'encodes a single zero byte as "1"' do
      expect(described_class.encode("\x00".b)).to eq('1')
    end

    # Known vector from Bitcoin wiki
    it 'encodes "Hello World!" correctly' do
      encoded = described_class.encode('Hello World!')
      expect(encoded).to eq('2NEpo7TZRRrLZSi2U')
      expect(described_class.decode(encoded)).to eq('Hello World!')
    end
  end

  describe '.check_encode / .check_decode' do
    it 'round-trips with checksum verification' do
      payload = ['00751e76e8199196d454941c45d1b3a323f1433bd6'].pack('H*')
      encoded = described_class.check_encode(payload)
      expect(described_class.check_decode(encoded)).to eq(payload)
    end

    # Known Bitcoin address vector
    it 'encodes a mainnet P2PKH address correctly' do
      # Hash160 of generator point compressed pubkey with 0x00 version prefix
      payload = ['00751e76e8199196d454941c45d1b3a323f1433bd6'].pack('H*')
      encoded = described_class.check_encode(payload)
      expect(encoded).to eq('1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH')
    end

    it 'raises ChecksumError on corrupted data' do
      payload = ['00751e76e8199196d454941c45d1b3a323f1433bd6'].pack('H*')
      encoded = described_class.check_encode(payload)
      # Corrupt the last character
      corrupted = encoded[0...-1] + (encoded[-1] == 'A' ? 'B' : 'A')
      expect { described_class.check_decode(corrupted) }
        .to raise_error(BSV::Primitives::Base58::ChecksumError, /checksum mismatch/)
    end

    it 'raises ChecksumError on input too short' do
      short = described_class.encode("\x01\x02\x03".b)
      expect { described_class.check_decode(short) }
        .to raise_error(BSV::Primitives::Base58::ChecksumError, /too short/)
    end
  end
end
