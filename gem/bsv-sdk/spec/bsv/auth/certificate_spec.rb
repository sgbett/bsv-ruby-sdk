# frozen_string_literal: true

require 'spec_helper'

# TS SDK test vector (from Certificate.test.ts, lines 338-362).
# Note: the type field decodes to 21 bytes (not 32) — this vector is designed
# for testing fromObject attribute parsing only, not binary serialisation.
CERT_TS_VECTOR = {
  'type' => 'Q29tbW9uU291cmNlIGlkZW50aXR5',
  'serial_number' => 'UegX3uufsqHsbEKeBSxUd9AziLSyru86TnwfhPoZJYE=',
  'subject' => '028e2e075e1e57ba4c62c90125468109f9b4e2a7741da3dd76ccd0c73b2a8a37ad',
  'certifier' => '03c644fe2fd97673a5d86555a58587e7936390be6582ece262bc387014bcff6fe4',
  'revocation_outpoint' => '0245242bd144a85053b4c1e4a0ed5467c79a4d172680ca77a970ebabd682d564.0',
  'signature' => '304402202c86ef816c469fe657289ddea12d2c444f006ef5ab5851f00107c7724eb67ea602202786244c077567c8f3ec5da78bd61ce0c35bf1eeac0488e026c03b21c403b0fd',
  'fields' => { 'displayName' => 'eqsSpUgTKk891y1EkyCPPg+C4YoVZJvB0EQ4iore7VofkM5TB9Ctj7x2PgBaWI0A9tfATDO9' }
}.freeze

