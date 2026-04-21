# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require 'bsv-wallet'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'BSV::Auth.validate_certificates' do
  let(:subject_key)   { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(21)) }
  let(:certifier_key) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(22)) }
  let(:verifier_key)  { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(23)) }
  let(:wrong_key)     { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(31)) }

  let(:subject_wallet)   { BSV::Wallet::Client.new(subject_key, storage: BSV::Wallet::Store::Memory.new, allow_memory_store: true) }
  let(:certifier_wallet) { BSV::Wallet::Client.new(certifier_key, storage: BSV::Wallet::Store::Memory.new, allow_memory_store: true) }
  let(:verifier_wallet)  { BSV::Wallet::Client.new(verifier_key, storage: BSV::Wallet::Store::Memory.new, allow_memory_store: true) }
  let(:wrong_wallet)     { BSV::Wallet::Client.new(wrong_key, storage: BSV::Wallet::Store::Memory.new, allow_memory_store: true) }

  let(:subject_hex)   { subject_key.public_key.to_hex }
  let(:certifier_hex) { certifier_key.public_key.to_hex }
  let(:verifier_hex)  { verifier_key.public_key.to_hex }

  let(:cert_type)     { Base64.strict_encode64("\x01" * 32) }
  let(:serial_number) { Base64.strict_encode64("\x02" * 32) }

  let(:plaintext_fields) { { 'name' => 'Alice', 'email' => 'alice@example.com' } }

  # Issue a master certificate and build a verifier keyring.
  let(:master_cert) do
    BSV::Auth::MasterCertificate.issue_certificate_for_subject(
      certifier_wallet,
      subject_hex,
      plaintext_fields,
      cert_type,
      serial_number: serial_number
    )
  end

  let(:verifier_keyring) do
    BSV::Auth::MasterCertificate.create_keyring_for_verifier(
      subject_wallet,
      certifier: certifier_hex,
      verifier: verifier_hex,
      fields: master_cert.fields,
      fields_to_reveal: plaintext_fields.keys,
      master_keyring: master_cert.master_keyring,
      serial_number: master_cert.serial_number
    )
  end

  let(:verifiable_cert) do
    BSV::Auth::VerifiableCertificate.from_certificate(master_cert, verifier_keyring)
  end

  let(:valid_message) do
    {
      identity_key: subject_hex,
      certificates: [verifiable_cert]
    }
  end

  # --- Happy path ---

  describe 'with a valid VerifiableCertificate' do
    it 'does not raise when all checks pass' do
      expect { BSV::Auth.validate_certificates(verifier_wallet, valid_message) }.not_to raise_error
    end

    it 'decrypts certificate fields as a side-effect' do
      BSV::Auth.validate_certificates(verifier_wallet, valid_message)
      expect(verifiable_cert.decrypted_fields).to eq(plaintext_fields)
    end
  end

  # --- Hash input ---

  describe 'with a Hash certificate input' do
    it 'constructs a VerifiableCertificate and validates it' do
      cert_hash = verifiable_cert.to_h
      message = { identity_key: subject_hex, certificates: [cert_hash] }
      expect { BSV::Auth.validate_certificates(verifier_wallet, message) }.not_to raise_error
    end
  end

  # --- String keys in message ---

  describe 'with string keys in the message hash' do
    it 'accepts string-keyed message hashes' do
      message = { 'identity_key' => subject_hex, 'certificates' => [verifiable_cert] }
      expect { BSV::Auth.validate_certificates(verifier_wallet, message) }.not_to raise_error
    end
  end

  # --- No certificates ---

  describe 'when certificates is nil' do
    it 'raises AuthError with descriptive message' do
      message = { identity_key: subject_hex, certificates: nil }
      expect do
        BSV::Auth.validate_certificates(verifier_wallet, message)
      end.to raise_error(BSV::Auth::AuthError, /No certificates/)
    end
  end

  # --- Empty certificates ---

  describe 'when certificates array is empty' do
    it 'raises AuthError' do
      message = { identity_key: subject_hex, certificates: [] }
      expect do
        BSV::Auth.validate_certificates(verifier_wallet, message)
      end.to raise_error(BSV::Auth::AuthError, /No certificates/)
    end
  end

  # --- Subject mismatch ---

  describe 'when certificate subject does not match message identity_key' do
    it 'raises AuthError mentioning both keys' do
      wrong_subject_hex = wrong_key.public_key.to_hex
      message = { identity_key: wrong_subject_hex, certificates: [verifiable_cert] }
      expect do
        BSV::Auth.validate_certificates(verifier_wallet, message)
      end.to raise_error(BSV::Auth::AuthError, /#{Regexp.escape(subject_hex)}.*#{Regexp.escape(wrong_subject_hex)}/m)
    end
  end

  # --- Invalid signature ---

  describe 'when certificate has a tampered signature' do
    it 'raises AuthError about invalid signature' do
      tampered = BSV::Auth::VerifiableCertificate.new(
        type: master_cert.type,
        serial_number: master_cert.serial_number,
        subject: master_cert.subject,
        certifier: master_cert.certifier,
        revocation_outpoint: master_cert.revocation_outpoint,
        fields: master_cert.fields,
        keyring: verifier_keyring,
        signature: 'deadbeef' * 9
      )
      message = { identity_key: subject_hex, certificates: [tampered] }
      expect do
        BSV::Auth.validate_certificates(verifier_wallet, message)
      end.to raise_error(BSV::Auth::AuthError, /invalid|verification failed/i)
    end
  end

  # --- Unrequested certifier ---

  describe 'when certifier is not in requested_certificates[:certifiers]' do
    it 'raises AuthError about unrequested certifier' do
      requested = {
        certifiers: [wrong_key.public_key.to_hex],
        types: { cert_type => [] }
      }
      expect do
        BSV::Auth.validate_certificates(verifier_wallet, valid_message, requested)
      end.to raise_error(BSV::Auth::AuthError, /unrequested certifier/)
    end
  end

  # --- Unrequested type ---

  describe 'when certificate type is not in requested_certificates[:types]' do
    it 'raises AuthError about unrequested type' do
      other_type = Base64.strict_encode64("\xFF" * 32)
      requested = {
        certifiers: [certifier_hex],
        types: { other_type => [] }
      }
      expect do
        BSV::Auth.validate_certificates(verifier_wallet, valid_message, requested)
      end.to raise_error(BSV::Auth::AuthError, /was not requested/)
    end
  end

  # --- Successful with requested_certificates filter ---

  describe 'with matching requested_certificates' do
    it 'passes when certifier and type are both in the requested set' do
      requested = {
        certifiers: [certifier_hex],
        types: { cert_type => [] }
      }
      expect do
        BSV::Auth.validate_certificates(verifier_wallet, valid_message, requested)
      end.not_to raise_error
    end
  end

  # --- Decryption failure ---

  describe 'when decryption fails due to wrong wallet' do
    it 'raises AuthError about failed decryption' do
      expect do
        BSV::Auth.validate_certificates(wrong_wallet, valid_message)
      end.to raise_error(BSV::Auth::AuthError, /Failed to decrypt/)
    end
  end

  # --- Multiple certificates ---

  describe 'with multiple valid certificates' do
    let(:serial_number_2) { Base64.strict_encode64("\x03" * 32) }

    let(:master_cert_2) do
      BSV::Auth::MasterCertificate.issue_certificate_for_subject(
        certifier_wallet,
        subject_hex,
        { 'role' => 'admin' },
        cert_type,
        serial_number: serial_number_2
      )
    end

    let(:verifier_keyring_2) do
      BSV::Auth::MasterCertificate.create_keyring_for_verifier(
        subject_wallet,
        certifier: certifier_hex,
        verifier: verifier_hex,
        fields: master_cert_2.fields,
        fields_to_reveal: ['role'],
        master_keyring: master_cert_2.master_keyring,
        serial_number: master_cert_2.serial_number
      )
    end

    let(:verifiable_cert_2) do
      BSV::Auth::VerifiableCertificate.from_certificate(master_cert_2, verifier_keyring_2)
    end

    it 'validates all certificates without raising' do
      message = {
        identity_key: subject_hex,
        certificates: [verifiable_cert, verifiable_cert_2]
      }
      expect { BSV::Auth.validate_certificates(verifier_wallet, message) }.not_to raise_error
    end
  end

  # --- nil requested_certificates skips certifier/type checks ---

  describe 'when requested_certificates is nil' do
    it 'skips certifier and type checks and still validates signature and decrypts' do
      expect { BSV::Auth.validate_certificates(verifier_wallet, valid_message, nil) }.not_to raise_error
    end
  end
end
# rubocop:enable RSpec/DescribeClass
