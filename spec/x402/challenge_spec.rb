# frozen_string_literal: true

require_relative 'spec_helper'

# Test vector data defined outside describe block to avoid Lint/ConstantDefinitionInBlock.
VECTOR_NONCE_UTXO = BSV::X402::NonceUTXO.new(
  txid: '4f8b42a7c1d7c0e0a3e3f7b8d4c5a6b7c8d9e0f112233445566778899aabbcc',
  vout: 0,
  satoshis: 1,
  locking_script_hex: '76a91400112233445566778899aabbccddeeff0011223388ac'
).freeze

VECTOR_CHALLENGE_ATTRS = {
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
  nonce_utxo: VECTOR_NONCE_UTXO,
  expires_at: 1_700_000_000,
  require_mempool_accept: true,
  skip_scheme_validation: true
}.freeze

RSpec.describe BSV::X402::Challenge do
  let(:nonce_utxo) do
    BSV::X402::NonceUTXO.new(
      txid: 'deadbeef' * 8,
      vout: 0,
      satoshis: 1,
      locking_script_hex: "76a914#{'ab' * 20}88ac"
    )
  end

  let(:valid_attrs) do
    {
      v: 1,
      scheme: 'bsv-tx-v1',
      domain: 'example.com',
      method: 'GET',
      path: '/api/data',
      query: '',
      req_headers_sha256: 'a' * 64,
      req_body_sha256: 'b' * 64,
      amount_sats: 100,
      payee_locking_script_hex: "76a914#{'cc' * 20}88ac",
      nonce_utxo: nonce_utxo,
      expires_at: 9_999_999_999,
      require_mempool_accept: false
    }
  end

  describe '.new' do
    it 'constructs with valid attributes' do
      challenge = described_class.new(**valid_attrs)
      expect(challenge.v).to eq(1)
      expect(challenge.scheme).to eq('bsv-tx-v1')
      expect(challenge.domain).to eq('example.com')
      expect(challenge.amount_sats).to eq(100)
    end

    it 'is frozen after construction' do
      expect(described_class.new(**valid_attrs)).to be_frozen
    end

    it 'raises ValidationError when v is not 1' do
      expect { described_class.new(**valid_attrs, v: 2) }
        .to raise_error(BSV::X402::ValidationError, /v must be 1/)
    end

    it 'raises ValidationError when scheme is not bsv-tx-v1' do
      expect { described_class.new(**valid_attrs, scheme: 'other') }
        .to raise_error(BSV::X402::ValidationError, /scheme must be/)
    end

    it 'allows non-standard scheme when skip_scheme_validation is true' do
      expect do
        described_class.new(**valid_attrs, scheme: 'x402-bsv', skip_scheme_validation: true)
      end.not_to raise_error
    end

    it 'raises ValidationError when amount_sats is zero' do
      expect { described_class.new(**valid_attrs, amount_sats: 0) }
        .to raise_error(BSV::X402::ValidationError, /amount_sats must be a positive integer/)
    end

    it 'raises ValidationError when a required string field is missing' do
      expect { described_class.new(**valid_attrs, domain: nil) }
        .to raise_error(BSV::X402::ValidationError, /domain/)
    end

    it 'raises ValidationError when nonce_utxo is not a NonceUTXO' do
      expect { described_class.new(**valid_attrs, nonce_utxo: {}) }
        .to raise_error(BSV::X402::ValidationError, /nonce_utxo/)
    end
  end

  describe '.from_json' do
    it 'parses a valid JSON string' do
      json = described_class.new(**valid_attrs).to_json
      challenge = described_class.from_json(json)
      expect(challenge.domain).to eq('example.com')
      expect(challenge.amount_sats).to eq(100)
    end

    it 'raises EncodingError for malformed JSON' do
      expect { described_class.from_json('{not valid json}') }
        .to raise_error(BSV::X402::EncodingError, /invalid JSON/)
    end

    it 'raises ValidationError when nonce_utxo is missing from JSON' do
      hash = described_class.new(**valid_attrs).to_hash
      hash.delete('nonce_utxo')
      expect { described_class.from_json(JSON.generate(hash)) }
        .to raise_error(BSV::X402::ValidationError, /nonce_utxo/)
    end
  end

  describe '.from_header / #to_header' do
    it 'round-trips through base64url header encoding' do
      original  = described_class.new(**valid_attrs)
      header    = original.to_header
      restored  = described_class.from_header(header)

      expect(restored.domain).to eq(original.domain)
      expect(restored.amount_sats).to eq(original.amount_sats)
      expect(restored.nonce_utxo.txid).to eq(original.nonce_utxo.txid)
      expect(restored.require_mempool_accept).to eq(original.require_mempool_accept)
    end

    it 'raises EncodingError for invalid base64url input' do
      expect { described_class.from_header('not!valid!base64url') }
        .to raise_error(BSV::X402::EncodingError)
    end

    it 'raises EncodingError for valid base64url but invalid JSON' do
      bad_json = BSV::X402::Encoding.base64url_encode('{broken json')
      expect { described_class.from_header(bad_json) }
        .to raise_error(BSV::X402::EncodingError, /invalid JSON/)
    end
  end

  describe '#to_json' do
    it 'produces canonical JSON with sorted keys' do
      challenge = described_class.new(**valid_attrs)
      json      = challenge.to_json
      keys      = JSON.parse(json).keys
      expect(keys).to eq(keys.sort)
    end

    it 'includes nonce_utxo with sorted keys' do
      challenge = described_class.new(**valid_attrs)
      nonce_keys = JSON.parse(challenge.to_json)['nonce_utxo'].keys
      expect(nonce_keys).to eq(nonce_keys.sort)
    end
  end

  describe '#sha256' do
    it 'returns a lowercase hex string of length 64' do
      challenge = described_class.new(**valid_attrs)
      expect(challenge.sha256).to match(/\A[0-9a-f]{64}\z/)
    end

    it 'returns a different hash when a field changes' do
      a = described_class.new(**valid_attrs)
      b = described_class.new(**valid_attrs, amount_sats: 200)
      expect(a.sha256).not_to eq(b.sha256)
    end
  end

  describe '#expired?' do
    it 'returns false when expires_at equals now' do
      now       = 1_700_000_000
      challenge = described_class.new(**valid_attrs, expires_at: now)
      expect(challenge.expired?(now)).to be(false)
    end

    it 'returns true when expires_at is one second before now' do
      now       = 1_700_000_001
      challenge = described_class.new(**valid_attrs, expires_at: now - 1)
      expect(challenge.expired?(now)).to be(true)
    end

    it 'returns false when expires_at is in the future' do
      challenge = described_class.new(**valid_attrs, expires_at: 9_999_999_999)
      expect(challenge.expired?).to be(false)
    end
  end

  describe 'test vector conformance' do
    it 'computes the correct sha256 for challenge-vector-001' do
      challenge = described_class.new(**VECTOR_CHALLENGE_ATTRS)
      expect(challenge.sha256).to eq('e1c2b034b378048b8a7299137f9ffcabfe0fc6a06018f15dd05b553858237aa9')
    end

    it 'produces the expected canonical JSON for challenge-vector-001' do
      challenge = described_class.new(**VECTOR_CHALLENGE_ATTRS)
      expected  = '{"amount_sats":50,"domain":"api.example.com","expires_at":1700000000,' \
                  '"method":"GET","nonce_utxo":{"locking_script_hex":"76a91400112233445566778899aabbccddeeff0011223388ac",' \
                  '"satoshis":1,"txid":"4f8b42a7c1d7c0e0a3e3f7b8d4c5a6b7c8d9e0f112233445566778899aabbcc","vout":0},' \
                  '"path":"/v1/weather","payee_locking_script_hex":"76a91489abcdefabbaabbaabbaabbaabbaabbaabba88ac",' \
                  '"query":"city=lisbon","req_body_sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",' \
                  '"req_headers_sha256":"5b2d5c2d9c7e1a2e3f0b4f6d7c8a9e0f1a2b3c4d5e6f7081920a1b2c3d4e5f60",' \
                  '"require_mempool_accept":true,"scheme":"x402-bsv","v":1}'
      expect(challenge.to_json).to eq(expected)
    end
  end
end
