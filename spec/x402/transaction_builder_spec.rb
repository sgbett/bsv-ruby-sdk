# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'BSV::X402::TransactionBuilder' do
  # -------------------------------------------------------------------
  # Shared fixtures
  # -------------------------------------------------------------------

  # Keys generated once per example group for speed.
  let(:nonce_key)   { BSV::Primitives::PrivateKey.generate }
  let(:funding_key) { BSV::Primitives::PrivateKey.generate }

  # Nonce UTXO — P2PKH-locked to the nonce key.
  let(:nonce_locking_script) { BSV::Script::Script.p2pkh_lock(nonce_key.public_key.hash160) }
  let(:nonce_txid)           { 'aa' * 32 }
  let(:nonce_vout)           { 0 }
  let(:nonce_sats)           { 10 }

  let(:nonce_utxo) do
    BSV::X402::NonceUTXO.new(
      txid: nonce_txid,
      vout: nonce_vout,
      satoshis: nonce_sats,
      locking_script_hex: nonce_locking_script.to_hex
    )
  end

  # Payee script — a simple P2PKH.
  let(:payee_key)        { BSV::Primitives::PrivateKey.generate }
  let(:payee_script_hex) { BSV::Script::Script.p2pkh_lock(payee_key.public_key.hash160).to_hex }
  let(:amount_sats)      { 500 }

  # Funding UTXO — P2PKH-locked to the funding key.
  let(:funding_locking_script) { BSV::Script::Script.p2pkh_lock(funding_key.public_key.hash160) }
  let(:funding_utxo) do
    {
      txid: 'bb' * 32,
      vout: 0,
      satoshis: 10_000,
      locking_script_hex: funding_locking_script.to_hex,
      private_key: funding_key
    }
  end

  # Change script.
  let(:change_key)        { BSV::Primitives::PrivateKey.generate }
  let(:change_script_hex) { BSV::Script::Script.p2pkh_lock(change_key.public_key.hash160).to_hex }

  # Challenge
  let(:challenge) do
    BSV::X402::Challenge.new(
      v: 1,
      scheme: 'bsv-tx-v1',
      domain: 'example.com',
      method: 'GET',
      path: '/resource',
      query: '',
      req_headers_sha256: 'a' * 64,
      req_body_sha256: 'e' * 64,
      amount_sats: amount_sats,
      payee_locking_script_hex: payee_script_hex,
      nonce_utxo: nonce_utxo,
      expires_at: Time.now.to_i + 3600,
      require_mempool_accept: false
    )
  end

  # P2PKH nonce unlocker — signs using the nonce key.
  let(:nonce_unlocker) do
    p2pkh = BSV::Transaction::P2PKH.new(nonce_key)
    ->(tx, idx) { p2pkh.sign(tx, idx) }
  end

  # -------------------------------------------------------------------
  # Helper: build with defaults, allowing overrides.
  # -------------------------------------------------------------------

  def build(**overrides)
    BSV::X402::TransactionBuilder.build(
      challenge: overrides.fetch(:challenge, challenge),
      funding_utxos: overrides.fetch(:funding_utxos, [funding_utxo]),
      nonce_unlocker: overrides.fetch(:nonce_unlocker, nonce_unlocker),
      change_locking_script_hex: overrides.fetch(:change_locking_script_hex, change_script_hex)
    )
  end

  # -------------------------------------------------------------------
  # Happy path
  # -------------------------------------------------------------------

  describe 'nonce UTXO input' do
    it 'adds the nonce UTXO as the first input' do
      tx = build
      expect(tx.inputs.first.txid_hex).to eq(nonce_txid)
      expect(tx.inputs.first.prev_tx_out_index).to eq(nonce_vout)
    end

    it 'calls the nonce_unlocker to produce an unlocking script for input 0' do
      called_with = []
      custom_unlocker = lambda do |tx, idx|
        called_with << [tx, idx]
        BSV::Transaction::P2PKH.new(nonce_key).sign(tx, idx)
      end

      build(nonce_unlocker: custom_unlocker)

      expect(called_with.length).to eq(1)
      expect(called_with.first[1]).to eq(0)
    end

    it 'sets an unlocking script on the nonce input after building' do
      tx = build
      expect(tx.inputs.first.unlocking_script).not_to be_nil
    end
  end

  describe 'funding UTXOs' do
    it 'includes each funding UTXO as an input after the nonce' do
      tx = build
      expect(tx.inputs.length).to eq(2) # nonce + 1 funding
      expect(tx.inputs[1].txid_hex).to eq(funding_utxo[:txid])
    end

    it 'adds multiple funding inputs when multiple UTXOs are provided' do
      second_key  = BSV::Primitives::PrivateKey.generate
      second_lock = BSV::Script::Script.p2pkh_lock(second_key.public_key.hash160)
      second_utxo = {
        txid: 'cc' * 32,
        vout: 1,
        satoshis: 5_000,
        locking_script_hex: second_lock.to_hex,
        private_key: second_key
      }

      tx = build(funding_utxos: [funding_utxo, second_utxo])
      expect(tx.inputs.length).to eq(3) # nonce + 2 funding
    end
  end

  describe 'payment output' do
    it 'includes a payment output with the payee locking script' do
      tx = build
      matching = tx.outputs.find { |o| o.locking_script.to_hex == payee_script_hex }
      expect(matching).not_to be_nil
    end

    it 'sets the payment output satoshis to amount_sats from the challenge' do
      tx = build
      matching = tx.outputs.find { |o| o.locking_script.to_hex == payee_script_hex }
      expect(matching.satoshis).to eq(amount_sats)
    end
  end

  describe 'change output' do
    it 'includes a change output when change_locking_script_hex is provided and surplus exists' do
      tx = build
      change_output = tx.outputs.find { |o| o.locking_script.to_hex == change_script_hex }
      expect(change_output).not_to be_nil
    end

    it 'omits the change output when change_locking_script_hex is nil' do
      tx = build(change_locking_script_hex: nil)
      expect(tx.outputs.length).to eq(1) # only the payment output
    end

    it 'omits the change output when there is no surplus after fee' do
      # Use only nonce satoshis — just enough to cover the payment amount (barely).
      tiny_utxo = {
        txid: 'dd' * 32,
        vout: 0,
        satoshis: amount_sats, # exactly enough, no room for fee
        locking_script_hex: funding_locking_script.to_hex,
        private_key: funding_key
      }
      # With nonce (10 sats) + tiny_utxo (500 sats) = 510 sats total.
      # Fee will consume the surplus, so change should be removed.
      tx = build(funding_utxos: [tiny_utxo])
      change_output = tx.outputs.find { |o| o.locking_script.to_hex == change_script_hex }
      expect(change_output).to be_nil
    end
  end

  describe 'signing' do
    it 'produces a transaction with unlocking scripts on all inputs' do
      tx = build
      tx.inputs.each_with_index do |input, i|
        expect(input.unlocking_script).not_to be_nil, "input #{i} has no unlocking script"
      end
    end
  end

  describe 'error cases' do
    it 'raises ChallengeExpiredError when the challenge has expired' do
      expired_challenge = BSV::X402::Challenge.new(
        v: 1,
        scheme: 'bsv-tx-v1',
        domain: 'example.com',
        method: 'GET',
        path: '/resource',
        query: '',
        req_headers_sha256: 'a' * 64,
        req_body_sha256: 'e' * 64,
        amount_sats: 100,
        payee_locking_script_hex: payee_script_hex,
        nonce_utxo: nonce_utxo,
        expires_at: Time.now.to_i - 1,
        require_mempool_accept: false
      )

      expect { build(challenge: expired_challenge) }.to raise_error(BSV::X402::ChallengeExpiredError)
    end

    it 'raises InsufficientFundsError when UTXOs cannot cover the payment amount' do
      poor_utxo = {
        txid: 'ee' * 32,
        vout: 0,
        satoshis: 1,
        locking_script_hex: funding_locking_script.to_hex,
        private_key: funding_key
      }

      # nonce (10) + poor (1) = 11 sats, but amount_sats is 500.
      expect { build(funding_utxos: [poor_utxo]) }.to raise_error(BSV::X402::InsufficientFundsError)
    end
  end
end
