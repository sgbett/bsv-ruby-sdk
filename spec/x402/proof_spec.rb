# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe BSV::X402::Proof do
  # Minimal valid raw transaction (coinbase-style, 64 bytes of zeros for testing).
  # We use a known txid/rawtx pair rather than generating a real one.
  # sha256d(raw_bytes).reverse in hex == txid
  let(:raw_tx_bytes) { "\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00" }
  let(:valid_rawtx_b64) { BSV::X402::Encoding.base64_encode(raw_tx_bytes) }
  let(:computed_txid) do
    hash = BSV::Primitives::Digest.sha256d(raw_tx_bytes)
    hash.reverse.unpack1('H*')
  end

  let(:valid_attrs) do
    {
      v: 1,
      scheme: 'bsv-tx-v1',
      challenge_sha256: 'a' * 64,
      request: {
        'method' => 'GET',
        'path' => '/api/data',
        'query' => '',
        'req_headers_sha256' => 'b' * 64,
        'req_body_sha256' => 'c' * 64
      },
      payment: {
        'txid' => computed_txid,
        'rawtx_b64' => valid_rawtx_b64
      }
    }
  end

  describe '.new' do
    it 'constructs with valid attributes' do
      proof = described_class.new(**valid_attrs)
      expect(proof.v).to eq(1)
      expect(proof.scheme).to eq('bsv-tx-v1')
      expect(proof.challenge_sha256).to eq('a' * 64)
    end

    it 'is frozen after construction' do
      expect(described_class.new(**valid_attrs)).to be_frozen
    end

    it 'raises ValidationError when v is not 1' do
      expect { described_class.new(**valid_attrs, v: 2) }
        .to raise_error(BSV::X402::ValidationError, /v must be 1/)
    end

    it 'raises ValidationError when scheme is wrong' do
      expect { described_class.new(**valid_attrs, scheme: 'other') }
        .to raise_error(BSV::X402::ValidationError, /scheme must be/)
    end

    it 'raises ValidationError when challenge_sha256 is missing' do
      expect { described_class.new(**valid_attrs, challenge_sha256: '') }
        .to raise_error(BSV::X402::ValidationError, /challenge_sha256/)
    end

    it 'raises ValidationError when request is missing a field' do
      bad_request = valid_attrs[:request].reject { |k, _| k == 'method' }
      expect { described_class.new(**valid_attrs, request: bad_request) }
        .to raise_error(BSV::X402::ValidationError, /request.*method/)
    end

    it 'raises ValidationError when payment txid is missing' do
      bad_payment = valid_attrs[:payment].reject { |k, _| k == 'txid' }
      expect { described_class.new(**valid_attrs, payment: bad_payment) }
        .to raise_error(BSV::X402::ValidationError, /payment.*txid/)
    end
  end

  describe '.from_json' do
    it 'parses a valid JSON string' do
      json  = described_class.new(**valid_attrs).to_json
      proof = described_class.from_json(json)
      expect(proof.challenge_sha256).to eq('a' * 64)
    end

    it 'raises EncodingError for malformed JSON' do
      expect { described_class.from_json('{not json}') }
        .to raise_error(BSV::X402::EncodingError, /invalid JSON/)
    end
  end

  describe '.from_header / #to_header' do
    it 'round-trips through base64url encoding' do
      original = described_class.new(**valid_attrs)
      restored = described_class.from_header(original.to_header)

      expect(restored.challenge_sha256).to eq(original.challenge_sha256)
      expect(restored.request['method']).to eq(original.request['method'])
      expect(restored.payment['txid']).to eq(original.payment['txid'])
    end

    it 'raises EncodingError for truncated base64url' do
      # Partial base64url that decodes but isn't valid JSON
      truncated = BSV::X402::Encoding.base64url_encode('{"v":1')[0..3]
      expect { described_class.from_header(truncated) }
        .to raise_error(BSV::X402::EncodingError)
    end
  end

  describe '#to_json' do
    it 'produces canonical JSON with sorted top-level keys' do
      proof = described_class.new(**valid_attrs)
      keys  = JSON.parse(proof.to_json).keys
      expect(keys).to eq(keys.sort)
    end
  end

  describe '#decoded_tx' do
    it 'decodes the rawtx_b64 field to raw bytes' do
      proof = described_class.new(**valid_attrs)
      expect(proof.decoded_tx).to eq(raw_tx_bytes)
    end
  end

  describe '#valid_txid?' do
    it 'returns true when txid matches double-SHA-256 of the raw transaction' do
      proof = described_class.new(**valid_attrs)
      expect(proof.valid_txid?).to be(true)
    end

    it 'returns false when txid does not match the raw transaction' do
      bad_payment = valid_attrs[:payment].merge('txid' => 'ff' * 32)
      proof = described_class.new(**valid_attrs, payment: bad_payment)
      expect(proof.valid_txid?).to be(false)
    end
  end
end
