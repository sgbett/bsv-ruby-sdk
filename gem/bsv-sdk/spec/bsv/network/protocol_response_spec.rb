# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::ProtocolResponse do
  let(:ok_response)         { fake_http_response(200, '{"txid":"abc"}', content_type: 'application/json') }
  let(:not_found_response)  { fake_http_response(404, 'not found') }
  let(:too_many_response)   { fake_http_response(429, 'slow down') }
  let(:server_err_response) { fake_http_response(500, 'server error') }
  let(:bad_req_response)    { fake_http_response(400, 'bad request') }

  describe 'construction with 2xx response' do
    subject(:pr) { described_class.new(ok_response) }

    it 'is successful' do
      expect(pr.success?).to be true
    end

    it 'is not an error' do
      expect(pr.error?).to be false
    end

    it 'is not a not-found' do
      expect(pr.not_found?).to be false
    end

    it 'is not retryable' do
      expect(pr.retryable?).to be false
    end
  end

  describe 'construction with 404 response' do
    subject(:pr) { described_class.new(not_found_response) }

    it 'is not successful' do
      expect(pr.success?).to be false
    end

    it 'is not_found' do
      expect(pr.not_found?).to be true
    end

    it 'is not retryable' do
      expect(pr.retryable?).to be false
    end
  end

  describe 'construction with 429 response' do
    subject(:pr) { described_class.new(too_many_response) }

    it 'is retryable' do
      expect(pr.retryable?).to be true
    end
  end

  describe 'construction with 500 response' do
    subject(:pr) { described_class.new(server_err_response) }

    it 'is retryable' do
      expect(pr.retryable?).to be true
    end
  end

  describe 'construction with 400 response' do
    subject(:pr) { described_class.new(bad_req_response) }

    it 'is an error' do
      expect(pr.error?).to be true
    end

    it 'is not retryable' do
      expect(pr.retryable?).to be false
    end
  end

  describe 'ok: override' do
    it '2xx with ok: false is not successful (ARC REJECTED pattern)' do
      pr = described_class.new(ok_response, ok: false)
      expect(pr.success?).to be false
    end

    it '404 with ok: true is successful (WoC is_utxo pattern)' do
      pr = described_class.new(not_found_response, ok: true)
      expect(pr.success?).to be true
    end

    it '404 with ok: true still reports not_found? (transport status independent)' do
      pr = described_class.new(not_found_response, ok: true)
      expect(pr.not_found?).to be true
    end
  end

  describe '.data' do
    it 'returns provided data' do
      pr = described_class.new(ok_response, data: { txid: 'abc' })
      expect(pr.data).to eq({ txid: 'abc' })
    end
  end

  describe '.canonical' do
    it 'delegates to .data' do
      pr = described_class.new(ok_response, data: 'raw')
      expect(pr.canonical).to eq('raw')
    end
  end

  describe '.error_message' do
    it 'returns provided error message' do
      pr = described_class.new(bad_req_response, error_message: 'invalid tx')
      expect(pr.error_message).to eq('invalid tx')
    end
  end

  describe '.message alias' do
    it 'works as alias for error_message' do
      pr = described_class.new(bad_req_response, error_message: 'invalid tx')
      expect(pr.message).to eq('invalid tx')
    end
  end

  describe 'HTTP response delegation' do
    subject(:pr) { described_class.new(ok_response) }

    it 'delegates .body to HTTP response' do
      expect(pr.body).to eq('{"txid":"abc"}')
    end

    it 'delegates .code to HTTP response' do
      expect(pr.code).to eq('200')
    end

    it 'delegates .content_type to HTTP response' do
      expect(pr.content_type).to eq('application/json')
    end
  end

  describe 'nil HTTP response' do
    subject(:pr) { described_class.new(nil) }

    it 'returns nil for .body' do
      expect(pr.body).to be_nil
    end

    it 'returns nil for .code' do
      expect(pr.code).to be_nil
    end

    it 'returns nil for .content_type' do
      expect(pr.content_type).to be_nil
    end

    it 'not_found? returns false without raising' do
      expect(pr.not_found?).to be false
    end

    it 'retryable? returns false without raising' do
      expect(pr.retryable?).to be false
    end
  end

  describe '.with()' do
    let(:original) { described_class.new(ok_response, data: 'original', error_message: 'none') }

    it 'creates a new response with overridden data' do
      derived = original.with(data: 'overridden')
      expect(derived.data).to eq('overridden')
    end

    it 'preserves non-overridden fields' do
      derived = original.with(data: 'overridden')
      expect(derived.error_message).to eq('none')
    end

    it 'allows overriding ok:' do
      derived = original.with(ok: false)
      expect(derived.success?).to be false
    end

    it 'preserves HTTP delegation after with()' do
      derived = original.with(data: 'new')
      expect(derived.code).to eq('200')
    end

    it 'leaves the original unchanged' do
      original.with(data: 'other')
      expect(original.data).to eq('original')
    end

    it 'returns a frozen instance' do
      derived = original.with(data: 'new')
      expect(derived).to be_frozen
    end
  end

  describe 'immutability' do
    it 'is frozen after construction' do
      pr = described_class.new(ok_response)
      expect(pr).to be_frozen
    end
  end
end
