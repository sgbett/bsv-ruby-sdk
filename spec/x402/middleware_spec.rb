# frozen_string_literal: true

require_relative 'spec_helper'
require 'rack'
require 'rack/mock'

RSpec.describe BSV::X402::Middleware do
  # ------------------------------------------------------------------
  # Fixtures
  # ------------------------------------------------------------------

  let(:nonce_utxo) do
    BSV::X402::NonceUTXO.new(
      txid: 'ee' * 32,
      vout: 0,
      satoshis: 1,
      locking_script_hex: "76a914#{'22' * 20}88ac"
    )
  end

  let(:nonce_provider) { BSV::X402::StaticNonceProvider.new(nonce_utxo) }
  let(:payee_script_hex) { "76a914#{'33' * 20}88ac" }
  let(:amount_sats) { 100 }

  let(:config) do
    cfg = BSV::X402::Configuration.new
    cfg.payee_locking_script_hex = payee_script_hex
    cfg.amount_sats              = amount_sats
    cfg.nonce_provider           = nonce_provider
    cfg.expires_in               = 300
    cfg.bound_headers            = []
    cfg
  end

  # Inner app always returns 200 OK.
  let(:inner_app) { ->(_env) { [200, { 'content-type' => 'text/plain' }, ['OK']] } }

  # Build a Rack::MockRequest for the middleware under test.
  def build_middleware(&block)
    BSV::X402::Middleware.new(inner_app, config: config, &block)
  end

  def get(middleware, path, headers = {})
    Rack::MockRequest.new(middleware).get(path, headers)
  end

  # ------------------------------------------------------------------
  # Unprotected routes
  # ------------------------------------------------------------------

  describe 'unprotected routes' do
    let(:middleware) do
      build_middleware do |x402|
        x402.protect '/api/premium'
      end
    end

    it 'passes through a request to an unprotected path' do
      response = get(middleware, '/public')
      expect(response.status).to eq(200)
      expect(response.body).to eq('OK')
    end

    it 'does not set X402-Challenge header for unprotected paths' do
      response = get(middleware, '/public')
      expect(response.headers['x402-challenge']).to be_nil
    end
  end

  # ------------------------------------------------------------------
  # Protected route without proof → 402
  # ------------------------------------------------------------------

  describe 'protected route without proof' do
    let(:middleware) do
      build_middleware do |x402|
        x402.protect '/api/premium'
      end
    end

    it 'returns 402 when no X402-Proof header is present' do
      response = get(middleware, '/api/premium')
      expect(response.status).to eq(402)
    end

    it 'includes the X402-Challenge header in the 402 response' do
      response = get(middleware, '/api/premium')
      expect(response.headers['x402-challenge']).not_to be_nil
    end

    it 'sets a valid base64url-encoded challenge in the header' do
      response = get(middleware, '/api/premium')
      header   = response.headers['x402-challenge']
      challenge = BSV::X402::Challenge.from_header(header)
      expect(challenge).to be_a(BSV::X402::Challenge)
    end

    it 'returns exactly one X402-Challenge header' do
      response = get(middleware, '/api/premium')
      # Rack headers are strings; confirm header is a single value
      expect(response.headers['x402-challenge']).to be_a(String)
    end

    it 'binds the challenge to the correct method and path' do
      response  = get(middleware, '/api/premium')
      challenge = BSV::X402::Challenge.from_header(response.headers['x402-challenge'])
      expect(challenge.method).to eq('GET')
      expect(challenge.path).to eq('/api/premium')
    end

    it 'binds the challenge to the correct query string' do
      response  = Rack::MockRequest.new(middleware).get('/api/premium?foo=bar')
      challenge = BSV::X402::Challenge.from_header(response.headers['x402-challenge'])
      expect(challenge.query).to eq('foo=bar')
    end

    it 'uses the global config amount_sats' do
      response  = get(middleware, '/api/premium')
      challenge = BSV::X402::Challenge.from_header(response.headers['x402-challenge'])
      expect(challenge.amount_sats).to eq(amount_sats)
    end

    it 'returns a JSON body with error information' do
      response = get(middleware, '/api/premium')
      body     = JSON.parse(response.body)
      expect(body['error']).to eq('Payment Required')
      expect(body['amount_sats']).to eq(amount_sats)
    end

    it 'calls nonce_provider.reserve_nonce exactly once' do
      mock_provider = instance_spy(BSV::X402::StaticNonceProvider)
      allow(mock_provider).to receive(:reserve_nonce).and_return(nonce_utxo)
      config.nonce_provider = mock_provider

      middleware = build_middleware do |x402|
        x402.protect '/api/premium'
      end

      get(middleware, '/api/premium')

      expect(mock_provider).to have_received(:reserve_nonce).once
    end
  end

  # ------------------------------------------------------------------
  # Per-route amount_sats override
  # ------------------------------------------------------------------

  describe 'per-route amount_sats override' do
    let(:middleware) do
      build_middleware do |x402|
        x402.protect '/api/cheap', amount_sats: 10
        x402.protect '/api/expensive', amount_sats: 999
      end
    end

    it 'uses the per-route amount for the cheap route' do
      response  = get(middleware, '/api/cheap')
      challenge = BSV::X402::Challenge.from_header(response.headers['x402-challenge'])
      expect(challenge.amount_sats).to eq(10)
    end

    it 'uses the per-route amount for the expensive route' do
      response  = get(middleware, '/api/expensive')
      challenge = BSV::X402::Challenge.from_header(response.headers['x402-challenge'])
      expect(challenge.amount_sats).to eq(999)
    end
  end

  # ------------------------------------------------------------------
  # Glob matching
  # ------------------------------------------------------------------

  describe 'glob route matching' do
    let(:middleware) do
      build_middleware do |x402|
        x402.protect '/api/v1/*'
      end
    end

    it 'protects a path matching the glob' do
      response = get(middleware, '/api/v1/resource')
      expect(response.status).to eq(402)
    end

    it 'protects another matching path' do
      response = get(middleware, '/api/v1/data')
      expect(response.status).to eq(402)
    end

    it 'does not protect a path outside the glob' do
      response = get(middleware, '/api/v2/resource')
      expect(response.status).to eq(200)
    end

    it 'does not protect the parent path of the glob pattern' do
      response = get(middleware, '/api/v1')
      expect(response.status).to eq(200)
    end
  end

  # ------------------------------------------------------------------
  # Multiple routes — first-match-wins
  # ------------------------------------------------------------------

  describe 'multiple routes — first match wins' do
    let(:middleware) do
      build_middleware do |x402|
        x402.protect '/api/v1/data', amount_sats: 50
        x402.protect '/api/v1/*',    amount_sats: 200
      end
    end

    it 'uses the first matching route (exact over glob)' do
      response  = get(middleware, '/api/v1/data')
      challenge = BSV::X402::Challenge.from_header(response.headers['x402-challenge'])
      expect(challenge.amount_sats).to eq(50)
    end

    it 'uses the second route for non-exact matches' do
      response  = get(middleware, '/api/v1/other')
      challenge = BSV::X402::Challenge.from_header(response.headers['x402-challenge'])
      expect(challenge.amount_sats).to eq(200)
    end
  end

  # ------------------------------------------------------------------
  # Proc-based protection
  # ------------------------------------------------------------------

  describe 'proc-based protection' do
    let(:protect_proc) { ->(env) { env['PATH_INFO'].start_with?('/paid/') } }

    let(:middleware) do
      described_class.new(inner_app, config: config, protect: protect_proc)
    end

    it 'protects paths matching the proc' do
      response = get(middleware, '/paid/resource')
      expect(response.status).to eq(402)
    end

    it 'passes through paths not matching the proc' do
      response = get(middleware, '/free/resource')
      expect(response.status).to eq(200)
    end

    it 'uses the global config amount_sats (no per-route override with proc)' do
      response  = get(middleware, '/paid/resource')
      challenge = BSV::X402::Challenge.from_header(response.headers['x402-challenge'])
      expect(challenge.amount_sats).to eq(amount_sats)
    end
  end

  # ------------------------------------------------------------------
  # Protected route with valid proof → passes through
  # ------------------------------------------------------------------

  describe 'protected route with valid proof' do
    let(:middleware) do
      build_middleware do |x402|
        x402.protect '/api/pay'
      end
    end

    # Simulate the full two-request flow:
    # 1. GET /api/pay (no proof) → 402 + challenge stored in challenge_store
    # 2. Build a valid transaction spending the nonce from the challenge
    # 3. Build a proof referencing the stored challenge's SHA-256
    # 4. GET /api/pay with X402-Proof header → 200

    def build_valid_proof_for(path, app)
      # First request — server stores the challenge and returns 402.
      first_env      = Rack::MockRequest.env_for("http://example.com#{path}", method: 'GET')
      first_response = Rack::MockResponse.new(*app.call(first_env))
      challenge      = BSV::X402::Challenge.from_header(first_response.headers['x402-challenge'])

      # Build a valid transaction spending the nonce UTXO from the challenge.
      t = BSV::Transaction::Transaction.new
      t.add_input(
        BSV::Transaction::TransactionInput.new(
          prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(challenge.nonce_utxo.txid),
          prev_tx_out_index: challenge.nonce_utxo.vout
        )
      )
      t.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: challenge.amount_sats,
          locking_script: BSV::Script::Script.from_binary([challenge.payee_locking_script_hex].pack('H*'))
        )
      )

      headers_sha256 = BSV::X402::RequestBinding.compute_headers_hash({})
      body_sha256    = BSV::X402::RequestBinding.compute_body_hash(nil)

      BSV::X402::Proof.new(
        v: 1,
        scheme: 'bsv-tx-v1',
        challenge_sha256: challenge.sha256,
        request: {
          'method' => challenge.method,
          'path' => challenge.path,
          'query' => challenge.query,
          'req_headers_sha256' => headers_sha256,
          'req_body_sha256' => body_sha256
        },
        payment: {
          'txid' => t.txid_hex,
          'rawtx_b64' => BSV::X402::Encoding.base64_encode(t.to_binary)
        }
      )
    end

    it 'passes through to the inner app when the proof is valid' do
      proof = build_valid_proof_for('/api/pay', middleware)

      env = Rack::MockRequest.env_for(
        'http://example.com/api/pay',
        method: 'GET',
        'HTTP_X402_PROOF' => proof.to_header
      )

      status, _headers, body = middleware.call(env)
      expect(status).to eq(200)
      expect(body.first).to eq('OK')
    end
  end

  # ------------------------------------------------------------------
  # Protected route with invalid proof → 400 or 402
  # ------------------------------------------------------------------

  describe 'protected route with invalid proof' do
    let(:middleware) do
      build_middleware do |x402|
        x402.protect '/api/pay'
      end
    end

    context 'when the X402-Proof header is malformed base64' do
      it 'returns 400' do
        env = Rack::MockRequest.env_for(
          'http://example.com/api/pay',
          method: 'GET',
          'HTTP_X402_PROOF' => '!!!not-valid-base64!!!'
        )

        status, _headers, _body = middleware.call(env)
        expect(status).to eq(400)
      end
    end

    context 'when the X402-Proof header is valid base64 but not valid JSON' do
      it 'returns 400' do
        garbage = BSV::X402::Encoding.base64url_encode('this is not json {{{')
        env = Rack::MockRequest.env_for(
          'http://example.com/api/pay',
          method: 'GET',
          'HTTP_X402_PROOF' => garbage
        )

        status, _headers, _body = middleware.call(env)
        expect(status).to eq(400)
      end
    end

    context 'when the proof has wrong challenge_sha256 (challenge mismatch)' do
      it 'returns 402 (step 3 failure)' do
        bad_proof = BSV::X402::Proof.new(
          v: 1,
          scheme: 'bsv-tx-v1',
          challenge_sha256: 'ff' * 32,
          request: {
            'method' => 'GET', 'path' => '/api/pay', 'query' => '',
            'req_headers_sha256' => 'a' * 64,
            'req_body_sha256' => 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
          },
          payment: { 'txid' => 'aa' * 32, 'rawtx_b64' => BSV::X402::Encoding.base64_encode("\x00" * 10) }
        )

        env = Rack::MockRequest.env_for(
          'http://example.com/api/pay',
          method: 'GET',
          'HTTP_X402_PROOF' => bad_proof.to_header
        )

        status, _headers, _body = middleware.call(env)
        expect(status).to eq(402)
      end
    end
  end

  # ------------------------------------------------------------------
  # on_payment_verified callback
  # ------------------------------------------------------------------

  describe 'on_payment_verified callback' do
    it 'fires the callback after successful verification' do
      fired        = false
      fired_env    = nil
      fired_result = nil

      callback = lambda do |env, result|
        fired        = true
        fired_env    = env
        fired_result = result
      end

      config.on_payment_verified = callback

      middleware = build_middleware do |x402|
        x402.protect '/api/callback'
      end

      # First request to obtain and store the challenge.
      first_env  = Rack::MockRequest.env_for('http://example.com/api/callback', method: 'GET')
      first_resp = Rack::MockResponse.new(*middleware.call(first_env))
      challenge  = BSV::X402::Challenge.from_header(first_resp.headers['x402-challenge'])

      # Build a valid transaction.
      t = BSV::Transaction::Transaction.new
      t.add_input(
        BSV::Transaction::TransactionInput.new(
          prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(challenge.nonce_utxo.txid),
          prev_tx_out_index: challenge.nonce_utxo.vout
        )
      )
      t.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: challenge.amount_sats,
          locking_script: BSV::Script::Script.from_binary([challenge.payee_locking_script_hex].pack('H*'))
        )
      )

      headers_sha256 = BSV::X402::RequestBinding.compute_headers_hash({})
      body_sha256    = BSV::X402::RequestBinding.compute_body_hash(nil)

      proof = BSV::X402::Proof.new(
        v: 1,
        scheme: 'bsv-tx-v1',
        challenge_sha256: challenge.sha256,
        request: {
          'method' => 'GET', 'path' => '/api/callback', 'query' => '',
          'req_headers_sha256' => headers_sha256,
          'req_body_sha256' => body_sha256
        },
        payment: {
          'txid' => t.txid_hex,
          'rawtx_b64' => BSV::X402::Encoding.base64_encode(t.to_binary)
        }
      )

      env = Rack::MockRequest.env_for(
        'http://example.com/api/callback',
        method: 'GET',
        'HTTP_X402_PROOF' => proof.to_header
      )

      middleware.call(env)

      expect(fired).to be(true)
      expect(fired_env).to be(env)
      expect(fired_result).to be_a(BSV::X402::VerificationResult)
      expect(fired_result.success?).to be(true)
    end

    it 'does not fire the callback when verification fails' do
      fired = false
      config.on_payment_verified = ->(_env, _result) { fired = true }

      middleware = build_middleware do |x402|
        x402.protect '/api/callback'
      end

      # No proof — returns 402 challenge, callback must not fire.
      get(middleware, '/api/callback')
      expect(fired).to be(false)
    end
  end

  # ------------------------------------------------------------------
  # Body hash in challenge
  # ------------------------------------------------------------------

  describe 'body hash in POST challenge' do
    let(:middleware) do
      build_middleware do |x402|
        x402.protect '/api/post'
      end
    end

    it 'hashes the POST body and embeds it in the challenge' do
      body_content = 'payload data'
      env = Rack::MockRequest.env_for(
        'http://example.com/api/post',
        method: 'POST',
        input: body_content
      )

      status, headers, = middleware.call(env)
      expect(status).to eq(402)

      challenge = BSV::X402::Challenge.from_header(headers['x402-challenge'])
      expected_hash = OpenSSL::Digest::SHA256.hexdigest(body_content)
      expect(challenge.req_body_sha256).to eq(expected_hash)
    end

    it 'produces the empty-string SHA-256 for a body-less GET' do
      response  = get(middleware, '/api/post')
      challenge = BSV::X402::Challenge.from_header(response.headers['x402-challenge'])
      empty_sha256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
      expect(challenge.req_body_sha256).to eq(empty_sha256)
    end
  end
end
