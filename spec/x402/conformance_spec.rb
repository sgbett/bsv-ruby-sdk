# frozen_string_literal: true

require_relative 'spec_helper'

# Test vector: challenge-vector-001
# Source: https://github.com/sgbett/merkleworks-x402-spec/blob/main/test-vectors/challenge-vector-001.md
#
# These constants are defined at file scope to avoid Lint/ConstantDefinitionInBlock.
CONFORMANCE_NONCE_UTXO = BSV::X402::NonceUTXO.new(
  txid: '4f8b42a7c1d7c0e0a3e3f7b8d4c5a6b7c8d9e0f112233445566778899aabbcc',
  vout: 0,
  satoshis: 1,
  locking_script_hex: '76a91400112233445566778899aabbccddeeff0011223388ac'
).freeze

CONFORMANCE_CHALLENGE_ATTRS = {
  v: 1,
  scheme: 'x402-bsv',
  domain: 'api.example.com',
  method: 'GET',
  path: '/v1/weather',
  query: 'city=lisbon',
  req_headers_sha256: '5b2d5c2d9c7e1a2e3f0b4f6d7c8a9e0f1a2b3c4d5e6f7081920a1b2c3d4e5f60',
  req_body_sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
  amount_sats: 50,
  payee_locking_script_hex: '76a91489abcdefabbaabbaabbaabbaabbaabbaabba88ac',
  nonce_utxo: CONFORMANCE_NONCE_UTXO,
  expires_at: 1_700_000_000,
  require_mempool_accept: true,
  skip_scheme_validation: true
}.freeze

# Expected canonical JSON for challenge-vector-001.
CONFORMANCE_CANONICAL_JSON =
  '{"amount_sats":50,"domain":"api.example.com","expires_at":1700000000,' \
  '"method":"GET","nonce_utxo":{"locking_script_hex":"76a91400112233445566778899aabbccddeeff0011223388ac",' \
  '"satoshis":1,"txid":"4f8b42a7c1d7c0e0a3e3f7b8d4c5a6b7c8d9e0f112233445566778899aabbcc","vout":0},' \
  '"path":"/v1/weather","payee_locking_script_hex":"76a91489abcdefabbaabbaabbaabbaabbaabbaabba88ac",' \
  '"query":"city=lisbon","req_body_sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",' \
  '"req_headers_sha256":"5b2d5c2d9c7e1a2e3f0b4f6d7c8a9e0f1a2b3c4d5e6f7081920a1b2c3d4e5f60",' \
  '"require_mempool_accept":true,"scheme":"x402-bsv","v":1}'

