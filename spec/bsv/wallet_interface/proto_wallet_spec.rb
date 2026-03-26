# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::ProtoWallet do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:wallet) { described_class.new(private_key) }
  let(:protocol_id) { [0, 'hello world'] }
  let(:key_id) { 'test key 1' }
  let(:counterparty) { 'self' }
  let(:crypto_args) { { protocol_id: protocol_id, key_id: key_id, counterparty: counterparty } }

  describe '#initialize' do
    it 'wraps a PrivateKey in a KeyDeriver' do
      expect(wallet.key_deriver).to be_a(BSV::Wallet::KeyDeriver)
    end

    it 'accepts "anyone" as the key argument' do
      w = described_class.new('anyone')
      expect(w.key_deriver).to be_a(BSV::Wallet::KeyDeriver)
      expect(w.key_deriver.identity_key).to be_a(String)
    end

    it 'accepts a pre-built KeyDeriver directly' do
      kd = BSV::Wallet::KeyDeriver.new(private_key)
      w = described_class.new(kd)
      expect(w.key_deriver).to equal(kd)
    end
  end

  describe '#get_public_key' do
    it 'returns the identity key when identity_key: true' do
      result = wallet.get_public_key({ identity_key: true })
      expect(result[:public_key]).to eq(private_key.public_key.to_hex)
    end

    it 'returns a derived public key for a protocol and key ID' do
      result = wallet.get_public_key(crypto_args)
      expect(result[:public_key]).to be_a(String)
      expect(result[:public_key].length).to eq(66)
      expect(result[:public_key]).not_to eq(private_key.public_key.to_hex)
    end

    it 'returns consistent results for the same inputs' do
      result1 = wallet.get_public_key(crypto_args)
      result2 = wallet.get_public_key(crypto_args)
      expect(result1[:public_key]).to eq(result2[:public_key])
    end

    it 'returns different keys for different key IDs' do
      r1 = wallet.get_public_key(crypto_args.merge(key_id: 'key1'))
      r2 = wallet.get_public_key(crypto_args.merge(key_id: 'key2'))
      expect(r1[:public_key]).not_to eq(r2[:public_key])
    end

    it 'defaults counterparty to "self" when not provided' do
      without_cp = wallet.get_public_key({ protocol_id: protocol_id, key_id: key_id })
      with_self_cp = wallet.get_public_key(crypto_args)
      expect(without_cp[:public_key]).to eq(with_self_cp[:public_key])
    end
  end

  describe '#encrypt' do
    let(:plaintext_bytes) { [72, 101, 108, 108, 111] } # "Hello"

    it 'returns a hash with a :ciphertext key containing an array of integers' do
      result = wallet.encrypt(crypto_args.merge(plaintext: plaintext_bytes))
      expect(result).to have_key(:ciphertext)
      expect(result[:ciphertext]).to be_a(Array)
      expect(result[:ciphertext]).to all(be_a(Integer))
    end

    it 'produces ciphertext that differs from the plaintext' do
      result = wallet.encrypt(crypto_args.merge(plaintext: plaintext_bytes))
      expect(result[:ciphertext]).not_to eq(plaintext_bytes)
    end
  end

  describe '#decrypt' do
    let(:plaintext_bytes) { [72, 101, 108, 108, 111] } # "Hello"

    it 'restores the original plaintext after encrypt/decrypt round-trip' do
      encrypted = wallet.encrypt(crypto_args.merge(plaintext: plaintext_bytes))
      decrypted = wallet.decrypt(crypto_args.merge(ciphertext: encrypted[:ciphertext]))
      expect(decrypted[:plaintext]).to eq(plaintext_bytes)
    end

    it 'returns plaintext as an array of integers' do
      encrypted = wallet.encrypt(crypto_args.merge(plaintext: plaintext_bytes))
      decrypted = wallet.decrypt(crypto_args.merge(ciphertext: encrypted[:ciphertext]))
      expect(decrypted[:plaintext]).to all(be_a(Integer))
    end
  end

  describe '#create_hmac' do
    let(:data_bytes) { [1, 2, 3, 4, 5] }

    it 'returns a hash with an :hmac key' do
      result = wallet.create_hmac(crypto_args.merge(data: data_bytes))
      expect(result).to have_key(:hmac)
    end

    it 'returns a 32-byte HMAC as an array of integers' do
      result = wallet.create_hmac(crypto_args.merge(data: data_bytes))
      expect(result[:hmac]).to be_a(Array)
      expect(result[:hmac].length).to eq(32)
      expect(result[:hmac]).to all(be_a(Integer))
    end

    it 'produces the same HMAC for identical inputs' do
      r1 = wallet.create_hmac(crypto_args.merge(data: data_bytes))
      r2 = wallet.create_hmac(crypto_args.merge(data: data_bytes))
      expect(r1[:hmac]).to eq(r2[:hmac])
    end

    it 'produces different HMACs for different data' do
      r1 = wallet.create_hmac(crypto_args.merge(data: [1, 2, 3]))
      r2 = wallet.create_hmac(crypto_args.merge(data: [4, 5, 6]))
      expect(r1[:hmac]).not_to eq(r2[:hmac])
    end
  end

  describe '#verify_hmac' do
    let(:data_bytes) { [1, 2, 3, 4, 5] }

    it 'returns { valid: true } for a correct HMAC' do
      result = wallet.create_hmac(crypto_args.merge(data: data_bytes))
      verify_result = wallet.verify_hmac(crypto_args.merge(data: data_bytes, hmac: result[:hmac]))
      expect(verify_result[:valid]).to be true
    end

    it 'raises InvalidHmacError for a tampered HMAC' do
      bad_hmac = Array.new(32, 0)
      expect do
        wallet.verify_hmac(crypto_args.merge(data: data_bytes, hmac: bad_hmac))
      end.to raise_error(BSV::Wallet::InvalidHmacError)
    end

    it 'raises InvalidHmacError when data differs from what was MACed' do
      result = wallet.create_hmac(crypto_args.merge(data: data_bytes))
      expect do
        wallet.verify_hmac(crypto_args.merge(data: [9, 9, 9], hmac: result[:hmac]))
      end.to raise_error(BSV::Wallet::InvalidHmacError)
    end
  end

  describe '#create_signature' do
    let(:data_bytes) { 'sign this data'.bytes }

    it 'returns a hash with a :signature key' do
      result = wallet.create_signature(crypto_args.merge(data: data_bytes))
      expect(result).to have_key(:signature)
    end

    it 'returns the signature as an array of integers' do
      result = wallet.create_signature(crypto_args.merge(data: data_bytes))
      expect(result[:signature]).to be_a(Array)
      expect(result[:signature]).to all(be_a(Integer))
    end

    it 'accepts hash_to_directly_sign instead of data' do
      hash = Array.new(32, 0xab)
      result = wallet.create_signature(crypto_args.merge(hash_to_directly_sign: hash))
      expect(result[:signature]).to be_a(Array)
    end
  end

  describe '#verify_signature' do
    let(:data_bytes) { 'sign this data'.bytes }

    it 'returns { valid: true } for a valid signature' do
      sig_result = wallet.create_signature(crypto_args.merge(data: data_bytes))
      verify_result = wallet.verify_signature(
        crypto_args.merge(data: data_bytes, signature: sig_result[:signature], for_self: true)
      )
      expect(verify_result[:valid]).to be true
    end

    it 'raises InvalidSignatureError when signature does not match the data' do
      sig_result = wallet.create_signature(crypto_args.merge(data: [9, 9, 9]))
      expect do
        wallet.verify_signature(
          crypto_args.merge(data: data_bytes, signature: sig_result[:signature], for_self: true)
        )
      end.to raise_error(BSV::Wallet::InvalidSignatureError)
    end
  end

  describe '#reveal_counterparty_key_linkage' do
    let(:prover_key) { BSV::Primitives::PrivateKey.generate }
    let(:verifier_key) { BSV::Primitives::PrivateKey.generate }
    let(:prover_wallet) { described_class.new(prover_key) }
    let(:verifier_wallet) { described_class.new(verifier_key) }
    let(:counterparty_key) { BSV::Primitives::PrivateKey.generate }

    let(:linkage_result) do
      prover_wallet.reveal_counterparty_key_linkage({
                                                      counterparty: counterparty_key.public_key.to_hex,
                                                      verifier: verifier_key.public_key.to_hex
                                                    })
    end

    it 'returns all expected keys in the result hash' do
      expect(linkage_result).to have_key(:prover)
      expect(linkage_result).to have_key(:verifier)
      expect(linkage_result).to have_key(:counterparty)
      expect(linkage_result).to have_key(:revelation_time)
      expect(linkage_result).to have_key(:encrypted_linkage)
      expect(linkage_result).to have_key(:encrypted_linkage_proof)
    end

    it 'sets prover to the prover wallet identity key' do
      expect(linkage_result[:prover]).to eq(prover_wallet.key_deriver.identity_key)
    end

    it 'echoes the verifier and counterparty keys' do
      expect(linkage_result[:verifier]).to eq(verifier_key.public_key.to_hex)
      expect(linkage_result[:counterparty]).to eq(counterparty_key.public_key.to_hex)
    end

    it 'returns an ISO 8601 revelation_time string' do
      expect(linkage_result[:revelation_time]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
    end

    it 'returns encrypted_linkage and encrypted_linkage_proof as arrays of integers' do
      expect(linkage_result[:encrypted_linkage]).to be_a(Array)
      expect(linkage_result[:encrypted_linkage]).to all(be_a(Integer))
      expect(linkage_result[:encrypted_linkage_proof]).to be_a(Array)
      expect(linkage_result[:encrypted_linkage_proof]).to all(be_a(Integer))
    end

    it 'raises InvalidParameterError when verifier is not a valid public key' do
      expect do
        prover_wallet.reveal_counterparty_key_linkage({
                                                        counterparty: counterparty_key.public_key.to_hex,
                                                        verifier: 'invalid'
                                                      })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'verifier can decrypt the linkage using the prover identity key as counterparty' do
      prover_identity_pub = prover_wallet.key_deriver.identity_key

      decrypted = verifier_wallet.decrypt({
                                            ciphertext: linkage_result[:encrypted_linkage],
                                            protocol_id: [2, 'counterparty linkage revelation'],
                                            key_id: linkage_result[:revelation_time],
                                            counterparty: prover_identity_pub
                                          })

      # The linkage is a compressed EC point — 33 bytes
      expect(decrypted[:plaintext].length).to eq(33)
    end

    it 'verifier can decrypt and verify the Schnorr proof using only public keys' do
      prover_identity_pub = prover_wallet.key_deriver.identity_key

      decrypt_args = {
        protocol_id: [2, 'counterparty linkage revelation'],
        key_id: linkage_result[:revelation_time],
        counterparty: prover_identity_pub
      }

      linkage_bytes = verifier_wallet.decrypt(
        decrypt_args.merge(ciphertext: linkage_result[:encrypted_linkage])
      )[:plaintext]

      proof_bytes = verifier_wallet.decrypt(
        decrypt_args.merge(ciphertext: linkage_result[:encrypted_linkage_proof])
      )[:plaintext]

      # Reconstruct the linkage EC point
      linkage_point = BSV::Primitives::PublicKey.from_bytes(linkage_bytes.pack('C*'))

      # Deserialise the 98-byte proof: 33 bytes R + 33 bytes S' + 32 bytes z
      proof_bin = proof_bytes.pack('C*')
      r_point     = BSV::Primitives::PublicKey.from_bytes(proof_bin[0, 33])
      s_prime     = BSV::Primitives::PublicKey.from_bytes(proof_bin[33, 33])
      z_scalar    = OpenSSL::BN.new(proof_bin[66, 32], 2)
      proof       = BSV::Primitives::Schnorr::Proof.new(r_point, s_prime, z_scalar)

      prover_pub       = BSV::Primitives::PublicKey.from_hex(prover_identity_pub)
      counterparty_pub = BSV::Primitives::PublicKey.from_hex(counterparty_key.public_key.to_hex)

      valid = BSV::Primitives::Schnorr.verify_proof(prover_pub, counterparty_pub, linkage_point, proof)
      expect(valid).to be true
    end
  end

  describe '#reveal_specific_key_linkage' do
    let(:prover_key) { BSV::Primitives::PrivateKey.generate }
    let(:verifier_key) { BSV::Primitives::PrivateKey.generate }
    let(:prover_wallet) { described_class.new(prover_key) }
    let(:verifier_wallet) { described_class.new(verifier_key) }
    let(:counterparty_key) { BSV::Primitives::PrivateKey.generate }

    let(:linkage_result) do
      prover_wallet.reveal_specific_key_linkage({
                                                  counterparty: counterparty_key.public_key.to_hex,
                                                  verifier: verifier_key.public_key.to_hex,
                                                  protocol_id: protocol_id,
                                                  key_id: key_id
                                                })
    end

    it 'returns all expected keys in the result hash' do
      expect(linkage_result).to have_key(:prover)
      expect(linkage_result).to have_key(:verifier)
      expect(linkage_result).to have_key(:counterparty)
      expect(linkage_result).to have_key(:protocol_id)
      expect(linkage_result).to have_key(:key_id)
      expect(linkage_result).to have_key(:encrypted_linkage)
      expect(linkage_result).to have_key(:encrypted_linkage_proof)
      expect(linkage_result).to have_key(:proof_type)
    end

    it 'sets prover to the prover wallet identity key' do
      expect(linkage_result[:prover]).to eq(prover_wallet.key_deriver.identity_key)
    end

    it 'echoes the protocol_id and key_id' do
      expect(linkage_result[:protocol_id]).to eq(protocol_id)
      expect(linkage_result[:key_id]).to eq(key_id)
    end

    it 'sets proof_type to 0' do
      expect(linkage_result[:proof_type]).to eq(0)
    end

    it 'returns encrypted_linkage as an array of integers' do
      expect(linkage_result[:encrypted_linkage]).to be_a(Array)
      expect(linkage_result[:encrypted_linkage]).to all(be_a(Integer))
    end

    it 'raises InvalidParameterError when verifier is not a valid public key' do
      expect do
        prover_wallet.reveal_specific_key_linkage({
                                                    counterparty: counterparty_key.public_key.to_hex,
                                                    verifier: 'invalid',
                                                    protocol_id: protocol_id,
                                                    key_id: key_id
                                                  })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'verifier can decrypt the proof and it decodes to [0]' do
      prover_identity_pub = prover_wallet.key_deriver.identity_key
      derived_protocol    = "specific linkage revelation #{protocol_id[0]} #{protocol_id[1]}"

      decrypted = verifier_wallet.decrypt({
                                            ciphertext: linkage_result[:encrypted_linkage_proof],
                                            protocol_id: [2, derived_protocol],
                                            key_id: key_id,
                                            counterparty: prover_identity_pub
                                          })

      expect(decrypted[:plaintext]).to eq([0])
    end

    it 'verifier can decrypt the linkage and it is 32 bytes' do
      prover_identity_pub = prover_wallet.key_deriver.identity_key
      derived_protocol    = "specific linkage revelation #{protocol_id[0]} #{protocol_id[1]}"

      decrypted = verifier_wallet.decrypt({
                                            ciphertext: linkage_result[:encrypted_linkage],
                                            protocol_id: [2, derived_protocol],
                                            key_id: key_id,
                                            counterparty: prover_identity_pub
                                          })

      # The linkage is an HMAC-SHA256 output — 32 bytes
      expect(decrypted[:plaintext].length).to eq(32)
    end
  end

  describe 'unsupported methods' do
    # Methods that require an args hash argument
    %i[
      create_action sign_action abort_action list_actions internalize_action
      list_outputs relinquish_output acquire_certificate list_certificates
      prove_certificate relinquish_certificate discover_by_identity_key
      discover_by_attributes get_header_for_height
    ].each do |method_name|
      it "raises UnsupportedActionError for ##{method_name}" do
        expect { wallet.send(method_name, {}) }.to raise_error(BSV::Wallet::UnsupportedActionError)
      end
    end

    # Methods with optional args that can be called with no arguments
    %i[get_height get_network get_version is_authenticated wait_for_authentication].each do |method_name|
      it "raises UnsupportedActionError for ##{method_name}" do
        expect { wallet.send(method_name) }.to raise_error(BSV::Wallet::UnsupportedActionError)
      end
    end
  end
end
