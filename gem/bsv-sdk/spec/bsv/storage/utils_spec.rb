# frozen_string_literal: true

require 'spec_helper'

# TS-SDK conformance vectors from StorageUtils.test.ts lines 6-10 and the bad-checksum URL.
FILE_HEX = '687da27f04a112aa48f1cab2e7949f1eea4f7ba28319c1e999910cd561a634a05a3516e6db'
HASH_HEX = '1a5ec49a3f32cd56d19732e89bde5d81755ddc0fd8515dc8b226d47654139dca'
EXAMPLE_URL = 'XUT6PqWb3GP3LR7dmBMCJwZ3oo5g1iGCF3CrpzyuJCemkGu1WGoq'
BAD_CHECKSUM_URL = 'XUU7cTfy6fA6q2neLDmzPqJnGB6o18PXKoGaWLPrH1SeWLKgdCKq'

RSpec.describe BSV::Storage::Utils do
  let(:example_file) { [FILE_HEX].pack('H*') }
  let(:example_hash) { [HASH_HEX].pack('H*') }

  describe '.get_url_for_hash' do
    it 'encodes the conformance vector hash to the expected URL' do
      expect(described_class.get_url_for_hash(example_hash)).to eq(EXAMPLE_URL)
    end

    it 'raises on a 33-byte hash' do
      expect { described_class.get_url_for_hash("#{example_hash}\x00") }
        .to raise_error(ArgumentError, 'Hash length must be 32 bytes (sha256)')
    end

    it 'raises on a 31-byte hash' do
      expect { described_class.get_url_for_hash(example_hash[0, 31]) }
        .to raise_error(ArgumentError, 'Hash length must be 32 bytes (sha256)')
    end

    it 'raises on an empty hash' do
      expect { described_class.get_url_for_hash(''.b) }
        .to raise_error(ArgumentError, 'Hash length must be 32 bytes (sha256)')
    end

    it 'raises on the full file bytes (wrong length)' do
      expect { described_class.get_url_for_hash(example_file) }
        .to raise_error(ArgumentError, 'Hash length must be 32 bytes (sha256)')
    end
  end

  describe '.get_url_for_file' do
    it 'produces the expected URL for the conformance vector file' do
      expect(described_class.get_url_for_file(example_file)).to eq(EXAMPLE_URL)
    end

    it 'produces the same URL as get_url_for_hash(sha256(file))' do
      require 'openssl'
      direct_hash = OpenSSL::Digest::SHA256.digest(example_file)
      expect(described_class.get_url_for_file(example_file))
        .to eq(described_class.get_url_for_hash(direct_hash))
    end
  end

  describe '.get_hash_from_url' do
    it 'decodes the conformance vector URL to the correct hash hex' do
      hash = described_class.get_hash_from_url(EXAMPLE_URL)
      expect(hash.unpack1('H*')).to eq(HASH_HEX)
    end

    it 'decodes the same hash as hashing the file directly' do
      require 'openssl'
      hash_from_url = described_class.get_hash_from_url(EXAMPLE_URL)
      hash_from_file = OpenSSL::Digest::SHA256.digest(example_file)
      expect(hash_from_url).to eq(hash_from_file)
    end

    it 'raises on a bad-checksum URL' do
      expect { described_class.get_hash_from_url(BAD_CHECKSUM_URL) }
        .to raise_error(BSV::Primitives::Base58::ChecksumError)
    end

    it 'raises on an empty string' do
      expect { described_class.get_hash_from_url('') }
        .to raise_error(ArgumentError)
    end

    it 'raises on a URL with wrong decoded length' do
      expect { described_class.get_hash_from_url('SomeBase58CheckTooShortOrTooLong') }
        .to raise_error(StandardError)
    end

    it 'raises on a URL with an invalid prefix' do
      expect { described_class.get_hash_from_url('AInvalidPrefixTestString1') }
        .to raise_error(StandardError)
    end

    it 'accepts uhrp: prefixed URLs' do
      hash = described_class.get_hash_from_url("uhrp:#{EXAMPLE_URL}")
      expect(hash.unpack1('H*')).to eq(HASH_HEX)
    end

    it 'accepts uhrp:// prefixed URLs' do
      hash = described_class.get_hash_from_url("uhrp://#{EXAMPLE_URL}")
      expect(hash.unpack1('H*')).to eq(HASH_HEX)
    end

    it 'accepts UHRP: upper-case prefixed URLs (case-insensitive)' do
      hash = described_class.get_hash_from_url("UHRP:#{EXAMPLE_URL}")
      expect(hash.unpack1('H*')).to eq(HASH_HEX)
    end
  end

  describe '.normalize_url' do
    it 'strips the uhrp: prefix' do
      expect(described_class.normalize_url("uhrp:#{EXAMPLE_URL}")).to eq(EXAMPLE_URL)
    end

    it 'strips uhrp:// (scheme + authority)' do
      expect(described_class.normalize_url("uhrp://#{EXAMPLE_URL}")).to eq(EXAMPLE_URL)
    end

    it 'strips UHRP: in upper case (case-insensitive)' do
      expect(described_class.normalize_url("UHRP:#{EXAMPLE_URL}")).to eq(EXAMPLE_URL)
    end

    it 'leaves a bare URL (no prefix) unchanged' do
      expect(described_class.normalize_url(EXAMPLE_URL)).to eq(EXAMPLE_URL)
    end

    it 'does not strip web+uhrp:// (TS parity — only uhrp: is normalised)' do
      with_web = "web+uhrp://#{EXAMPLE_URL}"
      expect(described_class.normalize_url(with_web)).to eq(with_web)
    end
  end

  describe '.valid_url?' do
    it 'returns true for the conformance vector URL' do
      expect(described_class.valid_url?(EXAMPLE_URL)).to be(true)
    end

    it 'returns false for a bad-checksum URL' do
      expect(described_class.valid_url?(BAD_CHECKSUM_URL)).to be(false)
    end

    it 'returns false for a URL with wrong decoded length' do
      expect(described_class.valid_url?('SomeBase58CheckTooShortOrTooLong')).to be(false)
    end

    it 'returns false for a URL with invalid prefix' do
      expect(described_class.valid_url?('AnotherInvalidPrefixTestString')).to be(false)
    end

    it 'returns false for an empty string' do
      expect(described_class.valid_url?('')).to be(false)
    end

    it 'returns true for a uhrp:// prefixed URL' do
      expect(described_class.valid_url?("uhrp://#{EXAMPLE_URL}")).to be(true)
    end
  end
end