# Expected challenge_sha256 for challenge-vector-001 (spec §test-vectors).
CONFORMANCE_EXPECTED_SHA256 = 'e1c2b034b378048b8a7299137f9ffcabfe0fc6a06018f15dd05b553858237aa9'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'x402 conformance: challenge-vector-001' do
  subject(:challenge) { BSV::X402::Challenge.new(**CONFORMANCE_CHALLENGE_ATTRS) }

  # -----------------------------------------------------------------------
  # Canonical JSON output
  # -----------------------------------------------------------------------

  describe 'canonical JSON serialisation' do
    it 'produces the exact canonical JSON bytes specified by the test vector' do
      expect(challenge.to_json).to eq(CONFORMANCE_CANONICAL_JSON)
    end

    it 'has all top-level keys in ascending lexicographic order' do
      keys = JSON.parse(challenge.to_json).keys
      expect(keys).to eq(keys.sort)
    end

    it 'has all nonce_utxo keys in ascending lexicographic order' do
      nonce_keys = JSON.parse(challenge.to_json)['nonce_utxo'].keys
      expect(nonce_keys).to eq(nonce_keys.sort)
    end

    it 'serialises integers as JSON numbers (not strings)' do
      parsed = JSON.parse(challenge.to_json)
      expect(parsed['amount_sats']).to be_a(Integer)
      expect(parsed['expires_at']).to be_a(Integer)
      expect(parsed['v']).to be_a(Integer)
      expect(parsed['nonce_utxo']['satoshis']).to be_a(Integer)
      expect(parsed['nonce_utxo']['vout']).to be_a(Integer)
    end

    it 'serialises booleans as JSON booleans (not strings)' do
      parsed = JSON.parse(challenge.to_json)
      # require_mempool_accept is set to true in the vector, so it must parse as TrueClass.
      expect(parsed['require_mempool_accept']).to be(true).or be(false)
    end

    it 'serialises string fields without unnecessary escaping' do
      json = challenge.to_json
      # No spurious backslash escapes in plain ASCII field values.
      expect(json).not_to include('\/')
    end
  end

  # -----------------------------------------------------------------------
  # SHA-256 hash
  # -----------------------------------------------------------------------

  describe '#sha256' do
    it 'matches the expected hash from the spec test vector' do
      expect(challenge.sha256).to eq(CONFORMANCE_EXPECTED_SHA256)
    end

    it 'returns a 64-character lowercase hex string' do
      expect(challenge.sha256).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'is deterministic — calling sha256 twice returns the same value' do
      first_call  = challenge.sha256
      second_call = challenge.sha256
      expect(first_call).to eq(second_call)
    end

    it 'differs when any field is changed' do
      mutated = BSV::X402::Challenge.new(**CONFORMANCE_CHALLENGE_ATTRS, amount_sats: 51)
      expect(mutated.sha256).not_to eq(CONFORMANCE_EXPECTED_SHA256)
    end
  end

  # -----------------------------------------------------------------------
  # Round-trip through header encoding
  # -----------------------------------------------------------------------

  describe 'header round-trip' do
    it 'survives base64url encode → decode without data loss' do
      header    = challenge.to_header
      restored  = BSV::X402::Challenge.from_header(header, skip_scheme_validation: true)

      expect(restored.sha256).to eq(challenge.sha256)
      expect(restored.to_json).to eq(challenge.to_json)
    end

    it 'produces a header string containing only URL-safe characters' do
      header = challenge.to_header
      expect(header).to match(/\A[A-Za-z0-9\-_]+\z/)
    end
  end

  # -----------------------------------------------------------------------
  # Field-level assertions
  # -----------------------------------------------------------------------

  describe 'field values' do
    it 'has v = 1' do
      expect(challenge.v).to eq(1)
    end

    it 'has scheme x402-bsv' do
      expect(challenge.scheme).to eq('x402-bsv')
    end

    it 'has amount_sats 50' do
      expect(challenge.amount_sats).to eq(50)
    end

    it 'has expires_at 1700000000' do
      expect(challenge.expires_at).to eq(1_700_000_000)
    end

    it 'has require_mempool_accept true' do
      expect(challenge.require_mempool_accept).to be(true)
    end

    it 'has the correct nonce txid' do
      expect(challenge.nonce_utxo.txid).to eq('4f8b42a7c1d7c0e0a3e3f7b8d4c5a6b7c8d9e0f112233445566778899aabbcc')
    end

    it 'has nonce vout 0' do
      expect(challenge.nonce_utxo.vout).to eq(0)
    end

    it 'has nonce satoshis 1' do
      expect(challenge.nonce_utxo.satoshis).to eq(1)
    end
  end

  # -----------------------------------------------------------------------
  # CanonicalJSON properties
  # -----------------------------------------------------------------------

  describe 'BSV::X402::CanonicalJSON' do
    it 'encodes a nested hash with recursively sorted keys' do
      input    = { 'z' => 1, 'a' => { 'z' => 2, 'a' => 3 } }
      output   = BSV::X402::CanonicalJSON.encode(input)
      parsed   = JSON.parse(output)
      expect(parsed.keys).to eq(%w[a z])
      expect(parsed['a'].keys).to eq(%w[a z])
    end

    it 'encodes a string with a forward slash without escaping it' do
      output = BSV::X402::CanonicalJSON.encode({ 'path' => '/v1/weather' })
      expect(output).to include('"/v1/weather"')
    end

    it 'produces byte-identical output to the known vector JSON' do
      # Reconstruct from the challenge hash and verify byte equality.
      json = BSV::X402::CanonicalJSON.encode(challenge.to_hash)
      expect(json.bytes).to eq(CONFORMANCE_CANONICAL_JSON.bytes)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
