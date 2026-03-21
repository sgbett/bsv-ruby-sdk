# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'BSV::X402::ProofBuilder' do
  # -------------------------------------------------------------------
  # Shared fixtures
  # -------------------------------------------------------------------

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

  let(:payee_script_hex) { "76a914#{'11' * 20}88ac" }
  let(:amount_sats)      { 300 }
  let(:expires_at)       { Time.now.to_i + 3600 }

  let(:challenge) do
    BSV::X402::Challenge.new(
      v: 1,
      scheme: 'bsv-tx-v1',
      domain: 'example.com',
      method: 'GET',
      path: '/pay',
      query: 'ref=test',
      req_headers_sha256: 'b' * 64,
      req_body_sha256: 'c' * 64,
      amount_sats: amount_sats,
      payee_locking_script_hex: payee_script_hex,
      nonce_utxo: nonce_utxo,
      expires_at: expires_at,
      require_mempool_accept: false
    )
  end

  # A minimal transaction with one nonce input and one payment output.
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

  let(:request) do
    {
      method: 'GET',
      path: '/pay',
      query: 'ref=test',
      req_headers_sha256: 'b' * 64,
      req_body_sha256: 'c' * 64
    }
  end

  # Helper: build a proof with optional overrides.
  def build_proof(**overrides)
    BSV::X402::ProofBuilder.build(
      challenge: overrides.fetch(:challenge, challenge),
      transaction: overrides.fetch(:transaction, tx),
      request: overrides.fetch(:request, request)
    )
  end

  # -------------------------------------------------------------------
  # Happy path
  # -------------------------------------------------------------------

  it 'returns a Proof instance' do
    expect(build_proof).to be_a(BSV::X402::Proof)
  end

  it 'sets v to 1' do
    expect(build_proof.v).to eq(1)
  end

  it "sets scheme to 'bsv-tx-v1'" do
    expect(build_proof.scheme).to eq('bsv-tx-v1')
  end

  describe 'challenge_sha256' do
    it "matches the challenge's own sha256" do
      proof = build_proof
      expect(proof.challenge_sha256).to eq(challenge.sha256)
    end

    it 'changes when a different challenge is used' do
      other_challenge = BSV::X402::Challenge.new(
        v: 1,
        scheme: 'bsv-tx-v1',
        domain: 'other.com',
        method: 'POST',
        path: '/other',
        query: '',
        req_headers_sha256: 'd' * 64,
        req_body_sha256: 'e' * 64,
        amount_sats: 100,
        payee_locking_script_hex: payee_script_hex,
        nonce_utxo: nonce_utxo,
        expires_at: expires_at,
        require_mempool_accept: false
      )

      proof1 = build_proof
      proof2 = build_proof(challenge: other_challenge)
      expect(proof1.challenge_sha256).not_to eq(proof2.challenge_sha256)
    end
  end

  describe 'payment sub-object' do
    it "sets txid to the transaction's txid_hex" do
      proof = build_proof
      expect(proof.payment['txid']).to eq(tx.txid_hex)
    end

    it 'sets rawtx_b64 to standard base64 of the raw transaction bytes' do
      proof = build_proof
      expected = BSV::X402::Encoding.base64_encode(tx.to_binary)
      expect(proof.payment['rawtx_b64']).to eq(expected)
    end

    it 'encodes rawtx_b64 with standard base64 (not base64url)' do
      proof = build_proof
      # Standard base64 uses '+' and '/', not '-' and '_'.
      # We verify the decoded bytes round-trip correctly.
      decoded = Base64.strict_decode64(proof.payment['rawtx_b64'])
      expect(decoded).to eq(tx.to_binary)
    end

    it 'passes valid_txid? check on the resulting proof' do
      proof = build_proof
      expect(proof.valid_txid?).to be(true)
    end
  end

  describe 'request sub-object' do
    it 'propagates method from the request hash' do
      proof = build_proof
      expect(proof.request['method']).to eq('GET')
    end

    it 'propagates path from the request hash' do
      proof = build_proof
      expect(proof.request['path']).to eq('/pay')
    end

    it 'propagates query from the request hash' do
      proof = build_proof
      expect(proof.request['query']).to eq('ref=test')
    end

    it 'propagates req_headers_sha256 from the request hash' do
      proof = build_proof
      expect(proof.request['req_headers_sha256']).to eq('b' * 64)
    end

    it 'propagates req_body_sha256 from the request hash' do
      proof = build_proof
      expect(proof.request['req_body_sha256']).to eq('c' * 64)
    end

    it 'accepts string-keyed request hashes' do
      string_request = {
        'method' => 'GET',
        'path' => '/pay',
        'query' => 'ref=test',
        'req_headers_sha256' => 'b' * 64,
        'req_body_sha256' => 'c' * 64
      }
      proof = build_proof(request: string_request)
      expect(proof.request['method']).to eq('GET')
    end
  end

  describe 'round-trip via header' do
    it 'can be encoded to a header and decoded back' do
      proof = build_proof
      header_value = proof.to_header
      decoded = BSV::X402::Proof.from_header(header_value)

      expect(decoded.challenge_sha256).to eq(proof.challenge_sha256)
      expect(decoded.payment['txid']).to eq(proof.payment['txid'])
    end
  end
end
