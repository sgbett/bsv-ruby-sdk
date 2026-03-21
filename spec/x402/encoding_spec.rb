# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'BSV::X402::Encoding' do
  describe '.base64url_encode / .base64url_decode' do
    it 'round-trips arbitrary bytes' do
      data = (0..255).map(&:chr).join
      expect(BSV::X402::Encoding.base64url_decode(BSV::X402::Encoding.base64url_encode(data))).to eq(data)
    end

    it 'encodes the empty string to an empty string' do
      expect(BSV::X402::Encoding.base64url_encode('')).to eq('')
    end

    it 'decodes an empty string to empty bytes' do
      expect(BSV::X402::Encoding.base64url_decode('')).to eq('')
    end

    it 'omits padding characters from encoded output' do
      encoded = BSV::X402::Encoding.base64url_encode('a')
      expect(encoded).not_to include('=')
    end

    it 'uses URL-safe characters (- and _ instead of + and /)' do
      # Byte 0xFB (11111011) encodes to a character containing + in standard base64,
      # URL-safe replaces it with -
      data = "\xFB\xFF"
      encoded = BSV::X402::Encoding.base64url_encode(data)
      expect(encoded).not_to include('+')
      expect(encoded).not_to include('/')
    end

    it 'decodes strings that have padding' do
      padded = 'eyJhIjoxfQ=='
      without_padding = 'eyJhIjoxfQ'
      expect(BSV::X402::Encoding.base64url_decode(padded)).to eq(BSV::X402::Encoding.base64url_decode(without_padding))
    end

    it 'matches a known encoding vector: {"a":1}' do
      # base64url of '{"a":1}' is 'eyJhIjoxfQ'
      expect(BSV::X402::Encoding.base64url_encode('{"a":1}')).to eq('eyJhIjoxfQ')
    end

    it 'raises EncodingError for malformed base64url' do
      expect { BSV::X402::Encoding.base64url_decode('not!base64url') }
        .to raise_error(BSV::X402::EncodingError)
    end

    it 'raises EncodingError when the string exceeds 64 KiB' do
      oversized = 'A' * 65_537
      expect { BSV::X402::Encoding.base64url_decode(oversized) }
        .to raise_error(BSV::X402::EncodingError, /64 KiB/)
    end
  end

  describe '.base64_encode / .base64_decode' do
    it 'round-trips arbitrary bytes' do
      data = 'raw transaction bytes \x00\xFF'
      expect(BSV::X402::Encoding.base64_decode(BSV::X402::Encoding.base64_encode(data))).to eq(data)
    end

    it 'includes padding in standard base64 output' do
      # 'a' encodes to 'YQ==' in standard base64
      expect(BSV::X402::Encoding.base64_encode('a')).to eq('YQ==')
    end

    it 'raises EncodingError for malformed standard base64' do
      expect { BSV::X402::Encoding.base64_decode('not!!!valid') }
        .to raise_error(BSV::X402::EncodingError)
    end
  end
end
