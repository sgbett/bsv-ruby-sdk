# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'BSV::X402::Client' do
  # -------------------------------------------------------------------
  # Shared fixtures
  # -------------------------------------------------------------------

  # Nonce UTXO — locked to a throwaway key.
  let(:nonce_key)    { BSV::Primitives::PrivateKey.generate }
  let(:nonce_script) { BSV::Script::Script.p2pkh_lock(nonce_key.public_key.hash160) }

  let(:nonce_utxo) do
    BSV::X402::NonceUTXO.new(
      txid: 'aa' * 32,
      vout: 0,
      satoshis: 1,
      locking_script_hex: nonce_script.to_hex
    )
  end

  # Payee script — a simple P2PKH.
  let(:payee_key)        { BSV::Primitives::PrivateKey.generate }
  let(:payee_script_hex) { BSV::Script::Script.p2pkh_lock(payee_key.public_key.hash160).to_hex }
  let(:amount_sats)      { 200 }

  # Funding UTXO — has enough to cover the payment plus fee.
  let(:funding_key)  { BSV::Primitives::PrivateKey.generate }
  let(:funding_lock) { BSV::Script::Script.p2pkh_lock(funding_key.public_key.hash160) }
  let(:funding_utxo) do
    {
      txid: 'bb' * 32,
      vout: 0,
      satoshis: 10_000,
      locking_script_hex: funding_lock.to_hex,
      private_key: funding_key
    }
  end

  # Change script.
  let(:change_key)        { BSV::Primitives::PrivateKey.generate }
  let(:change_script_hex) { BSV::Script::Script.p2pkh_lock(change_key.public_key.hash160).to_hex }

  # Nonce unlocker: signs with the nonce key.
  let(:nonce_unlocker) do
    p2pkh = BSV::Transaction::P2PKH.new(nonce_key)
    ->(tx, idx) { p2pkh.sign(tx, idx) }
  end

  # A valid challenge.
  let(:challenge) do
    BSV::X402::Challenge.new(
      v: 1,
      scheme: 'bsv-tx-v1',
      domain: 'example.com',
      method: 'GET',
      path: '/resource',
      query: '',
      req_headers_sha256: BSV::X402::RequestBinding.compute_headers_hash({}),
      req_body_sha256: BSV::X402::RequestBinding.compute_body_hash(nil),
      amount_sats: amount_sats,
      payee_locking_script_hex: payee_script_hex,
      nonce_utxo: nonce_utxo,
      expires_at: Time.now.to_i + 3600,
      require_mempool_accept: false
    )
  end

  let(:challenge_header) { challenge.to_header }

  # HTTP client double: returns [200, {}, 'ok'] by default.
  let(:http_responses) { [[200, {}, 'ok']] }
  let(:http_calls) { [] }
  let(:http_client) do
    responses = http_responses.dup
    lambda do |method, url, headers, body|
      http_calls << { method: method, url: url, headers: headers, body: body }
      responses.shift || [200, {}, 'ok']
    end
  end

  # The client under test.
  let(:client) do
    BSV::X402::Client.new(
      funding_utxos: [funding_utxo],
      nonce_unlocker: nonce_unlocker,
      change_locking_script_hex: change_script_hex,
      broadcaster: nil,
      http_client: http_client
    )
  end

  # -------------------------------------------------------------------
  # Pass-through behaviour
  # -------------------------------------------------------------------

  describe 'non-402 response' do
    it 'returns the response unchanged for a 200' do
      status, _headers, body = client.request('GET', 'http://example.com/resource')
      expect(status).to eq(200)
      expect(body).to eq('ok')
    end

    it 'returns the response unchanged for a 404' do
      let_http_responses [[404, {}, 'not found']]
      status, _headers, body = client.request('GET', 'http://example.com/missing')
      expect(status).to eq(404)
      expect(body).to eq('not found')
    end

    it 'makes exactly one HTTP call for a non-402 response' do
      client.request('GET', 'http://example.com/resource')
      expect(http_calls.length).to eq(1)
    end
  end

  # -------------------------------------------------------------------
  # 402 payment flow
  # -------------------------------------------------------------------

  describe '402 auto-pay flow' do
    let(:http_responses) do
      [
        [402, { 'x402-challenge' => challenge_header }, ''],
        [200, {}, 'paid content']
      ]
    end

    it 'retries the request after building a proof' do
      client.request('GET', 'http://example.com/resource')
      expect(http_calls.length).to eq(2)
    end

    it 'includes the X402-Proof header on the retry request' do
      client.request('GET', 'http://example.com/resource')
      retry_headers = http_calls[1][:headers]
      expect(retry_headers.key?('X402-Proof')).to be(true)
    end

    it 'returns the final response after successful payment' do
      status, _headers, body = client.request('GET', 'http://example.com/resource')
      expect(status).to eq(200)
      expect(body).to eq('paid content')
    end

    it 'sends the same method and URL on retry' do
      client.request('GET', 'http://example.com/resource')
      expect(http_calls[1][:method]).to eq('GET')
      expect(http_calls[1][:url]).to eq('http://example.com/resource')
    end

    it 'encodes a valid proof in the X402-Proof header' do
      client.request('GET', 'http://example.com/resource')
      proof_header = http_calls[1][:headers]['X402-Proof']
      proof = BSV::X402::Proof.from_header(proof_header)
      expect(proof.challenge_sha256).to eq(challenge.sha256)
    end
  end

  # -------------------------------------------------------------------
  # Broadcaster integration
  # -------------------------------------------------------------------

  describe 'broadcaster' do
    let(:broadcaster) { double('broadcaster') } # rubocop:disable RSpec/VerifiedDoubles

    let(:http_responses) do
      [
        [402, { 'x402-challenge' => challenge_header }, ''],
        [200, {}, 'paid']
      ]
    end

    let(:client_with_broadcaster) do
      BSV::X402::Client.new(
        funding_utxos: [funding_utxo],
        nonce_unlocker: nonce_unlocker,
        change_locking_script_hex: change_script_hex,
        broadcaster: broadcaster,
        http_client: http_client
      )
    end

    it 'calls broadcast on the broadcaster when configured' do
      allow(broadcaster).to receive(:broadcast)
      client_with_broadcaster.request('GET', 'http://example.com/resource')
      expect(broadcaster).to have_received(:broadcast).once
    end

    it 'passes a Transaction to the broadcaster' do
      received_tx = nil
      allow(broadcaster).to receive(:broadcast) { |tx| received_tx = tx }
      client_with_broadcaster.request('GET', 'http://example.com/resource')
      expect(received_tx).to be_a(BSV::Transaction::Transaction)
    end

    it 'does not call broadcast when no broadcaster is configured' do
      # client has broadcaster: nil — just verify no error is raised.
      expect do
        client.request('GET', 'http://example.com/resource')
      end.not_to raise_error
    end
  end

  # -------------------------------------------------------------------
  # auto_pay: false
  # -------------------------------------------------------------------

  describe 'auto_pay: false' do
    let(:http_responses) do
      [[402, { 'x402-challenge' => challenge_header }, '']]
    end

    let(:client_no_autopay) do
      BSV::X402::Client.new(
        funding_utxos: [funding_utxo],
        nonce_unlocker: nonce_unlocker,
        http_client: http_client,
        auto_pay: false
      )
    end

    it 'returns the 402 response without auto-paying' do
      status, _headers, _body = client_no_autopay.request('GET', 'http://example.com/resource')
      expect(status).to eq(402)
    end

    it 'makes only one HTTP call' do
      client_no_autopay.request('GET', 'http://example.com/resource')
      expect(http_calls.length).to eq(1)
    end
  end

  # -------------------------------------------------------------------
  # max_retries
  # -------------------------------------------------------------------

  describe 'max_retries' do
    # Server always returns 402.
    let(:http_responses) do
      Array.new(10, [402, { 'x402-challenge' => challenge_header }, ''])
    end

    let(:client_with_retries) do
      BSV::X402::Client.new(
        funding_utxos: [funding_utxo],
        nonce_unlocker: nonce_unlocker,
        http_client: http_client,
        max_retries: 2
      )
    end

    it 'raises PaymentRetryExhaustedError when max_retries is exceeded' do
      expect do
        client_with_retries.request('GET', 'http://example.com/resource')
      end.to raise_error(BSV::X402::PaymentRetryExhaustedError)
    end
  end

  # -------------------------------------------------------------------
  # POST with body
  # -------------------------------------------------------------------

  describe 'POST request with body' do
    let(:post_body) { '{"amount":42}' }

    let(:post_challenge) do
      body_hash = BSV::X402::RequestBinding.compute_body_hash(post_body)
      BSV::X402::Challenge.new(
        v: 1,
        scheme: 'bsv-tx-v1',
        domain: 'example.com',
        method: 'POST',
        path: '/pay',
        query: '',
        req_headers_sha256: BSV::X402::RequestBinding.compute_headers_hash({}),
        req_body_sha256: body_hash,
        amount_sats: amount_sats,
        payee_locking_script_hex: payee_script_hex,
        nonce_utxo: nonce_utxo,
        expires_at: Time.now.to_i + 3600,
        require_mempool_accept: false
      )
    end

    let(:http_responses) do
      [
        [402, { 'x402-challenge' => post_challenge.to_header }, ''],
        [200, {}, 'post paid']
      ]
    end

    it 'includes the body hash in the proof request binding' do
      client.post('http://example.com/pay', body: post_body)
      proof = BSV::X402::Proof.from_header(http_calls[1][:headers]['X402-Proof'])
      expected_hash = BSV::X402::RequestBinding.compute_body_hash(post_body)
      expect(proof.request['req_body_sha256']).to eq(expected_hash)
    end
  end

  # -------------------------------------------------------------------
  # Convenience methods
  # -------------------------------------------------------------------

  describe '#get' do
    it 'delegates to #request with GET method' do
      client.get('http://example.com/resource')
      expect(http_calls.first[:method]).to eq('GET')
    end
  end

  describe '#post' do
    let(:http_responses) { [[200, {}, 'ok']] }

    it 'delegates to #request with POST method' do
      client.post('http://example.com/resource', body: 'data')
      expect(http_calls.first[:method]).to eq('POST')
    end

    it 'forwards the body to the HTTP client' do
      client.post('http://example.com/resource', body: 'payload')
      expect(http_calls.first[:body]).to eq('payload')
    end
  end

  # -------------------------------------------------------------------
  # Error cases
  # -------------------------------------------------------------------

  describe 'insufficient funds' do
    let(:poor_utxo) do
      {
        txid: 'cc' * 32,
        vout: 0,
        satoshis: 1,
        locking_script_hex: funding_lock.to_hex,
        private_key: funding_key
      }
    end

    let(:http_responses) do
      [[402, { 'x402-challenge' => challenge_header }, '']]
    end

    let(:poor_client) do
      BSV::X402::Client.new(
        funding_utxos: [poor_utxo],
        nonce_unlocker: nonce_unlocker,
        http_client: http_client
      )
    end

    it 'raises InsufficientFundsError when UTXOs cannot cover the payment' do
      expect do
        poor_client.request('GET', 'http://example.com/resource')
      end.to raise_error(BSV::X402::InsufficientFundsError)
    end
  end

  describe 'missing X402-Challenge header' do
    let(:http_responses) { [[402, {}, '']] }

    it 'raises ValidationError when X402-Challenge header is absent' do
      expect do
        client.request('GET', 'http://example.com/resource')
      end.to raise_error(BSV::X402::ValidationError, /X402-Challenge/)
    end
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  # Mutates http_responses for tests that need a different first response.
  def let_http_responses(responses)
    http_responses.replace(responses)
  end
end
