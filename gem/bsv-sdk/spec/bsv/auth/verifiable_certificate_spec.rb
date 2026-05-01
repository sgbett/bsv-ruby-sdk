# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Auth::VerifiableCertificate do
  # --- Shared fixtures using deterministic keys matching TS SDK test vectors ---

  let(:subject_key)   { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(21)) }
  let(:certifier_key) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(22)) }
  let(:verifier_key)  { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(23)) }
  let(:wrong_key)     { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(31)) }

  let(:subject_wallet)   { BSV::Wallet::ProtoWallet.new(subject_key) }
  let(:certifier_wallet) { BSV::Wallet::ProtoWallet.new(certifier_key) }
  let(:verifier_wallet)  { BSV::Wallet::ProtoWallet.new(verifier_key) }
  let(:wrong_wallet)     { BSV::Wallet::ProtoWallet.new(wrong_key) }

  let(:subject_hex)   { subject_key.public_key.to_hex }
  let(:certifier_hex) { certifier_key.public_key.to_hex }
  let(:verifier_hex)  { verifier_key.public_key.to_hex }

  let(:cert_type)       { Base64.strict_encode64("\x01" * 32) }
  let(:serial_number)   { Base64.strict_encode64("\x02" * 32) }
  let(:revocation_outpoint) do
    'deadbeefdeadbeefdeadbeefdeadbeef00000000000000000000000000000000.1'
  end

  let(:plaintext_fields) do
    { 'name' => 'Alice', 'email' => 'alice@example.com', 'organization' => 'Example Corp' }
  end

  # Issued master certificate (certifier encrypts fields for subject).
  # Subject wallet is used as the "creator" to match MasterCertificate.issue_certificate_for_subject
  # which calls create_certificate_fields with the certifier_wallet and subject as counterparty.
  let(:master_cert) do
    BSV::Auth::MasterCertificate.issue_certificate_for_subject(
      certifier_wallet,
      subject_hex,
      plaintext_fields,
      cert_type,
      serial_number: serial_number
    )
  end

  # Verifier keyring: subject re-encrypts all field keys for the verifier.
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

  # The VerifiableCertificate ready for tests.
  let(:verifiable_cert) do
    described_class.new(
      type: master_cert.type,
      serial_number: master_cert.serial_number,
      subject: master_cert.subject,
      certifier: master_cert.certifier,
      revocation_outpoint: master_cert.revocation_outpoint,
      fields: master_cert.fields,
      keyring: verifier_keyring,
      signature: master_cert.signature
    )
  end

  # --- Scenario 1: constructor and instanceof ---

  describe '#initialize' do
    it 'creates a VerifiableCertificate with all required properties' do
      cert = verifiable_cert
      expect(cert).to be_a(described_class)
      expect(cert).to be_a(BSV::Auth::Certificate)
      expect(cert.type).to eq(cert_type)
      expect(cert.serial_number).to eq(serial_number)
      expect(cert.subject).to eq(subject_hex)
      expect(cert.certifier).to eq(certifier_hex)
      expect(cert.revocation_outpoint).to eq(master_cert.revocation_outpoint)
      expect(cert.fields).not_to be_empty
      expect(cert.keyring).not_to be_empty
      expect(cert.decrypted_fields).to be_nil
    end
  end

  # --- Scenario 2: successful decryption ---

  describe '#decrypt_fields — correct verifier wallet' do
    it 'decrypts all fields successfully' do
      decrypted = verifiable_cert.decrypt_fields(verifier_wallet)
      expect(decrypted).to eq(plaintext_fields)
    end

    it 'caches the result in decrypted_fields' do
      verifiable_cert.decrypt_fields(verifier_wallet)
      expect(verifiable_cert.decrypted_fields).to eq(plaintext_fields)
    end
  end

  # --- Scenario 3: wrong wallet key fails ---

  describe '#decrypt_fields — wrong wallet key' do
    it 'raises with a descriptive error message' do
      expect do
        verifiable_cert.decrypt_fields(wrong_wallet)
      end.to raise_error(RuntimeError, /Failed to decrypt selectively revealed certificate fields using keyring/)
    end
  end

  # --- Scenario 4: empty keyring raises ---

  describe '#decrypt_fields — empty keyring' do
    it 'raises ArgumentError immediately' do
      cert = described_class.new(
        type: master_cert.type,
        serial_number: master_cert.serial_number,
        subject: master_cert.subject,
        certifier: master_cert.certifier,
        revocation_outpoint: master_cert.revocation_outpoint,
        fields: master_cert.fields,
        keyring: {}
      )
      expect do
        cert.decrypt_fields(verifier_wallet)
      end.to raise_error(ArgumentError, /A keyring is required/)
    end
  end

  # --- Scenario 5: tampered keyring entry fails ---

  describe '#decrypt_fields — tampered keyring' do
    it 'raises when a keyring entry is corrupted' do
      tampered_keyring = verifier_keyring.dup
      tampered_keyring['name'] = Base64.strict_encode64([9, 9, 9, 9].pack('C*'))

      cert = described_class.new(
        type: master_cert.type,
        serial_number: master_cert.serial_number,
        subject: master_cert.subject,
        certifier: master_cert.certifier,
        revocation_outpoint: master_cert.revocation_outpoint,
        fields: master_cert.fields,
        keyring: tampered_keyring
      )

      expect do
        cert.decrypt_fields(verifier_wallet)
      end.to raise_error(StandardError)
    end
  end

  # --- Scenario 6: 'anyone' verifier ---

  describe "#decrypt_fields — 'anyone' verifier" do
    it "decrypts fields when verifier is 'anyone'" do
      anyone_master = BSV::Auth::MasterCertificate.issue_certificate_for_subject(
        certifier_wallet,
        subject_hex,
        plaintext_fields,
        cert_type,
        serial_number: serial_number
      )

      anyone_keyring = BSV::Auth::MasterCertificate.create_keyring_for_verifier(
        subject_wallet,
        certifier: certifier_hex,
        verifier: 'anyone',
        fields: anyone_master.fields,
        fields_to_reveal: plaintext_fields.keys,
        master_keyring: anyone_master.master_keyring,
        serial_number: anyone_master.serial_number
      )

      cert = described_class.new(
        type: anyone_master.type,
        serial_number: anyone_master.serial_number,
        subject: anyone_master.subject,
        certifier: anyone_master.certifier,
        revocation_outpoint: anyone_master.revocation_outpoint,
        fields: anyone_master.fields,
        keyring: anyone_keyring
      )

      anyone_wallet = BSV::Wallet::ProtoWallet.new('anyone')
      decrypted = cert.decrypt_fields(anyone_wallet)
      expect(decrypted).to eq(plaintext_fields)
    end
  end

  # --- Scenario 7: from_certificate factory ---

  describe '.from_certificate' do
    it 'produces an equivalent VerifiableCertificate that can decrypt successfully' do
      base_cert = BSV::Auth::Certificate.new(
        type: master_cert.type,
        serial_number: master_cert.serial_number,
        subject: master_cert.subject,
        certifier: master_cert.certifier,
        revocation_outpoint: master_cert.revocation_outpoint,
        fields: master_cert.fields,
        signature: master_cert.signature
      )

      verifiable = described_class.from_certificate(base_cert, verifier_keyring)

      expect(verifiable).to be_a(described_class)
      expect(verifiable.serial_number).to eq(master_cert.serial_number)
      expect(verifiable.keyring).to eq(verifier_keyring)

      decrypted = verifiable.decrypt_fields(verifier_wallet)
      expect(decrypted).to eq(plaintext_fields)
    end
  end

  # --- to_h / from_hash round-trip ---

  describe '#to_h and .from_hash' do
    it 'round-trips without data loss' do
      verifiable_cert.decrypt_fields(verifier_wallet)
      h = verifiable_cert.to_h

      expect(h['keyring']).to eq(verifier_keyring)
      expect(h['decrypted_fields']).to eq(plaintext_fields)

      restored = described_class.from_hash(h)
      expect(restored.keyring).to eq(verifier_keyring)
      expect(restored.decrypted_fields).to eq(plaintext_fields)
      expect(restored.serial_number).to eq(verifiable_cert.serial_number)
    end

    it 'to_h omits decrypted_fields when not yet decrypted' do
      h = verifiable_cert.to_h
      expect(h).not_to have_key('decrypted_fields')
    end

    it 'accepts camelCase decryptedFields key in from_hash' do
      verifiable_cert.decrypt_fields(verifier_wallet)
      h = verifiable_cert.to_h
      h['decryptedFields'] = h.delete('decrypted_fields')
      restored = described_class.from_hash(h)
      expect(restored.decrypted_fields).to eq(plaintext_fields)
    end
  end

  # --- Partial reveal ---

  describe 'partial field revelation' do
    it 'only reveals the fields present in the keyring' do
      partial_keyring = BSV::Auth::MasterCertificate.create_keyring_for_verifier(
        subject_wallet,
        certifier: certifier_hex,
        verifier: verifier_hex,
        fields: master_cert.fields,
        fields_to_reveal: ['name'],
        master_keyring: master_cert.master_keyring,
        serial_number: master_cert.serial_number
      )

      cert = described_class.new(
        type: master_cert.type,
        serial_number: master_cert.serial_number,
        subject: master_cert.subject,
        certifier: master_cert.certifier,
        revocation_outpoint: master_cert.revocation_outpoint,
        fields: master_cert.fields,
        keyring: partial_keyring
      )

      decrypted = cert.decrypt_fields(verifier_wallet)
      expect(decrypted.keys).to eq(['name'])
      expect(decrypted['name']).to eq('Alice')
    end
  end
end