RSpec.describe BSV::Auth::Certificate do
  # --- Shared fixture ---

  let(:certifier_key)    { BSV::Primitives::PrivateKey.generate }
  let(:subject_key)      { BSV::Primitives::PrivateKey.generate }
  let(:certifier_wallet) { BSV::Wallet::ProtoWallet.new(certifier_key) }

  let(:cert_type)     { Base64.strict_encode64(SecureRandom.random_bytes(32)) }
  let(:serial)        { Base64.strict_encode64(SecureRandom.random_bytes(32)) }
  let(:subject_hex)   { subject_key.public_key.to_hex }
  let(:certifier_hex) { certifier_key.public_key.to_hex }
  let(:outpoint)      { "#{'aa' * 32}.0" }
  let(:fields)        { { 'displayName' => 'Alice', 'email' => 'alice@example.com' } }

  let(:cert) do
    described_class.new(
      type: cert_type,
      serial_number: serial,
      subject: subject_hex,
      certifier: certifier_hex,
      revocation_outpoint: outpoint,
      fields: fields
    )
  end

  # --- Scenario 1: attribute access ---

  describe '#initialize and attribute readers' do
    it 'stores all fields correctly' do
      expect(cert.type).to eq(cert_type)
      expect(cert.serial_number).to eq(serial)
      expect(cert.subject).to eq(subject_hex)
      expect(cert.certifier).to eq(certifier_hex)
      expect(cert.revocation_outpoint).to eq(outpoint)
      expect(cert.fields).to eq(fields)
      expect(cert.signature).to be_nil
    end
  end

  # --- Scenario 2 & 3: binary round-trip ---

  describe '#to_binary / .from_binary' do
    it 'round-trips without signature' do
      bin      = cert.to_binary(include_signature: false)
      restored = described_class.from_binary(bin)

      expect(restored.type).to eq(cert.type)
      expect(restored.serial_number).to eq(cert.serial_number)
      expect(restored.subject).to eq(cert.subject)
      expect(restored.certifier).to eq(cert.certifier)
      expect(restored.revocation_outpoint).to eq(cert.revocation_outpoint)
      expect(restored.fields).to eq(cert.fields)
      expect(restored.signature).to be_nil
    end

    it 'round-trips with signature after signing' do
      cert.sign(certifier_wallet)
      bin      = cert.to_binary
      restored = described_class.from_binary(bin)

      expect(restored.signature).to eq(cert.signature)
      expect(restored.type).to eq(cert.type)
      expect(restored.fields).to eq(cert.fields)
    end

    it 'to_binary omits signature when include_signature: false even if signed' do
      cert.sign(certifier_wallet)
      bin_without = cert.to_binary(include_signature: false)
      bin_with    = cert.to_binary

      expect(bin_without.bytesize).to be < bin_with.bytesize
    end
  end

  # --- Scenario 4: sign then verify ---

  describe '#sign and #verify' do
    it 'signs and verifies successfully' do
      cert.sign(certifier_wallet)
      expect(cert.signature).to be_a(String)
      expect(cert.signature).not_to be_empty
      expect(cert.verify).to be(true)
    end

    it 'sets the certifier to the signing wallet identity key' do
      cert.sign(certifier_wallet)
      expected = certifier_wallet.get_public_key({ identity_key: true })[:public_key]
      expect(cert.certifier).to eq(expected)
    end
  end

  # --- Scenario 5: tampered fields fail verification ---

  describe '#verify — tampered fields' do
    it 'returns false when a field value is altered after signing' do
      cert.sign(certifier_wallet)
      cert.fields['displayName'] = 'Eve'
      expect(cert.verify).to be(false)
    end
  end

  # --- Scenario 6: missing signature ---

  describe '#verify — missing signature' do
    it 'raises ArgumentError when no signature is present' do
      expect { cert.verify }.to raise_error(ArgumentError, /no signature/)
    end
  end

  # --- Scenario 7: incorrect signature hex ---

  describe '#verify — incorrect signature' do
    it 'returns false for a signature with a flipped byte' do
      cert.sign(certifier_wallet)
      bad_sig = cert.signature.dup
      # Flip last two nibbles (last byte) — keep it valid hex length
      last_byte = bad_sig[-2..].to_i(16) ^ 0xFF
      cert.signature = bad_sig[0...-2] + format('%02x', last_byte)
      expect(cert.verify).to be(false)
    end
  end

  # --- Scenario 8: empty fields ---

  describe 'empty fields hash' do
    let(:empty_cert) do
      described_class.new(
        type: cert_type,
        serial_number: serial,
        subject: subject_hex,
        certifier: certifier_hex,
        revocation_outpoint: outpoint,
        fields: {}
      )
    end

    it 'serialises and deserialises with zero fields' do
      bin      = empty_cert.to_binary(include_signature: false)
      restored = described_class.from_binary(bin)
      expect(restored.fields).to eq({})
    end

    it 'signs, serialises, deserialises, and verifies with empty fields' do
      empty_cert.sign(certifier_wallet)
      bin      = empty_cert.to_binary
      restored = described_class.from_binary(bin)
      expect(restored.verify).to be(true)
    end
  end

  # --- Scenario 9: exclude signature, deserialise → nil signature ---

  describe '.from_binary on binary without signature' do
    it 'produces a certificate with nil signature' do
      cert.sign(certifier_wallet)
      bin_without = cert.to_binary(include_signature: false)
      restored    = described_class.from_binary(bin_without)
      expect(restored.signature).to be_nil
    end
  end

  # --- Scenario 10: long field names and values ---

  describe 'long field names and values' do
    let(:long_fields) do
      {
        'a_very_long_field_name_that_exceeds_fifty_bytes_in_utf8_encoding' => 'x' * 500,
        'normal' => 'y' * 200
      }
    end

    let(:long_cert) do
      described_class.new(
        type: cert_type,
        serial_number: serial,
        subject: subject_hex,
        certifier: certifier_hex,
        revocation_outpoint: outpoint,
        fields: long_fields
      )
    end

    it 'round-trips long fields' do
      bin      = long_cert.to_binary(include_signature: false)
      restored = described_class.from_binary(bin)
      expect(restored.fields).to eq(long_fields)
    end

    it 'signs, serialises, deserialises, and verifies with long fields' do
      long_cert.sign(certifier_wallet)
      bin      = long_cert.to_binary
      restored = described_class.from_binary(bin)
      expect(restored.verify).to be(true)
    end
  end

  # --- Scenario 11: revocation outpoint round-trip ---

  describe 'revocation outpoint' do
    it 'preserves txid and output index through round-trip' do
      txid     = 'ab' * 32
      outpoint = "#{txid}.42"
      c = described_class.new(
        type: cert_type,
        serial_number: serial,
        subject: subject_hex,
        certifier: certifier_hex,
        revocation_outpoint: outpoint,
        fields: {}
      )
      bin      = c.to_binary(include_signature: false)
      restored = described_class.from_binary(bin)
      expect(restored.revocation_outpoint).to eq(outpoint)
    end
  end

  # --- Scenario 12: already-signed raises; mismatched certifier auto-updates ---

  describe '#sign edge cases' do
    it 'raises ArgumentError when trying to sign an already-signed certificate' do
      cert.sign(certifier_wallet)
      expect { cert.sign(certifier_wallet) }.to raise_error(ArgumentError, /already been signed/)
    end

    it 'overwrites a mismatched certifier field with the wallet identity key' do
      cert_with_wrong_certifier = described_class.new(
        type: cert_type,
        serial_number: serial,
        subject: subject_hex,
        certifier: "02#{'00' * 32}",
        revocation_outpoint: outpoint,
        fields: fields
      )
      cert_with_wrong_certifier.sign(certifier_wallet)
      expected = certifier_wallet.get_public_key({ identity_key: true })[:public_key]
      expect(cert_with_wrong_certifier.certifier).to eq(expected)
    end
  end

  # --- Scenario 13: from_hash / to_h ---

  describe '.from_hash and #to_h' do
    it 'constructs correctly from a snake_case hash without signature' do
      h = {
        'type' => cert_type,
        'serial_number' => serial,
        'subject' => subject_hex,
        'certifier' => certifier_hex,
        'revocation_outpoint' => outpoint,
        'fields' => fields
      }
      c = described_class.from_hash(h)
      expect(c.type).to eq(cert_type)
      expect(c.fields).to eq(fields)
      expect(c.signature).to be_nil
    end

    it 'constructs correctly from a hash with a signature' do
      cert.sign(certifier_wallet)
      c = described_class.from_hash(cert.to_h)
      expect(c.signature).to eq(cert.signature)
    end

    it 'constructs correctly from TS SDK camelCase hash' do
      ts_hash = {
        'type' => cert_type,
        'serialNumber' => serial,
        'subject' => subject_hex,
        'certifier' => certifier_hex,
        'revocationOutpoint' => outpoint,
        'fields' => fields
      }
      c = described_class.from_hash(ts_hash)
      expect(c.serial_number).to eq(serial)
      expect(c.revocation_outpoint).to eq(outpoint)
    end

    it 'to_h / from_hash round-trips without data loss' do
      cert.sign(certifier_wallet)
      c2 = described_class.from_hash(cert.to_h)
      expect(c2.to_h).to eq(cert.to_h)
    end
  end

  # --- TS SDK test vector ---

  describe '.from_hash with TS SDK test vector' do
    let(:ts_cert) { described_class.from_hash(CERT_TS_VECTOR) }

    it 'parses type correctly' do
      expect(ts_cert.type).to eq(CERT_TS_VECTOR['type'])
    end

    it 'parses serial_number correctly' do
      expect(ts_cert.serial_number).to eq(CERT_TS_VECTOR['serial_number'])
    end

    it 'parses subject correctly' do
      expect(ts_cert.subject).to eq(CERT_TS_VECTOR['subject'])
    end

    it 'parses certifier correctly' do
      expect(ts_cert.certifier).to eq(CERT_TS_VECTOR['certifier'])
    end

    it 'parses revocation_outpoint correctly' do
      expect(ts_cert.revocation_outpoint).to eq(CERT_TS_VECTOR['revocation_outpoint'])
    end

    it 'parses fields correctly' do
      expect(ts_cert.fields).to eq(CERT_TS_VECTOR['fields'])
    end

    it 'parses signature correctly' do
      expect(ts_cert.signature).to eq(CERT_TS_VECTOR['signature'])
    end

    # The TS fromObject test vector uses a non-standard type field that is only
    # 21 bytes when base64-decoded (not the standard 32 bytes). The vector is
    # designed to test field-level attribute parsing only — the TS test suite
    # itself never calls toBinary on this object. Binary round-trip tests use
    # properly-generated 32-byte type and serial_number values instead.
    it 'parses all fields and reconstructs a matching hash' do
      expect(ts_cert.to_h.reject { |k, _| k == 'signature' }).to eq(CERT_TS_VECTOR.reject { |k, _| k == 'signature' })
    end
  end

  # --- .certificate_field_encryption_details ---

  describe '.certificate_field_encryption_details' do
    it 'returns the certificate field encryption protocol' do
      result = described_class.certificate_field_encryption_details('email')
      expect(result[:protocol_id]).to eq([2, 'certificate field encryption'])
    end

    it 'returns just the field name as key_id when no serial number given' do
      result = described_class.certificate_field_encryption_details('email')
      expect(result[:key_id]).to eq('email')
    end

    it 'prefixes key_id with serial number when provided' do
      result = described_class.certificate_field_encryption_details('email', 'SN123')
      expect(result[:key_id]).to eq('SN123 email')
    end
  end
end
