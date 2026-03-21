# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'BSV::X402::Verifier' do
  # -------------------------------------------------------------------
  # Shared fixtures
  # -------------------------------------------------------------------

  # Nonce UTXO used in challenge and consumed by the test transaction.
  let(:nonce_txid)    { 'aabbccdd' * 8 }
  let(:nonce_vout)    { 0 }
  let(:nonce_sats)    { 1 }
  let(:nonce_script)  { "76a914#{'aa' * 20}88ac" }

  let(:nonce_utxo) do
    BSV::X402::NonceUTXO.new(
      txid: nonce_txid,
      vout: nonce_vout,
      satoshis: nonce_sats,
      locking_script_hex: nonce_script
    )
  end

  # Payee locking script hex.
  let(:payee_script_hex) { "76a914#{'11' * 20}88ac" }

  # Required payment amount.
  let(:amount_sats) { 500 }

  # A future expiry timestamp — challenge is not expired by default.
  let(:expires_at)  { Time.now.to_i + 3600 }

  # Challenge bound to a specific HTTP request.
  let(:challenge) do
    BSV::X402::Challenge.new(
      v: 1,
      scheme: 'bsv-tx-v1',
      domain: 'example.com',
      method: 'GET',
      path: '/api/resource',
      query: 'page=1',
      req_headers_sha256: 'a' * 64,
      req_body_sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      amount_sats: amount_sats,
      payee_locking_script_hex: payee_script_hex,
      nonce_utxo: nonce_utxo,
      expires_at: expires_at,
      require_mempool_accept: false
    )
  end

  # Build a valid BSV transaction:
  #   - input spending the nonce UTXO
  #   - output paying the required amount to the payee script
  let(:tx) do
    t = BSV::Transaction::Transaction.new
    t.add_input(
      BSV::Transaction::TransactionInput.new(
        prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(nonce_txid),
        prev_tx_out_index: nonce_vout
      )
    )
    t.add_output(
      BSV::Transaction::TransactionOutput.new(
        satoshis: amount_sats,
        locking_script: BSV::Script::Script.from_binary([payee_script_hex].pack('H*'))
      )
    )
    t
  end

  let(:raw_tx_bytes) { tx.to_binary }
  let(:txid_hex)     { tx.txid_hex }
  let(:rawtx_b64)    { BSV::X402::Encoding.base64_encode(raw_tx_bytes) }

  # A valid proof that references the challenge and the test transaction.
  let(:proof) do
    BSV::X402::Proof.new(
      v: 1,
      scheme: 'bsv-tx-v1',
      challenge_sha256: challenge.sha256,
      request: {
        'method' => 'GET',
        'path' => '/api/resource',
        'query' => 'page=1',
        'req_headers_sha256' => 'a' * 64,
        'req_body_sha256' => 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
      },
      payment: {
        'txid' => txid_hex,
        'rawtx_b64' => rawtx_b64
      }
    )
  end

  # The actual inbound HTTP request info supplied to the verifier.
  let(:request) do
    {
      method: 'GET',
      path: '/api/resource',
      query: 'page=1',
      headers_sha256: 'a' * 64,
      body_sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    }
  end

  # Helper: run the verifier with the current let bindings.
  def verify(**overrides)
    BSV::X402::Verifier.verify(
      challenge: overrides.fetch(:challenge, challenge),
      proof: overrides.fetch(:proof, proof),
      request: overrides.fetch(:request, request),
      settlement_verifier: overrides.fetch(:settlement_verifier, nil)
    )
  end

  # -------------------------------------------------------------------
  # Happy path
  # -------------------------------------------------------------------

  describe 'happy path' do
    it 'returns success when all steps pass' do
      result = verify
      expect(result.success?).to be(true)
      expect(result.step).to be_nil
      expect(result.reason).to be_nil
    end

    it 'returns a VerificationResult' do
      expect(verify).to be_a(BSV::X402::VerificationResult)
    end
  end

  # -------------------------------------------------------------------
  # Step 1: proof structure
  # -------------------------------------------------------------------

  describe 'step 1 — proof structure' do
    it 'fails with step 1 and status 400 when proof is nil' do
      result = verify(proof: nil)
      expect(result.failure?).to be(true)
      expect(result.step).to eq(1)
      expect(result.http_status).to eq(400)
    end
  end

  # -------------------------------------------------------------------
  # Step 2: version and scheme
  # -------------------------------------------------------------------

  describe 'step 2 — version and scheme' do
    # Proof.new validates v and scheme, so valid Proof objects always satisfy
    # step 2. We use a simple duck-typed double to test the verifier's
    # defence-in-depth guard independently of the Proof constructor.

    def proof_double(v:, scheme:)
      dbl = instance_double(BSV::X402::Proof)
      allow(dbl).to receive_messages(v: v, scheme: scheme, challenge_sha256: challenge.sha256, request: proof.request, payment: proof.payment, decoded_tx: raw_tx_bytes, valid_txid?: true)
      dbl
    end

    it 'fails with step 2 and status 400 when proof.v is wrong' do
      bad_proof = proof_double(v: 99, scheme: 'bsv-tx-v1')

      result = verify(proof: bad_proof)
      expect(result.step).to eq(2)
      expect(result.http_status).to eq(400)
      expect(result.reason).to match(/v must be 1/)
    end

    it 'fails with step 2 and status 400 when proof.scheme is wrong' do
      bad_proof = proof_double(v: 1, scheme: 'other-scheme')

      result = verify(proof: bad_proof)
      expect(result.step).to eq(2)
      expect(result.http_status).to eq(400)
    end
  end

  # -------------------------------------------------------------------
  # Step 3: challenge SHA-256
  # -------------------------------------------------------------------

  describe 'step 3 — challenge_sha256' do
    it 'fails with step 3 and status 402 when challenge_sha256 does not match' do
      bad_proof = BSV::X402::Proof.new(
        v: 1, scheme: 'bsv-tx-v1',
        challenge_sha256: 'ff' * 32,
        request: proof.request, payment: proof.payment
      )

      result = verify(proof: bad_proof)
      expect(result.step).to eq(3)
      expect(result.http_status).to eq(402)
    end

    it 'fails when the challenge itself is different (tampered field)' do
      tampered_challenge = BSV::X402::Challenge.new(
        v: 1, scheme: 'bsv-tx-v1', domain: 'other.com',
        method: 'GET', path: '/api/resource', query: 'page=1',
        req_headers_sha256: 'a' * 64,
        req_body_sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        amount_sats: amount_sats,
        payee_locking_script_hex: payee_script_hex,
        nonce_utxo: nonce_utxo,
        expires_at: expires_at,
        require_mempool_accept: false
      )
      # proof.challenge_sha256 was computed from the original challenge, not the tampered one
      result = verify(challenge: tampered_challenge)
      expect(result.step).to eq(3)
    end
  end

  # -------------------------------------------------------------------
  # Step 4: request binding
  # -------------------------------------------------------------------

  describe 'step 4 — request binding' do
    context 'when proof.request.method does not match challenge' do
      it 'fails with step 4 and status 400' do
        bad_proof = BSV::X402::Proof.new(
          v: 1, scheme: 'bsv-tx-v1',
          challenge_sha256: challenge.sha256,
          request: proof.request.merge('method' => 'POST'),
          payment: proof.payment
        )
        result = verify(proof: bad_proof)
        expect(result.step).to eq(4)
        expect(result.http_status).to eq(400)
      end
    end

    context 'when actual request method does not match challenge' do
      it 'fails with step 4 and status 400' do
        bad_request = request.merge(method: 'POST')
        result = verify(request: bad_request)
        expect(result.step).to eq(4)
        expect(result.http_status).to eq(400)
      end
    end

    context 'when proof.request.path does not match challenge' do
      it 'fails with step 4 and status 400' do
        bad_proof = BSV::X402::Proof.new(
          v: 1, scheme: 'bsv-tx-v1',
          challenge_sha256: challenge.sha256,
          request: proof.request.merge('path' => '/other/path'),
          payment: proof.payment
        )
        result = verify(proof: bad_proof)
        expect(result.step).to eq(4)
      end
    end

    context 'when actual request path does not match challenge' do
      it 'fails with step 4 and status 400' do
        bad_request = request.merge(path: '/different')
        result = verify(request: bad_request)
        expect(result.step).to eq(4)
      end
    end

    context 'when proof.request.query does not match challenge' do
      it 'fails with step 4 and status 400' do
        bad_proof = BSV::X402::Proof.new(
          v: 1, scheme: 'bsv-tx-v1',
          challenge_sha256: challenge.sha256,
          request: proof.request.merge('query' => 'page=99'),
          payment: proof.payment
        )
        result = verify(proof: bad_proof)
        expect(result.step).to eq(4)
      end
    end

    context 'when actual request query does not match challenge' do
      it 'fails with step 4 and status 400' do
        bad_request = request.merge(query: 'page=99')
        result = verify(request: bad_request)
        expect(result.step).to eq(4)
      end
    end

    context 'when proof.request.req_headers_sha256 does not match challenge' do
      it 'fails with step 4 and status 400' do
        bad_proof = BSV::X402::Proof.new(
          v: 1, scheme: 'bsv-tx-v1',
          challenge_sha256: challenge.sha256,
          request: proof.request.merge('req_headers_sha256' => 'b' * 64),
          payment: proof.payment
        )
        result = verify(proof: bad_proof)
        expect(result.step).to eq(4)
      end
    end

    context 'when actual request headers hash does not match challenge' do
      it 'fails with step 4 and status 400' do
        bad_request = request.merge(headers_sha256: 'c' * 64)
        result = verify(request: bad_request)
        expect(result.step).to eq(4)
      end
    end

    context 'when proof.request.req_body_sha256 does not match challenge' do
      it 'fails with step 4 and status 400' do
        bad_proof = BSV::X402::Proof.new(
          v: 1, scheme: 'bsv-tx-v1',
          challenge_sha256: challenge.sha256,
          request: proof.request.merge('req_body_sha256' => 'd' * 64),
          payment: proof.payment
        )
        result = verify(proof: bad_proof)
        expect(result.step).to eq(4)
      end
    end

    context 'when actual request body hash does not match challenge' do
      it 'fails with step 4 and status 400' do
        bad_request = request.merge(body_sha256: 'd' * 64)
        result = verify(request: bad_request)
        expect(result.step).to eq(4)
      end
    end
  end

  # -------------------------------------------------------------------
  # Step 5: expiry
  # -------------------------------------------------------------------

  describe 'step 5 — expiry' do
    it 'fails with step 5 and status 402 when challenge has expired' do
      expired_challenge = BSV::X402::Challenge.new(
        v: 1, scheme: 'bsv-tx-v1', domain: 'example.com',
        method: 'GET', path: '/api/resource', query: 'page=1',
        req_headers_sha256: 'a' * 64,
        req_body_sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        amount_sats: amount_sats,
        payee_locking_script_hex: payee_script_hex,
        nonce_utxo: nonce_utxo,
        expires_at: Time.now.to_i - 1,
        require_mempool_accept: false
      )
      # Recompute proof with the expired challenge's sha256
      expired_proof = BSV::X402::Proof.new(
        v: 1, scheme: 'bsv-tx-v1',
        challenge_sha256: expired_challenge.sha256,
        request: proof.request, payment: proof.payment
      )

      result = BSV::X402::Verifier.verify(
        challenge: expired_challenge,
        proof: expired_proof,
        request: request
      )
      expect(result.step).to eq(5)
      expect(result.http_status).to eq(402)
    end

    it 'passes when expires_at equals current time (boundary — not yet expired)' do
      now = Time.now.to_i
      boundary_challenge = BSV::X402::Challenge.new(
        v: 1, scheme: 'bsv-tx-v1', domain: 'example.com',
        method: 'GET', path: '/api/resource', query: 'page=1',
        req_headers_sha256: 'a' * 64,
        req_body_sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        amount_sats: amount_sats,
        payee_locking_script_hex: payee_script_hex,
        nonce_utxo: nonce_utxo,
        expires_at: now,
        require_mempool_accept: false
      )
      boundary_proof = BSV::X402::Proof.new(
        v: 1, scheme: 'bsv-tx-v1',
        challenge_sha256: boundary_challenge.sha256,
        request: proof.request, payment: proof.payment
      )

      result = BSV::X402::Verifier.verify(
        challenge: boundary_challenge,
        proof: boundary_proof,
        request: request
      )
      # expired? returns true only when now > expires_at, so == is not expired
      expect(result.step).not_to eq(5)
    end
  end

  # -------------------------------------------------------------------
  # Step 6: transaction decode and txid verification
  # -------------------------------------------------------------------

  describe 'step 6 — transaction decode and txid' do
    it 'fails with step 6 and status 400 when rawtx_b64 is malformed' do
      bad_proof = BSV::X402::Proof.new(
        v: 1, scheme: 'bsv-tx-v1',
        challenge_sha256: challenge.sha256,
        request: proof.request,
        payment: { 'txid' => txid_hex, 'rawtx_b64' => 'not-valid-base64!!!' }
      )

      result = verify(proof: bad_proof)
      expect(result.step).to eq(6)
      expect(result.http_status).to eq(400)
    end

    it 'fails with step 6 and status 400 when rawtx_b64 is valid base64 but not a valid transaction' do
      # Base64 of 5 zero bytes — too short to be a valid transaction
      bad_tx_b64 = BSV::X402::Encoding.base64_encode("\x00" * 5)
      bad_proof = BSV::X402::Proof.new(
        v: 1, scheme: 'bsv-tx-v1',
        challenge_sha256: challenge.sha256,
        request: proof.request,
        payment: { 'txid' => txid_hex, 'rawtx_b64' => bad_tx_b64 }
      )

      result = verify(proof: bad_proof)
      expect(result.step).to eq(6)
      expect(result.http_status).to eq(400)
    end

    it 'fails with step 6 and status 400 when txid does not match the decoded transaction' do
      wrong_txid_proof = BSV::X402::Proof.new(
        v: 1, scheme: 'bsv-tx-v1',
        challenge_sha256: challenge.sha256,
        request: proof.request,
        payment: { 'txid' => 'ff' * 32, 'rawtx_b64' => rawtx_b64 }
      )

      result = verify(proof: wrong_txid_proof)
      expect(result.step).to eq(6)
      expect(result.http_status).to eq(400)
    end
  end

  # -------------------------------------------------------------------
  # Step 7: nonce UTXO is spent
  # -------------------------------------------------------------------

  describe 'step 7 — nonce UTXO spend' do
    it 'fails with step 7 and status 402 when no input spends the nonce UTXO' do
      # Build a transaction spending a different outpoint
      other_tx = BSV::Transaction::Transaction.new
      other_tx.add_input(
        BSV::Transaction::TransactionInput.new(
          prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex('00' * 32),
          prev_tx_out_index: 0
        )
      )
      other_tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: amount_sats,
          locking_script: BSV::Script::Script.from_binary([payee_script_hex].pack('H*'))
        )
      )
      other_raw = other_tx.to_binary
      other_proof = BSV::X402::Proof.new(
        v: 1, scheme: 'bsv-tx-v1',
        challenge_sha256: challenge.sha256,
        request: proof.request,
        payment: {
          'txid' => other_tx.txid_hex,
          'rawtx_b64' => BSV::X402::Encoding.base64_encode(other_raw)
        }
      )

      result = verify(proof: other_proof)
      expect(result.step).to eq(7)
      expect(result.http_status).to eq(402)
    end

    it 'fails when input txid matches but vout is different' do
      other_tx = BSV::Transaction::Transaction.new
      # Same txid, wrong vout
      other_tx.add_input(
        BSV::Transaction::TransactionInput.new(
          prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(nonce_txid),
          prev_tx_out_index: nonce_vout + 1
        )
      )
      other_tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: amount_sats,
          locking_script: BSV::Script::Script.from_binary([payee_script_hex].pack('H*'))
        )
      )
      other_raw = other_tx.to_binary
      other_proof = BSV::X402::Proof.new(
        v: 1, scheme: 'bsv-tx-v1',
        challenge_sha256: challenge.sha256,
        request: proof.request,
        payment: {
          'txid' => other_tx.txid_hex,
          'rawtx_b64' => BSV::X402::Encoding.base64_encode(other_raw)
        }
      )

      result = verify(proof: other_proof)
      expect(result.step).to eq(7)
    end

    it 'passes when nonce input is not at index 0 (any position acceptable)' do
      multi_input_tx = BSV::Transaction::Transaction.new
      # First input: some other spend
      multi_input_tx.add_input(
        BSV::Transaction::TransactionInput.new(
          prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex('cc' * 32),
          prev_tx_out_index: 0
        )
      )
      # Second input: nonce UTXO
      multi_input_tx.add_input(
        BSV::Transaction::TransactionInput.new(
          prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(nonce_txid),
          prev_tx_out_index: nonce_vout
        )
      )
      multi_input_tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: amount_sats,
          locking_script: BSV::Script::Script.from_binary([payee_script_hex].pack('H*'))
        )
      )
      multi_raw = multi_input_tx.to_binary
      multi_proof = BSV::X402::Proof.new(
        v: 1, scheme: 'bsv-tx-v1',
        challenge_sha256: challenge.sha256,
        request: proof.request,
        payment: {
          'txid' => multi_input_tx.txid_hex,
          'rawtx_b64' => BSV::X402::Encoding.base64_encode(multi_raw)
        }
      )

      result = verify(proof: multi_proof)
      expect(result.success?).to be(true)
    end
  end

  # -------------------------------------------------------------------
  # Step 8: payment output
  # -------------------------------------------------------------------

  describe 'step 8 — payment output' do
    it 'fails with step 8 and status 402 when no output matches the payee script' do
      wrong_script_hex = "76a914#{'99' * 20}88ac"
      wrong_tx = BSV::Transaction::Transaction.new
      wrong_tx.add_input(
        BSV::Transaction::TransactionInput.new(
          prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(nonce_txid),
          prev_tx_out_index: nonce_vout
        )
      )
      wrong_tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: amount_sats,
          locking_script: BSV::Script::Script.from_binary([wrong_script_hex].pack('H*'))
        )
      )
      wrong_raw = wrong_tx.to_binary
      wrong_proof = BSV::X402::Proof.new(
        v: 1, scheme: 'bsv-tx-v1',
        challenge_sha256: challenge.sha256,
        request: proof.request,
        payment: {
          'txid' => wrong_tx.txid_hex,
          'rawtx_b64' => BSV::X402::Encoding.base64_encode(wrong_raw)
        }
      )

      result = verify(proof: wrong_proof)
      expect(result.step).to eq(8)
      expect(result.http_status).to eq(402)
    end

    it 'fails with step 8 and status 402 when output has correct script but insufficient satoshis' do
      low_tx = BSV::Transaction::Transaction.new
      low_tx.add_input(
        BSV::Transaction::TransactionInput.new(
          prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(nonce_txid),
          prev_tx_out_index: nonce_vout
        )
      )
      low_tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: amount_sats - 1,
          locking_script: BSV::Script::Script.from_binary([payee_script_hex].pack('H*'))
        )
      )
      low_raw = low_tx.to_binary
      low_proof = BSV::X402::Proof.new(
        v: 1, scheme: 'bsv-tx-v1',
        challenge_sha256: challenge.sha256,
        request: proof.request,
        payment: {
          'txid' => low_tx.txid_hex,
          'rawtx_b64' => BSV::X402::Encoding.base64_encode(low_raw)
        }
      )

      result = verify(proof: low_proof)
      expect(result.step).to eq(8)
      expect(result.reason).to match(/satoshis/)
    end

    it 'fails when one output has correct script (too low sats) and another has enough sats (wrong script)' do
      # Neither single output satisfies both requirements.
      split_tx = BSV::Transaction::Transaction.new
      split_tx.add_input(
        BSV::Transaction::TransactionInput.new(
          prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(nonce_txid),
          prev_tx_out_index: nonce_vout
        )
      )
      # Output 0: correct script, insufficient amount
      split_tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: amount_sats - 1,
          locking_script: BSV::Script::Script.from_binary([payee_script_hex].pack('H*'))
        )
      )
      # Output 1: wrong script, sufficient amount
      split_tx.add_output(
        BSV::Transaction::TransactionOutput.new(
          satoshis: amount_sats,
          locking_script: BSV::Script::Script.from_binary(["76a914#{'99' * 20}88ac"].pack('H*'))
        )
      )
      split_raw = split_tx.to_binary
      split_proof = BSV::X402::Proof.new(
        v: 1, scheme: 'bsv-tx-v1',
        challenge_sha256: challenge.sha256,
        request: proof.request,
        payment: {
          'txid' => split_tx.txid_hex,
          'rawtx_b64' => BSV::X402::Encoding.base64_encode(split_raw)
        }
      )

      result = verify(proof: split_proof)
      expect(result.step).to eq(8)
    end

    it 'passes when a single output satisfies both script and amount' do
      result = verify
      expect(result.success?).to be(true)
    end

    it 'passes when satoshis exactly equal amount_sats (boundary)' do
      # The default tx already has exactly amount_sats — just confirm explicitly
      expect(tx.outputs[0].satoshis).to eq(amount_sats)
      expect(verify.success?).to be(true)
    end
  end

  # -------------------------------------------------------------------
  # Step 9: mempool acceptance
  # -------------------------------------------------------------------

  describe 'step 9 — mempool acceptance' do
    let(:mempool_challenge) do
      BSV::X402::Challenge.new(
        v: 1, scheme: 'bsv-tx-v1', domain: 'example.com',
        method: 'GET', path: '/api/resource', query: 'page=1',
        req_headers_sha256: 'a' * 64,
        req_body_sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        amount_sats: amount_sats,
        payee_locking_script_hex: payee_script_hex,
        nonce_utxo: nonce_utxo,
        expires_at: expires_at,
        require_mempool_accept: true
      )
    end

    let(:mempool_proof) do
      BSV::X402::Proof.new(
        v: 1, scheme: 'bsv-tx-v1',
        challenge_sha256: mempool_challenge.sha256,
        request: proof.request, payment: proof.payment
      )
    end

    it 'skips step 9 when require_mempool_accept is false' do
      called = false
      settlement_verifier = lambda { |_raw|
        called = true
        true
      }

      result = verify(settlement_verifier: settlement_verifier)
      expect(result.success?).to be(true)
      expect(called).to be(false)
    end

    it 'skips step 9 when no settlement_verifier is provided even if require_mempool_accept is true' do
      result = BSV::X402::Verifier.verify(
        challenge: mempool_challenge,
        proof: mempool_proof,
        request: request,
        settlement_verifier: nil
      )
      expect(result.success?).to be(true)
    end

    it 'passes when settlement_verifier returns true' do
      settlement_verifier = ->(_raw) { true }

      result = BSV::X402::Verifier.verify(
        challenge: mempool_challenge,
        proof: mempool_proof,
        request: request,
        settlement_verifier: settlement_verifier
      )
      expect(result.success?).to be(true)
    end

    it 'fails with step 9 and status 402 when settlement_verifier returns false' do
      settlement_verifier = ->(_raw) { false }

      result = BSV::X402::Verifier.verify(
        challenge: mempool_challenge,
        proof: mempool_proof,
        request: request,
        settlement_verifier: settlement_verifier
      )
      expect(result.step).to eq(9)
      expect(result.http_status).to eq(402)
    end

    it 'passes the raw transaction bytes to the settlement_verifier' do
      received = nil
      settlement_verifier = lambda do |raw|
        received = raw
        true
      end

      BSV::X402::Verifier.verify(
        challenge: mempool_challenge,
        proof: mempool_proof,
        request: request,
        settlement_verifier: settlement_verifier
      )

      expect(received).to eq(raw_tx_bytes)
    end
  end

  # -------------------------------------------------------------------
  # Step ordering invariant (V-1)
  # -------------------------------------------------------------------

  describe 'step ordering — invariant V-1' do
    it 'fails at step 3 (challenge hash), not step 4 (binding), when both would fail' do
      # Build a proof with wrong challenge_sha256 AND mismatched method.
      bad_proof = BSV::X402::Proof.new(
        v: 1, scheme: 'bsv-tx-v1',
        challenge_sha256: 'ff' * 32,
        request: proof.request.merge('method' => 'POST'),
        payment: proof.payment
      )
      result = verify(proof: bad_proof)
      expect(result.step).to eq(3)
    end

    it 'fails at step 4 (binding), not step 5 (expiry), when both would fail' do
      expired_challenge = BSV::X402::Challenge.new(
        v: 1, scheme: 'bsv-tx-v1', domain: 'example.com',
        method: 'GET', path: '/api/resource', query: 'page=1',
        req_headers_sha256: 'a' * 64,
        req_body_sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        amount_sats: amount_sats,
        payee_locking_script_hex: payee_script_hex,
        nonce_utxo: nonce_utxo,
        expires_at: Time.now.to_i - 1,
        require_mempool_accept: false
      )
      expired_proof = BSV::X402::Proof.new(
        v: 1, scheme: 'bsv-tx-v1',
        challenge_sha256: expired_challenge.sha256,
        # mismatched path will fail step 4
        request: proof.request.merge('path' => '/wrong'),
        payment: proof.payment
      )
      bad_request = request.merge(path: '/wrong')

      result = BSV::X402::Verifier.verify(
        challenge: expired_challenge,
        proof: expired_proof,
        request: bad_request
      )
      expect(result.step).to eq(4)
    end

    it 'fails at step 1 immediately, not at a later step, when proof is nil' do
      result = verify(proof: nil)
      expect(result.step).to eq(1)
    end
  end

  # -------------------------------------------------------------------
  # Request hash with string keys
  # -------------------------------------------------------------------

  describe 'string-keyed request hash' do
    it 'accepts a string-keyed request hash' do
      string_request = {
        'method' => 'GET',
        'path' => '/api/resource',
        'query' => 'page=1',
        'headers_sha256' => 'a' * 64,
        'body_sha256' => 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
      }
      result = verify(request: string_request)
      expect(result.success?).to be(true)
    end
  end
end
