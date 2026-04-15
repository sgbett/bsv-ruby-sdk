# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::Auth::AuthHeaders' do
  subject(:mod) { BSV::Auth::AuthHeaders }

  describe 'constants' do
    it 'defines AUTH_PREFIX' do
      expect(mod::AUTH_PREFIX).to eq('x-bsv-auth')
    end

    it 'defines BSV_PREFIX' do
      expect(mod::BSV_PREFIX).to eq('x-bsv-')
    end

    it 'defines VERSION' do
      expect(mod::VERSION).to eq('x-bsv-auth-version')
    end

    it 'defines IDENTITY_KEY' do
      expect(mod::IDENTITY_KEY).to eq('x-bsv-auth-identity-key')
    end

    it 'defines NONCE' do
      expect(mod::NONCE).to eq('x-bsv-auth-nonce')
    end

    it 'defines YOUR_NONCE' do
      expect(mod::YOUR_NONCE).to eq('x-bsv-auth-your-nonce')
    end

    it 'defines REQUEST_ID' do
      expect(mod::REQUEST_ID).to eq('x-bsv-auth-request-id')
    end

    it 'defines MESSAGE_TYPE' do
      expect(mod::MESSAGE_TYPE).to eq('x-bsv-auth-message-type')
    end

    it 'defines SIGNATURE' do
      expect(mod::SIGNATURE).to eq('x-bsv-auth-signature')
    end

    it 'defines REQUESTED_CERTIFICATES' do
      expect(mod::REQUESTED_CERTIFICATES).to eq('x-bsv-auth-requested-certificates')
    end

    it 'defines PAYMENT_VERSION' do
      expect(mod::PAYMENT_VERSION).to eq('x-bsv-payment-version')
    end

    it 'defines PAYMENT_SATOSHIS_REQUIRED' do
      expect(mod::PAYMENT_SATOSHIS_REQUIRED).to eq('x-bsv-payment-satoshis-required')
    end

    it 'defines PAYMENT_DERIVATION_PREFIX' do
      expect(mod::PAYMENT_DERIVATION_PREFIX).to eq('x-bsv-payment-derivation-prefix')
    end

    it 'defines PAYMENT' do
      expect(mod::PAYMENT).to eq('x-bsv-payment')
    end
  end

  describe '.filter_request_headers' do
    it 'includes content-type' do
      result = mod.filter_request_headers('content-type' => 'application/json')
      expect(result).to eq([['content-type', 'application/json']])
    end

    it 'normalises content-type by stripping charset params' do
      result = mod.filter_request_headers('content-type' => 'application/json; charset=utf-8')
      expect(result).to eq([['content-type', 'application/json']])
    end

    it 'normalises content-type stripping all params after semicolon' do
      result = mod.filter_request_headers('Content-Type' => 'text/plain; charset=ISO-8859-1')
      expect(result).to eq([['content-type', 'text/plain']])
    end

    it 'includes authorization' do
      result = mod.filter_request_headers('authorization' => 'Bearer token123')
      expect(result).to eq([['authorization', 'Bearer token123']])
    end

    it 'includes x-bsv-* headers (non-auth)' do
      result = mod.filter_request_headers('x-bsv-custom' => 'val')
      expect(result).to eq([%w[x-bsv-custom val]])
    end

    it 'excludes x-bsv-auth-* headers and raises' do
      expect do
        mod.filter_request_headers('x-bsv-auth-nonce' => 'abc')
      end.to raise_error(ArgumentError, /BSV auth headers are not allowed/)
    end

    it 'raises for unsupported headers' do
      expect do
        mod.filter_request_headers('x-custom-header' => 'value')
      end.to raise_error(ArgumentError, /Unsupported header/)
    end

    it 'raises for accept header' do
      expect do
        mod.filter_request_headers('accept' => 'application/json')
      end.to raise_error(ArgumentError, /Unsupported header/)
    end

    it 'sorts headers alphabetically by key' do
      result = mod.filter_request_headers(
        'content-type' => 'application/json',
        'authorization' => 'Bearer tok',
        'x-bsv-foo' => 'bar'
      )
      keys = result.map { |k, _| k }
      expect(keys).to eq(%w[authorization content-type x-bsv-foo])
    end

    it 'lowercases header keys' do
      result = mod.filter_request_headers('Content-Type' => 'text/html')
      expect(result.first.first).to eq('content-type')
    end

    it 'returns empty array for empty headers' do
      expect(mod.filter_request_headers({})).to eq([])
    end
  end

  describe '.filter_response_headers' do
    it 'includes authorization' do
      result = mod.filter_response_headers('authorization' => 'Bearer tok')
      expect(result).to eq([['authorization', 'Bearer tok']])
    end

    it 'includes x-bsv-* headers (non-auth)' do
      result = mod.filter_response_headers('x-bsv-custom' => 'val')
      expect(result).to eq([%w[x-bsv-custom val]])
    end

    it 'excludes x-bsv-auth-* headers silently' do
      result = mod.filter_response_headers(
        'x-bsv-auth-signature' => 'abc',
        'x-bsv-custom' => 'present'
      )
      expect(result).to eq([%w[x-bsv-custom present]])
    end

    it 'does NOT include content-type in responses' do
      result = mod.filter_response_headers('content-type' => 'application/json')
      expect(result).to eq([])
    end

    it 'does NOT raise for unsupported headers — silently ignores them' do
      result = mod.filter_response_headers('x-some-other' => 'value')
      expect(result).to eq([])
    end

    it 'sorts headers alphabetically by key' do
      result = mod.filter_response_headers(
        'x-bsv-zz' => '2',
        'authorization' => 'tok',
        'x-bsv-aa' => '1'
      )
      keys = result.map { |k, _| k }
      expect(keys).to eq(%w[authorization x-bsv-aa x-bsv-zz])
    end

    it 'returns empty array for empty headers' do
      expect(mod.filter_response_headers({})).to eq([])
    end
  end

  describe '.extract_auth_headers' do
    it 'extracts x-bsv-auth-* headers as symbolised keys' do
      result = mod.extract_auth_headers(
        'x-bsv-auth-version' => '0.1',
        'x-bsv-auth-identity-key' => 'deadbeef'
      )
      expect(result[:version]).to eq('0.1')
      expect(result[:identity_key]).to eq('deadbeef')
    end

    it 'converts hyphenated suffixes to underscored symbols' do
      result = mod.extract_auth_headers('x-bsv-auth-your-nonce' => 'abc')
      expect(result[:your_nonce]).to eq('abc')
    end

    it 'ignores non-auth headers' do
      result = mod.extract_auth_headers(
        'content-type' => 'application/json',
        'x-bsv-custom' => 'v',
        'x-bsv-auth-nonce' => 'n'
      )
      expect(result.keys).to eq([:nonce])
    end

    it 'handles mixed-case input keys' do
      result = mod.extract_auth_headers('X-BSV-Auth-Nonce' => 'xyz')
      expect(result[:nonce]).to eq('xyz')
    end

    it 'returns empty hash when no auth headers present' do
      expect(mod.extract_auth_headers('content-type' => 'text/plain')).to eq({})
    end
  end
end
