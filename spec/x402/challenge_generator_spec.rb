# frozen_string_literal: true

require_relative 'spec_helper'
require 'rack'

RSpec.describe BSV::X402::ChallengeGenerator do
  let(:nonce_utxo) do
    BSV::X402::NonceUTXO.new(
      txid: 'cc' * 32,
      vout: 0,
      satoshis: 1,
      locking_script_hex: "76a914#{'bb' * 20}88ac"
    )
  end

  let(:nonce_provider) { BSV::X402::StaticNonceProvider.new(nonce_utxo) }

  let(:payee_script_hex) { "76a914#{'11' * 20}88ac" }

  let(:config) do
    cfg = BSV::X402::Configuration.new
    cfg.payee_locking_script_hex = payee_script_hex
    cfg.amount_sats              = 200
    cfg.nonce_provider           = nonce_provider
    cfg.expires_in               = 300
    cfg.bound_headers            = []
    cfg
  end

  def rack_env(method: 'GET', path: '/api/data', query: '', host: 'example.com', body: '')
    Rack::MockRequest.env_for(
      "http://#{host}#{path}#{"?#{query}" unless query.empty?}",
      method: method,
      input: body
    )
  end

  describe '.generate' do
    context 'with a simple GET request' do
      it 'returns a Challenge' do
        env = rack_env
        challenge = described_class.generate(env: env, config: config)
        expect(challenge).to be_a(BSV::X402::Challenge)
      end

      it 'sets method from REQUEST_METHOD' do
        env = rack_env(method: 'GET')
        challenge = described_class.generate(env: env, config: config)
        expect(challenge.method).to eq('GET')
      end

      it 'sets path from PATH_INFO' do
        env = rack_env(path: '/api/premium')
        challenge = described_class.generate(env: env, config: config)
        expect(challenge.path).to eq('/api/premium')
      end

      it 'sets query from QUERY_STRING' do
        env = rack_env(query: 'page=2&sort=asc')
        challenge = described_class.generate(env: env, config: config)
        expect(challenge.query).to eq('page=2&sort=asc')
      end

      it 'sets domain from HTTP_HOST' do
        env = rack_env(host: 'payments.example.com')
        challenge = described_class.generate(env: env, config: config)
        expect(challenge.domain).to eq('payments.example.com')
      end

      it 'sets nonce_utxo from the provider' do
        env = rack_env
        challenge = described_class.generate(env: env, config: config)
        expect(challenge.nonce_utxo).to eq(nonce_utxo)
      end

      it 'sets amount_sats from config' do
        env = rack_env
        challenge = described_class.generate(env: env, config: config)
        expect(challenge.amount_sats).to eq(200)
      end

      it 'sets payee_locking_script_hex from config' do
        env = rack_env
        challenge = described_class.generate(env: env, config: config)
        expect(challenge.payee_locking_script_hex).to eq(payee_script_hex)
      end

      it 'sets scheme to bsv-tx-v1' do
        env = rack_env
        challenge = described_class.generate(env: env, config: config)
        expect(challenge.scheme).to eq('bsv-tx-v1')
      end

      it 'sets expires_at to approximately now + expires_in' do
        env = rack_env
        before = Time.now.to_i
        challenge = described_class.generate(env: env, config: config)
        after = Time.now.to_i

        expect(challenge.expires_at).to be_between(before + 300, after + 300)
      end
    end

    context 'with a POST request and body' do
      it 'computes the body SHA-256 hash correctly' do
        body = 'hello world'
        env  = rack_env(method: 'POST', path: '/api/pay', body: body)
        challenge = described_class.generate(env: env, config: config)

        expected = OpenSSL::Digest::SHA256.hexdigest(body)
        expect(challenge.req_body_sha256).to eq(expected)
      end

      it 'sets method to POST' do
        env = rack_env(method: 'POST', body: 'data')
        challenge = described_class.generate(env: env, config: config)
        expect(challenge.method).to eq('POST')
      end
    end

    context 'with an empty body' do
      it 'produces the SHA-256 of the empty string' do
        env = rack_env
        challenge = described_class.generate(env: env, config: config)
        empty_sha256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
        expect(challenge.req_body_sha256).to eq(empty_sha256)
      end
    end

    context 'with a nil QUERY_STRING' do
      it 'treats the query as an empty string' do
        env = rack_env
        env.delete('QUERY_STRING')
        challenge = described_class.generate(env: env, config: config)
        expect(challenge.query).to eq('')
      end
    end

    context 'with bound headers' do
      it 'includes only the configured headers in the hash' do
        config.bound_headers = ['content-type']
        env = rack_env
        env['HTTP_CONTENT_TYPE'] = 'application/json'
        env['HTTP_X_CUSTOM']     = 'should-be-ignored'

        challenge_with = described_class.generate(env: env, config: config)

        config_no_headers = BSV::X402::Configuration.new
        config_no_headers.payee_locking_script_hex = payee_script_hex
        config_no_headers.nonce_provider           = nonce_provider
        config_no_headers.bound_headers            = []
        challenge_without = described_class.generate(env: env, config: config_no_headers)

        # The hashes must differ because content-type is included in one but not the other.
        expect(challenge_with.req_headers_sha256).not_to eq(challenge_without.req_headers_sha256)
      end

      it 'produces a deterministic hash for the same headers' do
        config.bound_headers = ['content-type']
        env1 = rack_env
        env1['HTTP_CONTENT_TYPE'] = 'application/json'
        env2 = rack_env
        env2['HTTP_CONTENT_TYPE'] = 'application/json'

        c1 = described_class.generate(env: env1, config: config)
        c2 = described_class.generate(env: env2, config: config)
        expect(c1.req_headers_sha256).to eq(c2.req_headers_sha256)
      end
    end

    context 'with per-route amount_sats override' do
      it 'uses the route option instead of the config default' do
        env = rack_env
        challenge = described_class.generate(env: env, config: config, route_options: { amount_sats: 999 })
        expect(challenge.amount_sats).to eq(999)
      end
    end

    context 'when nonce_provider is nil' do
      it 'raises ValidationError' do
        config.nonce_provider = nil
        env = rack_env
        expect { described_class.generate(env: env, config: config) }
          .to raise_error(BSV::X402::ValidationError, /nonce_provider/)
      end
    end

    context 'when nonce_provider returns a hash' do
      it 'wraps the hash in a NonceUTXO' do
        hash_provider = instance_double(BSV::X402::StaticNonceProvider)
        allow(hash_provider).to receive(:reserve_nonce).and_return(
          'txid' => 'dd' * 32, 'vout' => 2, 'satoshis' => 10,
          'locking_script_hex' => "76a914#{'cc' * 20}88ac"
        )
        config.nonce_provider = hash_provider

        env = rack_env
        challenge = described_class.generate(env: env, config: config)
        expect(challenge.nonce_utxo).to be_a(BSV::X402::NonceUTXO)
        expect(challenge.nonce_utxo.txid).to eq('dd' * 32)
      end
    end

    context 'when nonce_provider returns a NonceUTXO directly' do
      it 'uses it as-is without double-wrapping' do
        env       = rack_env
        challenge = described_class.generate(env: env, config: config)
        expect(challenge.nonce_utxo).to be_a(BSV::X402::NonceUTXO)
      end
    end

    context 'when verifying reserve_nonce call count' do
      it 'calls reserve_nonce exactly once per generate call' do
        provider = instance_spy(BSV::X402::StaticNonceProvider)
        allow(provider).to receive(:reserve_nonce).and_return(nonce_utxo)
        config.nonce_provider = provider

        env = rack_env
        described_class.generate(env: env, config: config)

        expect(provider).to have_received(:reserve_nonce).once
      end
    end
  end
end
