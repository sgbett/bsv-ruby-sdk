# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'securerandom'
require 'base64'

RSpec.describe 'WalletClient certificate methods' do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:wallet) { BSV::Wallet::WalletClient.new(private_key, storage: BSV::Wallet::MemoryStore.new) }
  let(:certifier_key) { BSV::Primitives::PrivateKey.generate }
  let(:certifier_hex) { certifier_key.public_key.to_hex }

  let(:cert_type) { Base64.strict_encode64(SecureRandom.random_bytes(32)) }
  let(:serial_number) { Base64.strict_encode64(SecureRandom.random_bytes(32)) }
  let(:revocation_outpoint) { "#{'ab' * 32}.0" }
  let(:signature) { 'deadbeef' * 8 }

  let(:fields) { { 'name' => 'Alice', 'email' => 'alice@example.com' } }
  let(:keyring) { { 'name' => Base64.strict_encode64('key1'), 'email' => Base64.strict_encode64('key2') } }

  let(:direct_args) do
    {
      type: cert_type,
      certifier: certifier_hex,
      acquisition_protocol: 'direct',
      fields: fields,
      serial_number: serial_number,
      revocation_outpoint: revocation_outpoint,
      signature: signature,
      keyring_revealer: 'certifier',
      keyring_for_subject: keyring
    }
  end

  # -------------------------------------------------------------------------
  # acquire_certificate
  # -------------------------------------------------------------------------
  describe '#acquire_certificate' do
    it 'stores and returns a direct certificate' do
      result = wallet.acquire_certificate(direct_args)
      expect(result[:type]).to eq(cert_type)
      expect(result[:subject]).to eq(wallet.key_deriver.identity_key)
      expect(result[:serial_number]).to eq(serial_number)
      expect(result[:certifier]).to eq(certifier_hex)
      expect(result[:fields]).to eq(fields)
    end

    it 'does not return the keyring in the result' do
      result = wallet.acquire_certificate(direct_args)
      expect(result).not_to have_key(:keyring)
    end

    it 'raises InvalidParameterError for issuance without certifier_url' do
      args = direct_args.merge(acquisition_protocol: 'issuance')
      args.delete(:serial_number)
      args.delete(:revocation_outpoint)
      args.delete(:signature)
      args.delete(:keyring_for_subject)
      expect { wallet.acquire_certificate(args) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    context 'with issuance protocol' do
      let(:issuance_response) do
        {
          'type' => cert_type,
          'subject' => wallet.key_deriver.identity_key,
          'serialNumber' => serial_number,
          'certifier' => certifier_hex,
          'revocationOutpoint' => revocation_outpoint,
          'signature' => signature,
          'fields' => fields,
          'keyringForSubject' => keyring
        }
      end

      let(:mock_http) do
        resp = issuance_response
        Class.new do
          define_method(:request) do |_uri, _req|
            Struct.new(:code, :body).new('200', JSON.generate(resp))
          end
        end.new
      end

      let(:issuance_wallet) do
        BSV::Wallet::WalletClient.new(private_key, storage: BSV::Wallet::MemoryStore.new, http_client: mock_http)
      end

      let(:issuance_args) do
        {
          type: cert_type,
          certifier: certifier_hex,
          acquisition_protocol: 'issuance',
          fields: fields,
          certifier_url: 'https://certifier.example.com/api/issue'
        }
      end

      it 'acquires a certificate via issuance protocol' do
        result = issuance_wallet.acquire_certificate(issuance_args)
        expect(result[:type]).to eq(cert_type)
        expect(result[:subject]).to eq(wallet.key_deriver.identity_key)
        expect(result[:serial_number]).to eq(serial_number)
        expect(result[:certifier]).to eq(certifier_hex)
      end

      it 'does not return the keyring in the result' do
        result = issuance_wallet.acquire_certificate(issuance_args)
        expect(result).not_to have_key(:keyring)
      end

      it 'stores the certificate in storage' do
        issuance_wallet.acquire_certificate(issuance_args)
        certs = issuance_wallet.list_certificates({ certifiers: [certifier_hex], types: [cert_type] })
        expect(certs[:total_certificates]).to eq(1)
      end

      it 'raises WalletError on HTTP failure' do
        failing_http = Class.new do
          define_method(:request) { |_uri, _req| Struct.new(:code, :body).new('500', 'error') }
        end.new
        w = BSV::Wallet::WalletClient.new(private_key, storage: BSV::Wallet::MemoryStore.new, http_client: failing_http)
        expect { w.acquire_certificate(issuance_args) }.to raise_error(BSV::Wallet::WalletError, /HTTP 500/)
      end

      it 'raises WalletError on invalid JSON response' do
        bad_http = Class.new do
          define_method(:request) { |_uri, _req| Struct.new(:code, :body).new('200', 'not json') }
        end.new
        w = BSV::Wallet::WalletClient.new(private_key, storage: BSV::Wallet::MemoryStore.new, http_client: bad_http)
        expect { w.acquire_certificate(issuance_args) }.to raise_error(BSV::Wallet::WalletError, /invalid JSON/)
      end
    end

    it 'raises InvalidParameterError for invalid protocol' do
      args = direct_args.merge(acquisition_protocol: 'unknown')
      expect { wallet.acquire_certificate(args) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError when missing required direct fields' do
      %i[serial_number revocation_outpoint signature keyring_for_subject].each do |field|
        args = direct_args.dup
        args.delete(field)
        expect { wallet.acquire_certificate(args) }.to raise_error(BSV::Wallet::InvalidParameterError)
      end
    end

    it 'raises InvalidParameterError for invalid certifier' do
      args = direct_args.merge(certifier: 'bad')
      expect { wallet.acquire_certificate(args) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  # -------------------------------------------------------------------------
  # list_certificates
  # -------------------------------------------------------------------------
  describe '#list_certificates' do
    before { wallet.acquire_certificate(direct_args) }

    it 'lists certificates by certifier and type' do
      result = wallet.list_certificates({ certifiers: [certifier_hex], types: [cert_type] })
      expect(result[:total_certificates]).to eq(1)
      expect(result[:certificates].first[:serial_number]).to eq(serial_number)
    end

    it 'does not include the keyring' do
      result = wallet.list_certificates({ certifiers: [certifier_hex], types: [cert_type] })
      expect(result[:certificates].first).not_to have_key(:keyring)
    end

    it 'returns empty when no match' do
      result = wallet.list_certificates({ certifiers: ['aa' * 33], types: [cert_type] })
      expect(result[:total_certificates]).to eq(0)
      expect(result[:certificates]).to be_empty
    end

    it 'raises InvalidParameterError for missing certifiers' do
      expect { wallet.list_certificates({ types: [cert_type] }) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end

    it 'raises InvalidParameterError for missing types' do
      expect { wallet.list_certificates({ certifiers: [certifier_hex] }) }.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  # -------------------------------------------------------------------------
  # prove_certificate
  # -------------------------------------------------------------------------
  describe '#prove_certificate' do
    let(:verifier_key) { BSV::Primitives::PrivateKey.generate }
    let(:verifier_hex) { verifier_key.public_key.to_hex }

    before { wallet.acquire_certificate(direct_args) }

    it 'returns encrypted keyring entries for the verifier' do
      result = wallet.prove_certificate({
                                          certificate: { type: cert_type, serial_number: serial_number, certifier: certifier_hex },
                                          fields_to_reveal: ['name'],
                                          verifier: verifier_hex
                                        })
      expect(result[:keyring_for_verifier]).to have_key('name')
      expect(result[:keyring_for_verifier]['name']).to be_a(Array)
    end

    it 'encrypts multiple fields when requested' do
      result = wallet.prove_certificate({
                                          certificate: { type: cert_type, serial_number: serial_number, certifier: certifier_hex },
                                          fields_to_reveal: %w[name email],
                                          verifier: verifier_hex
                                        })
      expect(result[:keyring_for_verifier].keys).to contain_exactly('name', 'email')
    end

    it 'allows the verifier to decrypt the keyring entry' do
      verifier_wallet = BSV::Wallet::WalletClient.new(verifier_key, storage: BSV::Wallet::MemoryStore.new)
      prover_identity = wallet.key_deriver.identity_key

      result = wallet.prove_certificate({
                                          certificate: { type: cert_type, serial_number: serial_number, certifier: certifier_hex },
                                          fields_to_reveal: ['name'],
                                          verifier: verifier_hex
                                        })

      decrypted = verifier_wallet.decrypt({
                                            ciphertext: result[:keyring_for_verifier]['name'],
                                            protocol_id: [2, 'certificate field revelation'],
                                            key_id: "#{cert_type} #{serial_number} name",
                                            counterparty: prover_identity
                                          })
      expect(decrypted[:plaintext].pack('C*')).to eq(keyring['name'])
    end

    it 'raises WalletError when certificate not found' do
      expect do
        wallet.prove_certificate({
                                   certificate: { type: 'nonexistent', serial_number: 'x', certifier: certifier_hex },
                                   fields_to_reveal: ['name'],
                                   verifier: verifier_hex
                                 })
      end.to raise_error(BSV::Wallet::WalletError)
    end

    it 'raises InvalidParameterError for invalid verifier' do
      expect do
        wallet.prove_certificate({
                                   certificate: { type: cert_type, serial_number: serial_number, certifier: certifier_hex },
                                   fields_to_reveal: ['name'],
                                   verifier: 'bad'
                                 })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  # -------------------------------------------------------------------------
  # relinquish_certificate
  # -------------------------------------------------------------------------
  describe '#relinquish_certificate' do
    before { wallet.acquire_certificate(direct_args) }

    it 'removes the certificate and returns relinquished: true' do
      result = wallet.relinquish_certificate({ type: cert_type, serial_number: serial_number, certifier: certifier_hex })
      expect(result[:relinquished]).to be true

      listed = wallet.list_certificates({ certifiers: [certifier_hex], types: [cert_type] })
      expect(listed[:total_certificates]).to eq(0)
    end

    it 'raises WalletError when certificate not found' do
      expect do
        wallet.relinquish_certificate({ type: 'nonexistent', serial_number: 'x', certifier: certifier_hex })
      end.to raise_error(BSV::Wallet::WalletError)
    end
  end

  # -------------------------------------------------------------------------
  # discover_by_identity_key
  # -------------------------------------------------------------------------
  describe '#discover_by_identity_key' do
    before { wallet.acquire_certificate(direct_args) }

    it 'finds certificates for the wallet identity key' do
      result = wallet.discover_by_identity_key({ identity_key: wallet.key_deriver.identity_key })
      expect(result[:total_certificates]).to eq(1)
      expect(result[:certificates].first[:type]).to eq(cert_type)
    end

    it 'returns empty for an unknown identity key' do
      other_key = BSV::Primitives::PrivateKey.generate.public_key.to_hex
      result = wallet.discover_by_identity_key({ identity_key: other_key })
      expect(result[:total_certificates]).to eq(0)
    end

    it 'does not include the keyring' do
      result = wallet.discover_by_identity_key({ identity_key: wallet.key_deriver.identity_key })
      expect(result[:certificates].first).not_to have_key(:keyring)
    end

    it 'raises InvalidParameterError for invalid identity key' do
      expect do
        wallet.discover_by_identity_key({ identity_key: 'bad' })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end

  # -------------------------------------------------------------------------
  # discover_by_attributes
  # -------------------------------------------------------------------------
  describe '#discover_by_attributes' do
    before { wallet.acquire_certificate(direct_args) }

    it 'finds certificates matching field values' do
      result = wallet.discover_by_attributes({ attributes: { 'name' => 'Alice' } })
      expect(result[:total_certificates]).to eq(1)
    end

    it 'returns empty when no fields match' do
      result = wallet.discover_by_attributes({ attributes: { 'name' => 'Bob' } })
      expect(result[:total_certificates]).to eq(0)
    end

    it 'raises InvalidParameterError for empty attributes' do
      expect do
        wallet.discover_by_attributes({ attributes: {} })
      end.to raise_error(BSV::Wallet::InvalidParameterError)
    end
  end
end
