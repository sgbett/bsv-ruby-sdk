# frozen_string_literal: true

require_relative 'spec_helper'
require 'rack'
require 'rack/mock'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'BSV::X402 integration: full request/response cycle' do
  # -----------------------------------------------------------------------
  # Shared key material and scripts
  # -----------------------------------------------------------------------

  let(:payee_key)    { BSV::Primitives::PrivateKey.generate }
  let(:nonce_key)    { BSV::Primitives::PrivateKey.generate }
  let(:client_key)   { BSV::Primitives::PrivateKey.generate }
  let(:change_key)   { BSV::Primitives::PrivateKey.generate }

  # Locking scripts (P2PKH).
  let(:payee_script)  { BSV::Script::Script.p2pkh_lock(payee_key.public_key.hash160) }
  let(:nonce_script)  { BSV::Script::Script.p2pkh_lock(nonce_key.public_key.hash160) }
  let(:client_script) { BSV::Script::Script.p2pkh_lock(client_key.public_key.hash160) }
  let(:change_script) { BSV::Script::Script.p2pkh_lock(change_key.public_key.hash160) }

  # -----------------------------------------------------------------------
  # Nonce UTXO — locked to the nonce key, funded enough to pay the fee
  # -----------------------------------------------------------------------

  let(:nonce_utxo) do
    BSV::X402::NonceUTXO.new(
      txid: 'ab' * 32,
      vout: 0,
      satoshis: 10,
      locking_script_hex: nonce_script.to_hex
    )
  end

  # Callable that signs the nonce input with the nonce key.
  let(:nonce_unlocker) do
    p2pkh = BSV::Transaction::P2PKH.new(nonce_key)
    ->(tx, idx) { p2pkh.sign(tx, idx) }
  end

  # -----------------------------------------------------------------------
  # Client funding UTXOs
  # -----------------------------------------------------------------------

  let(:amount_sats) { 200 }

  let(:funding_utxo) do
    {
      txid: 'cd' * 32,
      vout: 0,
      satoshis: 10_000,
      locking_script_hex: client_script.to_hex,
      private_key: client_key
    }
  end

  # -----------------------------------------------------------------------
  # Server configuration
  # -----------------------------------------------------------------------

  let(:nonce_provider) { BSV::X402::StaticNonceProvider.new(nonce_utxo) }

  let(:config) do
    cfg = BSV::X402::Configuration.new
    cfg.payee_locking_script_hex = payee_script.to_hex
    cfg.amount_sats              = amount_sats
    cfg.nonce_provider           = nonce_provider
    cfg.expires_in               = 300
    cfg.bound_headers            = []
    cfg
  end

  # -----------------------------------------------------------------------
  # Inner Rack app — returns 200 with a JSON body
  # -----------------------------------------------------------------------

  let(:inner_app) do
    ->(_env) { [200, { 'content-type' => 'application/json' }, ['{"data":"premium content"}']] }
  end

  # Build a middleware stack with the given DSL block.
  def build_middleware(&block)
    BSV::X402::Middleware.new(inner_app, config: config, &block)
  end

  # -----------------------------------------------------------------------
  # E2E — GET: client → 402 → pay → 200
  # -----------------------------------------------------------------------

  describe 'GET flow: client receives 402, pays, and receives 200' do
    let(:middleware) do
      build_middleware do |x402|
        x402.protect '/api/premium', amount_sats: amount_sats
      end
    end

    it 'completes the full challenge → proof → 200 cycle' do
      # ---- Step 1: initial request (no proof) → 402 ----------------------
      first_env = Rack::MockRequest.env_for(
        'http://example.com/api/premium',
        method: 'GET'
      )
      first_status, first_headers, = middleware.call(first_env)

      expect(first_status).to eq(402)
      expect(first_headers['x402-challenge']).not_to be_nil

      # ---- Step 2: parse the challenge -----------------------------------
      challenge = BSV::X402::Challenge.from_header(first_headers['x402-challenge'])
      expect(challenge.amount_sats).to eq(amount_sats)
      expect(challenge.payee_locking_script_hex).to eq(payee_script.to_hex)

      # ---- Step 3: build the payment transaction via TransactionBuilder --
      tx = BSV::X402::TransactionBuilder.build(
        challenge: challenge,
        funding_utxos: [funding_utxo],
        nonce_unlocker: nonce_unlocker,
        change_locking_script_hex: change_script.to_hex
      )

      # Verify structural properties of the built transaction.
      expect(tx.inputs.first.txid_hex).to eq(nonce_utxo.txid)
      payment_out = tx.outputs.find { |o| o.locking_script.to_hex == payee_script.to_hex }
      expect(payment_out).not_to be_nil
      expect(payment_out.satoshis).to eq(amount_sats)

      # ---- Step 4: build the proof ---------------------------------------
      req_info = {
        method: 'GET',
        path: '/api/premium',
        query: '',
        req_headers_sha256: BSV::X402::RequestBinding.compute_headers_hash({}),
        req_body_sha256: BSV::X402::RequestBinding.compute_body_hash(nil)
      }
      proof = BSV::X402::ProofBuilder.build(
        challenge: challenge,
        transaction: tx,
        request: req_info
      )

      expect(proof.challenge_sha256).to eq(challenge.sha256)

      # ---- Step 5: retry with proof → 200 --------------------------------
      second_env = Rack::MockRequest.env_for(
        'http://example.com/api/premium',
        method: 'GET',
        'HTTP_X402_PROOF' => proof.to_header
      )
      second_status, _second_headers, second_body = middleware.call(second_env)

      expect(second_status).to eq(200)
      expect(second_body.first).to include('premium content')
    end
  end

  # -----------------------------------------------------------------------
  # E2E — POST flow with body binding
  # -----------------------------------------------------------------------

  describe 'POST flow: request body is bound to the challenge' do
    let(:middleware) do
      build_middleware do |x402|
        x402.protect '/api/data'
      end
    end

    let(:post_body) { '{"query":"weather"}' }

    it 'binds the POST body hash and accepts a matching proof' do
      # First request carries a body — the challenge must hash it.
      first_env = Rack::MockRequest.env_for(
        'http://example.com/api/data',
        method: 'POST',
        input: post_body,
        'CONTENT_TYPE' => 'application/json'
      )
      first_status, first_headers, = middleware.call(first_env)
      expect(first_status).to eq(402)

      challenge = BSV::X402::Challenge.from_header(first_headers['x402-challenge'])
      expected_body_sha256 = BSV::X402::RequestBinding.compute_body_hash(post_body)
      expect(challenge.req_body_sha256).to eq(expected_body_sha256)

      # Build the transaction.
      tx = BSV::X402::TransactionBuilder.build(
        challenge: challenge,
        funding_utxos: [funding_utxo],
        nonce_unlocker: nonce_unlocker,
        change_locking_script_hex: change_script.to_hex
      )

      req_info = {
        method: 'POST',
        path: '/api/data',
        query: '',
        req_headers_sha256: BSV::X402::RequestBinding.compute_headers_hash({}),
        req_body_sha256: expected_body_sha256
      }
      proof = BSV::X402::ProofBuilder.build(
        challenge: challenge,
        transaction: tx,
        request: req_info
      )

      # Retry with the proof — body must be rewound in the env for the
      # middleware to re-hash it and compare against the challenge.
      second_env = Rack::MockRequest.env_for(
        'http://example.com/api/data',
        method: 'POST',
        input: post_body,
        'HTTP_X402_PROOF' => proof.to_header
      )
      second_status, = middleware.call(second_env)
      expect(second_status).to eq(200)
    end
  end

  # -----------------------------------------------------------------------
  # E2E — Client auto-pay through middleware (Rack::MockRequest)
  # -----------------------------------------------------------------------

  describe 'Client auto-pay through Rack middleware' do
    let(:middleware) do
      build_middleware do |x402|
        x402.protect '/api/resource'
      end
    end

    # Adapts a Rack middleware into the Client's http_client callable interface.
    # This lets us exercise the Client ↔ Middleware pair without a network.
    def rack_http_client(rack_app)
      lambda do |method, url, headers, body|
        uri    = URI.parse(url)
        opts   = { method: method }
        opts[:input] = body if body

        # Forward headers that the Rack env helper understands.
        rack_headers = headers.transform_keys do |k|
          k =~ /\AHTTP_/i ? k : "HTTP_#{k.upcase.tr('-', '_')}"
        end

        env = Rack::MockRequest.env_for("http://#{uri.host}#{uri.path}", opts.merge(rack_headers))
        status, resp_headers, resp_body_parts = rack_app.call(env)
        resp_body = resp_body_parts.join
        [status, resp_headers, resp_body]
      end
    end

    it 'auto-pays the 402 and returns the 200 response' do
      client = BSV::X402::Client.new(
        funding_utxos: [funding_utxo],
        nonce_unlocker: nonce_unlocker,
        change_locking_script_hex: change_script.to_hex,
        broadcaster: nil,
        http_client: rack_http_client(middleware)
      )

      status, _headers, body = client.get('http://example.com/api/resource')

      expect(status).to eq(200)
      expect(body).to include('premium content')
    end
  end

  # -----------------------------------------------------------------------
  # Multiple protected routes — different prices, unprotected pass-through
  # -----------------------------------------------------------------------

  describe 'multiple routes' do
    let(:middleware) do
      build_middleware do |x402|
        x402.protect '/api/cheap',  amount_sats: 10
        x402.protect '/api/costly', amount_sats: 500
      end
    end

    it 'returns 402 for each protected route' do
      ['/api/cheap', '/api/costly'].each do |path|
        response = Rack::MockRequest.new(middleware).get(path)
        expect(response.status).to eq(402)
      end
    end

    it 'issues a 10-sat challenge for /api/cheap' do
      response  = Rack::MockRequest.new(middleware).get('/api/cheap')
      challenge = BSV::X402::Challenge.from_header(response.headers['x402-challenge'])
      expect(challenge.amount_sats).to eq(10)
    end

    it 'issues a 500-sat challenge for /api/costly' do
      response  = Rack::MockRequest.new(middleware).get('/api/costly')
      challenge = BSV::X402::Challenge.from_header(response.headers['x402-challenge'])
      expect(challenge.amount_sats).to eq(500)
    end

    it 'passes through unprotected routes with 200' do
      response = Rack::MockRequest.new(middleware).get('/public/health')
      expect(response.status).to eq(200)
    end

    it 'accepts a valid proof on /api/cheap and returns 200' do
      mock_req = Rack::MockRequest.new(middleware)

      first_response = mock_req.get('/api/cheap')
      challenge = BSV::X402::Challenge.from_header(first_response.headers['x402-challenge'])

      tx = BSV::X402::TransactionBuilder.build(
        challenge: challenge,
        funding_utxos: [funding_utxo],
        nonce_unlocker: nonce_unlocker,
        change_locking_script_hex: change_script.to_hex
      )

      req_info = {
        method: 'GET', path: '/api/cheap', query: '',
        req_headers_sha256: BSV::X402::RequestBinding.compute_headers_hash({}),
        req_body_sha256: BSV::X402::RequestBinding.compute_body_hash(nil)
      }
      proof = BSV::X402::ProofBuilder.build(challenge: challenge, transaction: tx, request: req_info)

      second_env = Rack::MockRequest.env_for(
        'http://example.com/api/cheap',
        method: 'GET',
        'HTTP_X402_PROOF' => proof.to_header
      )
      status, = middleware.call(second_env)
      expect(status).to eq(200)
    end
  end

  # -----------------------------------------------------------------------
  # on_payment_verified callback fires with correct arguments
  # -----------------------------------------------------------------------

  describe 'on_payment_verified callback' do
    it 'receives the Rack env and a successful VerificationResult' do
      fired_args = []
      config.on_payment_verified = ->(env, result) { fired_args << [env, result] }

      middleware = build_middleware do |x402|
        x402.protect '/api/callback'
      end

      first_env = Rack::MockRequest.env_for('http://example.com/api/callback', method: 'GET')
      _, first_headers, = middleware.call(first_env)
      challenge = BSV::X402::Challenge.from_header(first_headers['x402-challenge'])

      tx = BSV::X402::TransactionBuilder.build(
        challenge: challenge,
        funding_utxos: [funding_utxo],
        nonce_unlocker: nonce_unlocker,
        change_locking_script_hex: change_script.to_hex
      )

      req_info = {
        method: 'GET', path: '/api/callback', query: '',
        req_headers_sha256: BSV::X402::RequestBinding.compute_headers_hash({}),
        req_body_sha256: BSV::X402::RequestBinding.compute_body_hash(nil)
      }
      proof = BSV::X402::ProofBuilder.build(challenge: challenge, transaction: tx, request: req_info)

      second_env = Rack::MockRequest.env_for(
        'http://example.com/api/callback',
        method: 'GET',
        'HTTP_X402_PROOF' => proof.to_header
      )
      middleware.call(second_env)

      expect(fired_args.length).to eq(1)
      _env_arg, result_arg = fired_args.first
      expect(result_arg).to be_a(BSV::X402::VerificationResult)
      expect(result_arg.success?).to be(true)
    end
  end

  # -----------------------------------------------------------------------
  # Error paths
  # -----------------------------------------------------------------------

  describe 'error paths' do
    let(:middleware) do
      build_middleware do |x402|
        x402.protect '/api/pay'
      end
    end

    # Helper: get a fresh challenge from the middleware and store it.
    def obtain_challenge(path = '/api/pay')
      env = Rack::MockRequest.env_for("http://example.com#{path}", method: 'GET')
      _, headers, = middleware.call(env)
      BSV::X402::Challenge.from_header(headers['x402-challenge'])
    end

    # Helper: build a valid payment tx + proof for a challenge.
    def valid_proof_for(challenge, path = '/api/pay')
      tx = BSV::X402::TransactionBuilder.build(
        challenge: challenge,
        funding_utxos: [funding_utxo],
        nonce_unlocker: nonce_unlocker,
        change_locking_script_hex: change_script.to_hex
      )
      req_info = {
        method: 'GET', path: path, query: '',
        req_headers_sha256: BSV::X402::RequestBinding.compute_headers_hash({}),
        req_body_sha256: BSV::X402::RequestBinding.compute_body_hash(nil)
      }
      BSV::X402::ProofBuilder.build(challenge: challenge, transaction: tx, request: req_info)
    end

    context 'when the challenge has expired' do
      it 'returns 402 on the proof retry (step 5: expired challenge)' do
        # Obtain and store a fresh challenge.
        challenge = obtain_challenge

        # Replace the stored challenge with an expired copy.
        # We rebuild with the same sha256 key but an expired timestamp.
        expired = BSV::X402::Challenge.new(
          v: challenge.v,
          scheme: challenge.scheme,
          domain: challenge.domain,
          method: challenge.method,
          path: challenge.path,
          query: challenge.query,
          req_headers_sha256: challenge.req_headers_sha256,
          req_body_sha256: challenge.req_body_sha256,
          amount_sats: challenge.amount_sats,
          payee_locking_script_hex: challenge.payee_locking_script_hex,
          nonce_utxo: challenge.nonce_utxo,
          expires_at: Time.now.to_i - 1,
          require_mempool_accept: challenge.require_mempool_accept
        )
        config.challenge_store.store(expired.sha256, expired)

        # Build the transaction using the expired challenge (it's not expired yet
        # at construction time — we build manually to skip the expiry guard).
        tx = BSV::Transaction::Transaction.new
        tx.add_input(
          BSV::Transaction::TransactionInput.new(
            prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(expired.nonce_utxo.txid),
            prev_tx_out_index: expired.nonce_utxo.vout
          )
        )
        tx.add_output(
          BSV::Transaction::TransactionOutput.new(
            satoshis: expired.amount_sats,
            locking_script: BSV::Script::Script.from_hex(expired.payee_locking_script_hex)
          )
        )

        req_info = {
          method: 'GET', path: '/api/pay', query: '',
          req_headers_sha256: BSV::X402::RequestBinding.compute_headers_hash({}),
          req_body_sha256: BSV::X402::RequestBinding.compute_body_hash(nil)
        }
        proof = BSV::X402::ProofBuilder.build(
          challenge: expired,
          transaction: tx,
          request: req_info
        )

        env = Rack::MockRequest.env_for(
          'http://example.com/api/pay',
          method: 'GET',
          'HTTP_X402_PROOF' => proof.to_header
        )
        status, = middleware.call(env)
        expect(status).to eq(402)
      end
    end

    context 'when the proof uses a tampered transaction (wrong nonce)' do
      it 'returns 402 (step 7: nonce not spent)' do
        challenge = obtain_challenge

        # Build a transaction that does NOT spend the nonce UTXO.
        bad_tx = BSV::Transaction::Transaction.new
        bad_tx.add_input(
          BSV::Transaction::TransactionInput.new(
            prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex('ff' * 32),
            prev_tx_out_index: 0
          )
        )
        bad_tx.add_output(
          BSV::Transaction::TransactionOutput.new(
            satoshis: challenge.amount_sats,
            locking_script: BSV::Script::Script.from_hex(challenge.payee_locking_script_hex)
          )
        )

        req_info = {
          method: 'GET', path: '/api/pay', query: '',
          req_headers_sha256: BSV::X402::RequestBinding.compute_headers_hash({}),
          req_body_sha256: BSV::X402::RequestBinding.compute_body_hash(nil)
        }
        proof = BSV::X402::ProofBuilder.build(
          challenge: challenge,
          transaction: bad_tx,
          request: req_info
        )

        env = Rack::MockRequest.env_for(
          'http://example.com/api/pay',
          method: 'GET',
          'HTTP_X402_PROOF' => proof.to_header
        )
        status, = middleware.call(env)
        expect(status).to eq(402)
      end
    end

    context 'when the payment output is insufficient (wrong amount)' do
      it 'returns 402 (step 8: insufficient payment)' do
        challenge = obtain_challenge

        tx = BSV::Transaction::Transaction.new
        tx.add_input(
          BSV::Transaction::TransactionInput.new(
            prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(challenge.nonce_utxo.txid),
            prev_tx_out_index: challenge.nonce_utxo.vout
          )
        )
        # Underpay by 1 satoshi.
        tx.add_output(
          BSV::Transaction::TransactionOutput.new(
            satoshis: challenge.amount_sats - 1,
            locking_script: BSV::Script::Script.from_hex(challenge.payee_locking_script_hex)
          )
        )

        req_info = {
          method: 'GET', path: '/api/pay', query: '',
          req_headers_sha256: BSV::X402::RequestBinding.compute_headers_hash({}),
          req_body_sha256: BSV::X402::RequestBinding.compute_body_hash(nil)
        }
        proof = BSV::X402::ProofBuilder.build(
          challenge: challenge,
          transaction: tx,
          request: req_info
        )

        env = Rack::MockRequest.env_for(
          'http://example.com/api/pay',
          method: 'GET',
          'HTTP_X402_PROOF' => proof.to_header
        )
        status, = middleware.call(env)
        expect(status).to eq(402)
      end
    end

    context 'when the payment is sent to a wrong payee script' do
      it 'returns 402 (step 8: wrong locking script)' do
        challenge = obtain_challenge
        wrong_key    = BSV::Primitives::PrivateKey.generate
        wrong_script = BSV::Script::Script.p2pkh_lock(wrong_key.public_key.hash160)

        tx = BSV::Transaction::Transaction.new
        tx.add_input(
          BSV::Transaction::TransactionInput.new(
            prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(challenge.nonce_utxo.txid),
            prev_tx_out_index: challenge.nonce_utxo.vout
          )
        )
        tx.add_output(
          BSV::Transaction::TransactionOutput.new(
            satoshis: challenge.amount_sats,
            locking_script: wrong_script
          )
        )

        req_info = {
          method: 'GET', path: '/api/pay', query: '',
          req_headers_sha256: BSV::X402::RequestBinding.compute_headers_hash({}),
          req_body_sha256: BSV::X402::RequestBinding.compute_body_hash(nil)
        }
        proof = BSV::X402::ProofBuilder.build(
          challenge: challenge,
          transaction: tx,
          request: req_info
        )

        env = Rack::MockRequest.env_for(
          'http://example.com/api/pay',
          method: 'GET',
          'HTTP_X402_PROOF' => proof.to_header
        )
        status, = middleware.call(env)
        expect(status).to eq(402)
      end
    end

    context 'when the proof is replayed against a different path' do
      it 'returns 400 (step 4: request binding mismatch)' do
        # Obtain a challenge for /api/pay and build a valid proof for that path.
        challenge = obtain_challenge('/api/pay')
        proof     = valid_proof_for(challenge, '/api/pay')

        # Now submit the /api/pay proof to the /api/pay middleware but with the
        # PATH_INFO pointing to a different path. This exercises step 4 of the
        # verifier: actual request path does not match the challenge path.
        #
        # We register /api/other on the same middleware instance (sharing the
        # challenge store), then send the /api/pay proof to /api/other.
        multi_middleware = BSV::X402::Middleware.new(inner_app, config: config) do |x402|
          x402.protect '/api/pay'
          x402.protect '/api/other'
        end

        # The challenge for /api/pay is already in config.challenge_store.
        # When we send the proof to /api/other, the verifier finds the challenge
        # (same store) and then fails at step 4 because path '/api/other' ≠ '/api/pay'.
        env = Rack::MockRequest.env_for(
          'http://example.com/api/other',
          method: 'GET',
          'HTTP_X402_PROOF' => proof.to_header
        )
        status, = multi_middleware.call(env)
        # Step 4 path mismatch → 400 Bad Request.
        expect(status).to eq(400)
      end
    end

    context 'when the X402-Proof header is malformed base64' do
      it 'returns 400' do
        env = Rack::MockRequest.env_for(
          'http://example.com/api/pay',
          method: 'GET',
          'HTTP_X402_PROOF' => '!!!not-valid-base64!!!'
        )
        status, = middleware.call(env)
        expect(status).to eq(400)
      end
    end

    context 'when the X402-Proof header is valid base64 but invalid JSON' do
      it 'returns 400' do
        garbage = BSV::X402::Encoding.base64url_encode('not json {{{')
        env = Rack::MockRequest.env_for(
          'http://example.com/api/pay',
          method: 'GET',
          'HTTP_X402_PROOF' => garbage
        )
        status, = middleware.call(env)
        expect(status).to eq(400)
      end
    end

    context 'when the proof challenge_sha256 does not match any stored challenge' do
      it 'returns 402 with a fresh challenge' do
        unknown_proof = BSV::X402::Proof.new(
          v: 1,
          scheme: 'bsv-tx-v1',
          challenge_sha256: 'cc' * 32,
          request: {
            'method' => 'GET', 'path' => '/api/pay', 'query' => '',
            'req_headers_sha256' => 'a' * 64,
            'req_body_sha256' => 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
          },
          payment: {
            'txid' => 'ff' * 32,
            'rawtx_b64' => BSV::X402::Encoding.base64_encode("\x00" * 10)
          }
        )

        env = Rack::MockRequest.env_for(
          'http://example.com/api/pay',
          method: 'GET',
          'HTTP_X402_PROOF' => unknown_proof.to_header
        )
        status, headers, = middleware.call(env)
        expect(status).to eq(402)
        # A fresh challenge must be issued.
        expect(headers['x402-challenge']).not_to be_nil
      end
    end

    context 'when the nonce provider is exhausted' do
      it 'returns 500' do
        exhausted_provider = Object.new
        def exhausted_provider.reserve_nonce
          raise BSV::X402::ValidationError, 'nonce pool exhausted'
        end

        config.nonce_provider = exhausted_provider
        response = Rack::MockRequest.new(middleware).get('/api/pay')
        expect(response.status).to eq(500)
      end
    end
  end

  # -----------------------------------------------------------------------
  # Verifier step-level HTTP status mapping (spec §9)
  # -----------------------------------------------------------------------

  describe 'HTTP status codes for each verification failure step' do
    let(:middleware) do
      build_middleware do |x402|
        x402.protect '/api/pay'
      end
    end

    # Steps 1, 2, 4, 6 → 400; steps 3, 5, 7, 8, 9 → 402.

    it 'returns 400 for a structurally invalid proof (step 1/2 via malformed base64)' do
      env = Rack::MockRequest.env_for(
        'http://example.com/api/pay',
        method: 'GET',
        'HTTP_X402_PROOF' => '!!!bad!!!'
      )
      status, = middleware.call(env)
      expect(status).to eq(400)
    end

    it 'returns 402 for an unknown challenge_sha256 (triggers fresh challenge — step 3)' do
      unknown_proof = BSV::X402::Proof.new(
        v: 1,
        scheme: 'bsv-tx-v1',
        challenge_sha256: 'bb' * 32,
        request: {
          'method' => 'GET', 'path' => '/api/pay', 'query' => '',
          'req_headers_sha256' => 'a' * 64,
          'req_body_sha256' => 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
        },
        payment: {
          'txid' => 'aa' * 32,
          'rawtx_b64' => BSV::X402::Encoding.base64_encode("\x00" * 10)
        }
      )
      env = Rack::MockRequest.env_for(
        'http://example.com/api/pay',
        method: 'GET',
        'HTTP_X402_PROOF' => unknown_proof.to_header
      )
      status, = middleware.call(env)
      expect(status).to eq(402)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
