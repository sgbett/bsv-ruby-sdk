# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Auth::MasterCertificate do
  # --- Shared fixtures ---

  let(:certifier_key)    { BSV::Primitives::PrivateKey.generate }
  let(:subject_key)      { BSV::Primitives::PrivateKey.generate }
  let(:verifier_key)     { BSV::Primitives::PrivateKey.generate }

  let(:certifier_wallet) { BSV::Wallet::ProtoWallet.new(certifier_key) }
  let(:subject_wallet)   { BSV::Wallet::ProtoWallet.new(subject_key) }
  let(:verifier_wallet)  { BSV::Wallet::ProtoWallet.new(verifier_key) }

  let(:certifier_hex) { certifier_key.public_key.to_hex }
  let(:subject_hex)   { subject_key.public_key.to_hex }
  let(:verifier_hex)  { verifier_key.public_key.to_hex }

  let(:cert_type)  { Base64.strict_encode64(SecureRandom.random_bytes(32)) }
  let(:serial)     { Base64.strict_encode64(SecureRandom.random_bytes(32)) }
  let(:outpoint)   { "#{'aa' * 32}.0" }
  let(:plain_fields) { { 'name' => 'Alice', 'email' => 'alice@example.com' } }

  # Helper: issue a certificate from certifier to a given subject wallet
  def issue_cert(subject: subject_hex, fields: plain_fields)
    BSV::Auth::MasterCertificate.issue_certificate_for_subject(
      certifier_wallet,
      subject,
      fields,
      cert_type
    )
  end

  # Helper: build a valid master_keyring for pre-encrypted fields
  def build_keyring_and_fields(creator_wallet, counterparty, fields)
    BSV::Auth::MasterCertificate.create_certificate_fields(creator_wallet, counterparty, fields)
  end

  # --- Scenario 1: constructor succeeds with valid master keyring ---

  describe '#initialize with valid master keyring' do
    it 'stores all attributes including master_keyring' do
      result = build_keyring_and_fields(certifier_wallet, subject_hex, plain_fields)
      cert = described_class.new(
        type: cert_type,
        serial_number: serial,
        subject: subject_hex,
        certifier: certifier_hex,
        revocation_outpoint: outpoint,
        fields: result[:certificate_fields],
        master_keyring: result[:master_keyring]
      )

      expect(cert.type).to eq(cert_type)
      expect(cert.serial_number).to eq(serial)
      expect(cert.subject).to eq(subject_hex)
      expect(cert.certifier).to eq(certifier_hex)
      expect(cert.master_keyring.keys).to match_array(plain_fields.keys)
    end

    it 'is a Certificate subclass' do
      result = build_keyring_and_fields(certifier_wallet, subject_hex, plain_fields)
      cert = described_class.new(
        type: cert_type,
        serial_number: serial,
        subject: subject_hex,
        certifier: certifier_hex,
        revocation_outpoint: outpoint,
        fields: result[:certificate_fields],
        master_keyring: result[:master_keyring]
      )
      expect(cert).to be_a(BSV::Auth::Certificate)
    end
  end

  # --- Scenario 2: constructor raises when master keyring missing a field key ---

  describe '#initialize raises on incomplete master_keyring' do
    it 'raises ArgumentError when a field has no keyring entry' do
      result = build_keyring_and_fields(certifier_wallet, subject_hex, plain_fields)
      incomplete_keyring = result[:master_keyring].dup
      incomplete_keyring.delete('email')

      expect do
        described_class.new(
          type: cert_type,
          serial_number: serial,
          subject: subject_hex,
          certifier: certifier_hex,
          revocation_outpoint: outpoint,
          fields: result[:certificate_fields],
          master_keyring: incomplete_keyring
        )
      end.to raise_error(ArgumentError, /Missing or empty key for field: "email"/)
    end

    it 'raises ArgumentError for an empty master_keyring when fields are present' do
      result = build_keyring_and_fields(certifier_wallet, subject_hex, plain_fields)

      expect do
        described_class.new(
          type: cert_type,
          serial_number: serial,
          subject: subject_hex,
          certifier: certifier_hex,
          revocation_outpoint: outpoint,
          fields: result[:certificate_fields],
          master_keyring: {}
        )
      end.to raise_error(ArgumentError, /Missing or empty key/)
    end
  end

  # --- Scenario 3: issue certificate then decrypt all fields with subject wallet ---

  describe '.issue_certificate_for_subject and .decrypt_fields' do
    it 'issues a signed certificate and the subject can decrypt all fields' do
      cert = issue_cert

      decrypted = described_class.decrypt_fields(
        subject_wallet,
        cert.master_keyring,
        cert.fields,
        certifier_hex
      )

      expect(decrypted).to eq(plain_fields)
    end

    it 'issues a signed certificate that verifies correctly' do
      cert = issue_cert
      expect(cert.verify).to be(true)
    end
  end

  # --- Scenario 4: nil/empty master keyring raises on decrypt ---

  describe '.decrypt_fields raises on nil/empty master_keyring' do
    it 'raises ArgumentError for nil master_keyring' do
      cert = issue_cert
      expect do
        described_class.decrypt_fields(subject_wallet, nil, cert.fields, certifier_hex)
      end.to raise_error(ArgumentError, /valid masterKeyring/)
    end

    it 'raises ArgumentError for empty master_keyring' do
      cert = issue_cert
      expect do
        described_class.decrypt_fields(subject_wallet, {}, cert.fields, certifier_hex)
      end.to raise_error(ArgumentError, /valid masterKeyring/)
    end
  end

  # --- Scenario 5: bad keyring data raises on decrypt ---

  describe '.decrypt_fields raises on tampered keyring entry' do
    it 'raises a RuntimeError when a master keyring value is corrupted' do
      cert = issue_cert
      tampered_keyring = cert.master_keyring.dup
      tampered_keyring['name'] = Base64.strict_encode64(SecureRandom.random_bytes(80))

      expect do
        described_class.decrypt_fields(subject_wallet, tampered_keyring, cert.fields, certifier_hex)
      end.to raise_error(RuntimeError, /Failed to decrypt/)
    end
  end

  # --- Scenario 6: create verifier keyring for specific fields only ---

  describe '.create_keyring_for_verifier' do
    it 'returns a keyring containing only the revealed fields' do
      cert = issue_cert(fields: { 'name' => 'Alice', 'email' => 'alice@example.com', 'age' => '30' })

      keyring = described_class.create_keyring_for_verifier(
        subject_wallet,
        certifier: certifier_hex,
        verifier: verifier_hex,
        fields: cert.fields,
        fields_to_reveal: %w[name age],
        master_keyring: cert.master_keyring,
        serial_number: cert.serial_number
      )

      expect(keyring.keys).to match_array(%w[name age])
    end
  end

  # --- Scenario 7: verifier keyring -> decrypt succeeds for revealed fields only ---
  # Note: VerifiableCertificate is implemented separately; this scenario is tested
  # here by directly replicating its decryption logic.

  describe 'verifier decrypts selectively revealed fields' do
    let(:multi_fields) { { 'name' => 'Alice', 'email' => 'alice@example.com' } }

    it 'verifier can decrypt a revealed field using the verifier-specific keyring' do
      cert = issue_cert(fields: multi_fields)

      verifier_keyring = described_class.create_keyring_for_verifier(
        subject_wallet,
        certifier: certifier_hex,
        verifier: verifier_hex,
        fields: cert.fields,
        fields_to_reveal: ['name'],
        master_keyring: cert.master_keyring,
        serial_number: cert.serial_number
      )

      # Simulate VerifiableCertificate decryption: decrypt using verifier wallet,
      # key_id = "#{serial_number} #{field_name}", counterparty = subject
      dec_args = {
        ciphertext: Base64.strict_decode64(verifier_keyring['name']).bytes,
        counterparty: subject_hex
      }.merge(BSV::Auth::Certificate.certificate_field_encryption_details('name', cert.serial_number))

      key_bytes = verifier_wallet.decrypt(**dec_args)[:plaintext]
      sym_key = BSV::Primitives::SymmetricKey.new(key_bytes.pack('C*'))
      plaintext = sym_key.decrypt(Base64.strict_decode64(cert.fields['name']))

      expect(plaintext.force_encoding('UTF-8')).to eq('Alice')
    end
  end

  # --- Scenario 8: fields_to_reveal with nonexistent field raises ---

  describe '.create_keyring_for_verifier raises on nonexistent field' do
    it 'raises ArgumentError when a field to reveal is not in the certificate' do
      cert = issue_cert

      expect do
        described_class.create_keyring_for_verifier(
          subject_wallet,
          certifier: certifier_hex,
          verifier: verifier_hex,
          fields: cert.fields,
          fields_to_reveal: ['nonexistent'],
          master_keyring: cert.master_keyring,
          serial_number: cert.serial_number
        )
      end.to raise_error(ArgumentError, /Missing the "nonexistent" field/)
    end

    it 'raises ArgumentError when fields_to_reveal is not an Array' do
      cert = issue_cert

      expect do
        described_class.create_keyring_for_verifier(
          subject_wallet,
          certifier: certifier_hex,
          verifier: verifier_hex,
          fields: cert.fields,
          fields_to_reveal: 'name',
          master_keyring: cert.master_keyring,
          serial_number: cert.serial_number
        )
      end.to raise_error(ArgumentError, /must be an array/)
    end
  end

  # --- Scenario 9: tampered master key raises ---

  describe '.decrypt_field raises on tampered master key' do
    it 'raises RuntimeError when the master key for a field is tampered' do
      cert = issue_cert

      tampered = cert.master_keyring.dup
      tampered['name'] = Base64.strict_encode64(SecureRandom.random_bytes(80))

      expect do
        described_class.decrypt_field(
          subject_wallet,
          tampered,
          'name',
          cert.fields['name'],
          certifier_hex
        )
      end.to raise_error(RuntimeError, /Failed to decrypt certificate field/)
    end
  end

  # --- Scenario 10: 'anyone' counterparty support for verifier ---

  describe ".create_keyring_for_verifier with 'anyone' verifier" do
    it "creates a keyring for an 'anyone' verifier" do
      cert = issue_cert

      keyring = described_class.create_keyring_for_verifier(
        subject_wallet,
        certifier: certifier_hex,
        verifier: 'anyone',
        fields: cert.fields,
        fields_to_reveal: ['name'],
        master_keyring: cert.master_keyring,
        serial_number: cert.serial_number
      )

      expect(keyring).to have_key('name')
    end
  end

  # --- Scenario 11: issue with custom serial number ---

  describe '.issue_certificate_for_subject with custom serial_number' do
    it 'uses the provided serial number' do
      custom_serial = Base64.strict_encode64(SecureRandom.random_bytes(32))
      cert = described_class.issue_certificate_for_subject(
        certifier_wallet,
        subject_hex,
        plain_fields,
        cert_type,
        serial_number: custom_serial
      )

      expect(cert.serial_number).to eq(custom_serial)
    end
  end

  # --- Scenario 12: self-signed certificate (subject = certifier wallet) ---

  describe 'self-signed certificate' do
    it 'certifier can issue and decrypt a self-signed certificate' do
      cert = described_class.issue_certificate_for_subject(
        certifier_wallet,
        certifier_hex,
        plain_fields,
        cert_type
      )

      decrypted = described_class.decrypt_fields(
        certifier_wallet,
        cert.master_keyring,
        cert.fields,
        'self'
      )

      expect(decrypted).to eq(plain_fields)
    end
  end

  # --- Scenario 13: 'self' as subject resolves to certifier identity key ---

  describe ".issue_certificate_for_subject with 'self' subject" do
    it "resolves 'self' to the certifier's identity key" do
      cert = described_class.issue_certificate_for_subject(
        certifier_wallet,
        'self',
        plain_fields,
        cert_type
      )

      certifier_identity = certifier_wallet.get_public_key(identity_key: true)[:public_key]
      expect(cert.subject).to eq(certifier_identity)
    end
  end

  # --- Scenario 14: explicit subject hex pubkey used as-is ---

  describe '.issue_certificate_for_subject with explicit subject hex' do
    it 'uses the provided subject pubkey hex directly' do
      cert = issue_cert(subject: subject_hex)
      expect(cert.subject).to eq(subject_hex)
    end
  end

  # --- .create_certificate_fields ---

  describe '.create_certificate_fields' do
    it 'returns certificate_fields and master_keyring with the same keys as input fields' do
      result = described_class.create_certificate_fields(
        certifier_wallet,
        subject_hex,
        plain_fields
      )

      expect(result[:certificate_fields].keys).to match_array(plain_fields.keys)
      expect(result[:master_keyring].keys).to match_array(plain_fields.keys)
    end

    it 'encrypts field values (result is Base64, not original plaintext)' do
      result = described_class.create_certificate_fields(
        certifier_wallet,
        subject_hex,
        plain_fields
      )

      plain_fields.each_key do |k|
        expect(result[:certificate_fields][k]).not_to eq(plain_fields[k])
      end
    end
  end

  # --- .from_hash ---

  describe '.from_hash' do
    it 'constructs a MasterCertificate from a hash including master_keyring' do
      cert = issue_cert
      h = cert.to_h
      restored = described_class.from_hash(h)

      expect(restored.master_keyring).to eq(cert.master_keyring)
      expect(restored.fields).to eq(cert.fields)
    end

    it 'accepts camelCase master_keyring key' do
      cert = issue_cert
      h = cert.to_h
      h['masterKeyring'] = h.delete('master_keyring')
      restored = described_class.from_hash(h)

      expect(restored.master_keyring).to eq(cert.master_keyring)
    end
  end

  # --- get_revocation_outpoint callback ---

  describe '.issue_certificate_for_subject with get_revocation_outpoint callback' do
    it 'calls the callback with the serial_number and uses the returned outpoint' do
      custom_serial = Base64.strict_encode64(SecureRandom.random_bytes(32))
      received_serial = nil

      cert = described_class.issue_certificate_for_subject(
        certifier_wallet,
        subject_hex,
        plain_fields,
        cert_type,
        get_revocation_outpoint: lambda { |sn|
          received_serial = sn
          "#{'ff' * 32}.1"
        },
        serial_number: custom_serial
      )

      expect(received_serial).to eq(custom_serial)
      expect(cert.revocation_outpoint).to eq("#{'ff' * 32}.1")
    end

    it 'uses the default placeholder outpoint when no callback given' do
      cert = issue_cert
      expect(cert.revocation_outpoint).to eq("#{'00' * 32}.0")
    end
  end
end
