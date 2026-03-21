# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'BSV::X402::RequestBinding' do
  describe '.compute_headers_hash' do
    it 'returns a lowercase hex SHA-256 digest of length 64' do
      result = BSV::X402::RequestBinding.compute_headers_hash('host' => 'example.com')
      expect(result).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'sorts headers by name in ascending byte order' do
      result_a = BSV::X402::RequestBinding.compute_headers_hash('b' => '2', 'a' => '1')
      result_b = BSV::X402::RequestBinding.compute_headers_hash('a' => '1', 'b' => '2')
      expect(result_a).to eq(result_b)
    end

    it 'lowercases header names before sorting' do
      result_upper = BSV::X402::RequestBinding.compute_headers_hash('Content-Type' => 'application/json')
      result_lower = BSV::X402::RequestBinding.compute_headers_hash('content-type' => 'application/json')
      expect(result_upper).to eq(result_lower)
    end

    it 'trims whitespace from header values' do
      result_padded = BSV::X402::RequestBinding.compute_headers_hash('host' => '  example.com  ')
      result_clean  = BSV::X402::RequestBinding.compute_headers_hash('host' => 'example.com')
      expect(result_padded).to eq(result_clean)
    end

    it 'produces different hashes for different header sets' do
      a = BSV::X402::RequestBinding.compute_headers_hash('host' => 'a.example.com')
      b = BSV::X402::RequestBinding.compute_headers_hash('host' => 'b.example.com')
      expect(a).not_to eq(b)
    end

    it 'accepts symbol keys' do
      result_sym = BSV::X402::RequestBinding.compute_headers_hash(host: 'example.com')
      result_str = BSV::X402::RequestBinding.compute_headers_hash('host' => 'example.com')
      expect(result_sym).to eq(result_str)
    end
  end

  describe '.compute_body_hash' do
    it 'returns the SHA-256 of the empty string for a nil body' do
      empty_sha256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
      expect(BSV::X402::RequestBinding.compute_body_hash(nil)).to eq(empty_sha256)
    end

    it 'returns the SHA-256 of the empty string for an empty body' do
      empty_sha256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
      expect(BSV::X402::RequestBinding.compute_body_hash('')).to eq(empty_sha256)
    end

    it 'returns a deterministic hash for a given body' do
      body = 'hello world'
      result_a = BSV::X402::RequestBinding.compute_body_hash(body)
      result_b = BSV::X402::RequestBinding.compute_body_hash(body)
      expect(result_a).to eq(result_b)
    end

    it 'produces different hashes for different bodies' do
      a = BSV::X402::RequestBinding.compute_body_hash('body a')
      b = BSV::X402::RequestBinding.compute_body_hash('body b')
      expect(a).not_to eq(b)
    end

    it 'returns a lowercase hex string of length 64' do
      result = BSV::X402::RequestBinding.compute_body_hash('data')
      expect(result).to match(/\A[0-9a-f]{64}\z/)
    end
  end
end
