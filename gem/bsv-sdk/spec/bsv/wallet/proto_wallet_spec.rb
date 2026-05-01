# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Wallet::ProtoWallet do
  let(:private_key) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(42)) }
  let(:wallet)      { described_class.new(private_key) }
  let(:anyone)      { described_class.new('anyone') }

  let(:protocol_id)  { [1, 'test protocol'] }
  let(:key_id)       { 'key-1' }
  let(:counterparty) { 'self' }

  # -------------------------------------------------------------------------
  # Constructor
  # -------------------------------------------------------------------------

  describe '.new' do
    it 'accepts a PrivateKey' do
      expect { described_class.new(private_key) }.not_to raise_error
    end

    it "accepts 'anyone'" do
      expect { described_class.new('anyone') }.not_to raise_error
    end

    it 'raises ArgumentError for unsupported input' do
      expect { described_class.new('not-a-key') }.to raise_error(ArgumentError)
    end
  end

  # -------------------------------------------------------------------------
  # get_public_key
  # -------------------------------------------------------------------------

  describe '#get_public_key' do
    it 'returns the identity key when identity_key: true' do
      result = wallet.get_public_key(identity_key: true)
      expect(result[:public_key]).to eq(private_key.public_key.to_hex)
    end

    it 'returns a derived public key when identity_key is absent' do
      result = wallet.get_public_key(
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: counterparty
      )
      expect(result[:public_key]).to be_a(String)
      expect(result[:public_key].length).to eq(66)
    end

    it 'accepts the originator: keyword without error' do
      result = wallet.get_public_key(identity_key: true, originator: 'test-app')
      expect(result[:public_key]).to eq(private_key.public_key.to_hex)
    end
  end

  # -------------------------------------------------------------------------
  # create_signature / verify_signature
  # -------------------------------------------------------------------------

  describe '#create_signature and #verify_signature' do
    let(:data) { 'Hello, BSV!'.bytes }

    it 'roundtrips: create then verify returns { valid: true }' do
      sig_result = wallet.create_signature(
        data: data,
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: 'anyone'
      )

      expect(sig_result[:signature]).to be_an(Array)

      verify_result = wallet.verify_signature(
        data: data,
        signature: sig_result[:signature],
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: 'anyone',
        for_self: true
      )

      expect(verify_result[:valid]).to be true
    end

    it 'raises InvalidSignatureError for a bad signature' do
      bad_sig = wallet.create_signature(
        data: 'other data'.bytes,
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: 'anyone'
      )

      expect do
        wallet.verify_signature(
          data: data,
          signature: bad_sig[:signature],
          protocol_id: protocol_id,
          key_id: key_id,
          counterparty: 'anyone',
          for_self: true
        )
      end.to raise_error(BSV::Wallet::InvalidSignatureError)
    end
  end

  # -------------------------------------------------------------------------
  # encrypt / decrypt
  # -------------------------------------------------------------------------

  describe '#encrypt and #decrypt' do
    let(:plaintext) { 'secret message'.bytes }

    it 'roundtrips: encrypt then decrypt returns the original plaintext' do
      enc = wallet.encrypt(
        plaintext: plaintext,
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: counterparty
      )

      expect(enc[:ciphertext]).to be_an(Array)
      expect(enc[:ciphertext]).not_to eq(plaintext)

      dec = wallet.decrypt(
        ciphertext: enc[:ciphertext],
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: counterparty
      )

      expect(dec[:plaintext]).to eq(plaintext)
    end
  end

  # -------------------------------------------------------------------------
  # create_hmac / verify_hmac
  # -------------------------------------------------------------------------

  describe '#create_hmac and #verify_hmac' do
    let(:data) { 'authenticated data'.bytes }

    it 'roundtrips: create then verify returns { valid: true }' do
      hmac_result = wallet.create_hmac(
        data: data,
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: counterparty
      )

      expect(hmac_result[:hmac]).to be_an(Array)
      expect(hmac_result[:hmac].length).to eq(32)

      verify_result = wallet.verify_hmac(
        data: data,
        hmac: hmac_result[:hmac],
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: counterparty
      )

      expect(verify_result[:valid]).to be true
    end

    it 'raises InvalidHmacError for a tampered HMAC' do
      hmac_result = wallet.create_hmac(
        data: data,
        protocol_id: protocol_id,
        key_id: key_id,
        counterparty: counterparty
      )

      bad_hmac = hmac_result[:hmac].map { |b| b ^ 0xff }

      expect do
        wallet.verify_hmac(
          data: data,
          hmac: bad_hmac,
          protocol_id: protocol_id,
          key_id: key_id,
          counterparty: counterparty
        )
      end.to raise_error(BSV::Wallet::InvalidHmacError)
    end
  end

  # -------------------------------------------------------------------------
  # list_certificates / prove_certificate
  # -------------------------------------------------------------------------

  describe '#list_certificates' do
    it 'returns an empty certificate list' do
      result = wallet.list_certificates
      expect(result[:certificates]).to eq([])
    end

    it 'accepts args and originator without error' do
      result = wallet.list_certificates(originator: 'test-app')
      expect(result[:certificates]).to eq([])
    end
  end

  describe '#prove_certificate' do
    it 'raises UnsupportedActionError' do
      expect { wallet.prove_certificate }.to raise_error(BSV::Wallet::UnsupportedActionError)
    end
  end

  # -------------------------------------------------------------------------
  # Cross-wallet derivation symmetry
  # -------------------------------------------------------------------------

  describe 'cross-wallet derivation symmetry' do
    let(:alice_key) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(10)) }
    let(:bob_key)   { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(20)) }
    let(:alice)     { described_class.new(alice_key) }
    let(:bob)       { described_class.new(bob_key) }

    let(:alice_hex) { alice_key.public_key.to_hex }
    let(:bob_hex)   { bob_key.public_key.to_hex }

    it 'alice encrypting to bob can be decrypted by bob' do
      plaintext = 'shared secret'.bytes

      enc = alice.encrypt(
        plaintext: plaintext,
        protocol_id: [2, 'cross wallet test'],
        key_id: 'shared-1',
        counterparty: bob_hex
      )

      dec = bob.decrypt(
        ciphertext: enc[:ciphertext],
        protocol_id: [2, 'cross wallet test'],
        key_id: 'shared-1',
        counterparty: alice_hex
      )

      expect(dec[:plaintext]).to eq(plaintext)
    end

    it 'alice HMAC verified by bob' do
      data = 'cross-wallet authenticated'.bytes

      hmac_result = alice.create_hmac(
        data: data,
        protocol_id: [2, 'cross wallet test'],
        key_id: 'hmac-1',
        counterparty: bob_hex
      )

      verify_result = bob.verify_hmac(
        data: data,
        hmac: hmac_result[:hmac],
        protocol_id: [2, 'cross wallet test'],
        key_id: 'hmac-1',
        counterparty: alice_hex
      )

      expect(verify_result[:valid]).to be true
    end
  end
end
