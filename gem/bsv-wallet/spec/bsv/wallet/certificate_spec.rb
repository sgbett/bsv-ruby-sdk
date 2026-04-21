# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'securerandom'
require 'base64'

STORE_FACTORIES.each do |store_label, store_factory|
  RSpec.describe "Client certificate methods (#{store_label})" do
    let(:private_key) { BSV::Primitives::PrivateKey.generate }
    let(:wallet) { BSV::Wallet::Client.new(private_key, storage: store_factory.call, allow_memory_store: true) }
    let(:certifier_key) { BSV::Primitives::PrivateKey.generate }
    let(:certifier_hex) { certifier_key.public_key.to_hex }
    let(:certifier_wallet) { BSV::Wallet::Client.new(certifier_key, storage: store_factory.call, allow_memory_store: true) }

    let(:cert_type) { Base64.strict_encode64(SecureRandom.random_bytes(32)) }
    let(:serial_number) { Base64.strict_encode64(SecureRandom.random_bytes(32)) }
    let(:revocation_outpoint) { "#{'ab' * 32}.0" }

    let(:fields) { { 'name' => 'Alice', 'email' => 'alice@example.com' } }
    let(:keyring) { { 'name' => Base64.strict_encode64('key1'), 'email' => Base64.strict_encode64('key2') } }

    # Compute a valid BRC-52 certifier signature over the canonical preimage.
    # The certifier signs with counterparty 'anyone' so any verifier deriving
    # against counterparty=certifier_hex can reconstruct the same public key.
    let(:signature) do
      preimage = BSV::Wallet::CertificateSignature.serialise_preimage(
        type: cert_type,
        serial_number: serial_number,
        subject: wallet.key_deriver.identity_key,
        certifier: certifier_hex,
        revocation_outpoint: revocation_outpoint,
        fields: fields
      )
      result = certifier_wallet.create_signature({
                                                   data: preimage.unpack('C*'),
                                                   protocol_id: [2, 'certificate signature'],
                                                   key_id: "#{cert_type} #{serial_number}",
                                                   counterparty: 'anyone'
                                                 })
      result[:signature].pack('C*').unpack1('H*')
    end

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

      # Regression for https://github.com/sgbett/bsv-ruby-sdk/issues/305 (F8.15)
      #
      # Prior to this fix, `acquire_via_direct` wrote user-supplied certificate
      # fields to storage without verifying the certifier's signature. A caller
      # could pass any value as `args[:signature]` and it would be persisted as
      # authentic. `list_certificates` and `prove_certificate` then treated the
      # record as valid, producing a credential forgery primitive.
      describe 'BRC-52 certifier signature verification (issue #305)' do
        it 'rejects a certificate with an invalid signature' do
          tampered = direct_args.merge(signature: 'ff' * 70)

          expect { wallet.acquire_certificate(tampered) }
            .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)
        end

        it 'rejects a certificate whose fields have been tampered with after signing' do
          tampered = direct_args.merge(fields: fields.merge('email' => 'attacker@example.com'))

          expect { wallet.acquire_certificate(tampered) }
            .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)
        end

        it 'rejects a certificate whose subject is overridden' do
          # The wallet always sets subject to its own identity key, so changing
          # the subject in args has no effect — but if the signature was made
          # over a different subject, the preimage hash won't match.
          other_wallet_signature = begin
            other_key = BSV::Primitives::PrivateKey.generate
            preimage = BSV::Wallet::CertificateSignature.serialise_preimage(
              type: cert_type,
              serial_number: serial_number,
              subject: other_key.public_key.to_hex,
              certifier: certifier_hex,
              revocation_outpoint: revocation_outpoint,
              fields: fields
            )
            result = certifier_wallet.create_signature({
                                                         data: preimage.unpack('C*'),
                                                         protocol_id: [2, 'certificate signature'],
                                                         key_id: "#{cert_type} #{serial_number}",
                                                         counterparty: 'anyone'
                                                       })
            result[:signature].pack('C*').unpack1('H*')
          end

          tampered = direct_args.merge(signature: other_wallet_signature)

          expect { wallet.acquire_certificate(tampered) }
            .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)
        end

        it 'rejects a certificate signed by a different certifier' do
          imposter_key = BSV::Primitives::PrivateKey.generate
          imposter_wallet = BSV::Wallet::Client.new(imposter_key, storage: store_factory.call, allow_memory_store: true)
          preimage = BSV::Wallet::CertificateSignature.serialise_preimage(
            type: cert_type,
            serial_number: serial_number,
            subject: wallet.key_deriver.identity_key,
            certifier: certifier_hex, # claims to be from the real certifier
            revocation_outpoint: revocation_outpoint,
            fields: fields
          )
          imposter_sig = imposter_wallet.create_signature({
                                                            data: preimage.unpack('C*'),
                                                            protocol_id: [2, 'certificate signature'],
                                                            key_id: "#{cert_type} #{serial_number}",
                                                            counterparty: 'anyone'
                                                          })[:signature].pack('C*').unpack1('H*')

          tampered = direct_args.merge(signature: imposter_sig)

          expect { wallet.acquire_certificate(tampered) }
            .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)
        end

        it 'rejects a certificate with a malformed (non-hex) signature' do
          tampered = direct_args.merge(signature: 'not hex at all')

          expect { wallet.acquire_certificate(tampered) }
            .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)
        end

        it 'does not persist an unverified certificate to storage' do
          tampered = direct_args.merge(signature: 'ff' * 70)

          expect { wallet.acquire_certificate(tampered) }
            .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)

          certs = wallet.list_certificates({ certifiers: [certifier_hex], types: [cert_type] })
          expect(certs[:total_certificates]).to eq(0)
        end
      end

      # Follow-up hardening from PR #306 review.
      describe 'CertificateSignature input validation (#306 review)' do
        # #2 — strict base64 decode
        it 'rejects a certificate whose type has whitespace-injected base64' do
          # strict_decode64 rejects whitespace; decode64 would have accepted it.
          # The decoded length would still be 32 bytes here, which is exactly
          # the silent-corruption case strict_decode64 closes.
          raw32 = "\x01".b * 32
          valid_type = Base64.strict_encode64(raw32)
          whitespace_injected = valid_type.chars.each_slice(8).map(&:join).join("\n")

          tampered = direct_args.merge(type: whitespace_injected)

          expect { wallet.acquire_certificate(tampered) }
            .to raise_error(BSV::Wallet::CertificateSignature::InvalidError, /base64/)
        end

        it 'rejects a certificate whose serial_number has non-base64 characters' do
          tampered = direct_args.merge(serial_number: 'not valid base64!!@#$%^&*()_+|')

          expect { wallet.acquire_certificate(tampered) }
            .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)
        end

        # #3 — EncodingError → InvalidError
        it 'rejects a certificate with non-UTF-8 bytes in a field value as InvalidError' do
          # A lone 0x80 byte is invalid UTF-8 (continuation byte with no lead).
          bad_field_value = "\x80".b
          tampered = direct_args.merge(fields: fields.merge('email' => bad_field_value))

          # Without the EncodingError rescue, this would leak
          # Encoding::InvalidByteSequenceError / UndefinedConversionError.
          expect { wallet.acquire_certificate(tampered) }
            .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)
        end

        # #4 — duplicate field names
        it 'rejects fields containing both symbol and string forms of the same name' do
          ambiguous = { 'email' => 'one@example.com', email: 'two@example.com' }
          tampered = direct_args.merge(fields: ambiguous)

          expect { wallet.acquire_certificate(tampered) }
            .to raise_error(BSV::Wallet::CertificateSignature::InvalidError, /duplicate field name/)
        end

        # #6 — hex_to_bytes even-length guard
        it 'rejects an odd-length signature hex' do
          # Chop one hex nibble off an otherwise valid signature.
          tampered = direct_args.merge(signature: signature[0...-1])

          expect { wallet.acquire_certificate(tampered) }
            .to raise_error(BSV::Wallet::CertificateSignature::InvalidError, /even/)
        end
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
        let(:issuance_response_body) do
          JSON.generate({
                          'type' => cert_type,
                          'subject' => wallet.key_deriver.identity_key,
                          'serialNumber' => serial_number,
                          'certifier' => certifier_hex,
                          'revocationOutpoint' => revocation_outpoint,
                          'signature' => signature,
                          'fields' => fields,
                          'keyringForSubject' => keyring
                        })
        end

        let(:mock_auth_response) do
          BSV::Auth::AuthResponse.new(
            status: 200,
            headers: {},
            body: issuance_response_body,
            identity_key: certifier_hex
          )
        end

        let(:mock_auth_fetch) do
          # rubocop:disable RSpec/VerifiedDoubles
          double('auth_fetch', fetch: mock_auth_response)
          # rubocop:enable RSpec/VerifiedDoubles
        end

        let(:issuance_wallet) do
          w = BSV::Wallet::Client.new(private_key, storage: store_factory.call, allow_memory_store: true)
          allow(w).to receive(:auth_fetch_client).and_return(mock_auth_fetch)
          w
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

        it 'calls AuthFetch#fetch with correct URL, method, headers, and body' do
          expected_body = JSON.generate({
                                          type: cert_type,
                                          subject: issuance_wallet.key_deriver.identity_key,
                                          certifier: certifier_hex,
                                          fields: fields
                                        })
          allow(mock_auth_fetch).to receive(:fetch).and_return(mock_auth_response)
          issuance_wallet.acquire_certificate(issuance_args)
          expect(mock_auth_fetch).to have_received(:fetch).with(
            'https://certifier.example.com/api/issue',
            method: 'POST',
            headers: { 'content-type' => 'application/json' },
            body: expected_body
          )
        end

        it 'raises WalletError on HTTP failure' do
          # rubocop:disable RSpec/VerifiedDoubles
          failing_auth_fetch = double('auth_fetch')
          # rubocop:enable RSpec/VerifiedDoubles
          allow(failing_auth_fetch).to receive(:fetch).and_return(
            BSV::Auth::AuthResponse.new(status: 500, headers: {}, body: 'error', identity_key: certifier_hex)
          )
          w = BSV::Wallet::Client.new(private_key, storage: store_factory.call, allow_memory_store: true)
          allow(w).to receive(:auth_fetch_client).and_return(failing_auth_fetch)
          expect { w.acquire_certificate(issuance_args) }.to raise_error(BSV::Wallet::WalletError, /HTTP 500/)
        end

        it 'raises WalletError on invalid JSON response' do
          # rubocop:disable RSpec/VerifiedDoubles
          bad_auth_fetch = double('auth_fetch')
          # rubocop:enable RSpec/VerifiedDoubles
          allow(bad_auth_fetch).to receive(:fetch).and_return(
            BSV::Auth::AuthResponse.new(status: 200, headers: {}, body: 'not json', identity_key: certifier_hex)
          )
          w = BSV::Wallet::Client.new(private_key, storage: store_factory.call, allow_memory_store: true)
          allow(w).to receive(:auth_fetch_client).and_return(bad_auth_fetch)
          expect { w.acquire_certificate(issuance_args) }.to raise_error(BSV::Wallet::WalletError, /invalid JSON/)
        end

        it 'verifies the certifier signature on the issuance response' do
          # rubocop:disable RSpec/VerifiedDoubles
          tampered_auth_fetch = double('auth_fetch')
          # rubocop:enable RSpec/VerifiedDoubles
          tampered_body = JSON.generate({
                                          'type' => cert_type,
                                          'serialNumber' => serial_number,
                                          'revocationOutpoint' => revocation_outpoint,
                                          'signature' => 'ff' * 70,
                                          'fields' => fields
                                        })
          allow(tampered_auth_fetch).to receive(:fetch).and_return(
            BSV::Auth::AuthResponse.new(status: 200, headers: {}, body: tampered_body, identity_key: certifier_hex)
          )
          w = BSV::Wallet::Client.new(private_key, storage: store_factory.call, allow_memory_store: true)
          allow(w).to receive(:auth_fetch_client).and_return(tampered_auth_fetch)
          expect { w.acquire_certificate(issuance_args) }
            .to raise_error(BSV::Wallet::CertificateSignature::InvalidError)
        end

        it 'lazily initialises auth_fetch_client on first call and memoises it' do
          w = BSV::Wallet::Client.new(private_key, storage: store_factory.call, allow_memory_store: true)
          allow(BSV::Auth::AuthFetch).to receive(:new).and_call_original
          client1 = w.send(:auth_fetch_client)
          client2 = w.send(:auth_fetch_client)
          expect(client1).to be(client2)
          expect(BSV::Auth::AuthFetch).to have_received(:new).once
        end

        it 'passes self as the wallet to AuthFetch' do
          w = BSV::Wallet::Client.new(private_key, storage: store_factory.call, allow_memory_store: true)
          allow(BSV::Auth::AuthFetch).to receive(:new).and_call_original
          w.send(:auth_fetch_client)
          expect(BSV::Auth::AuthFetch).to have_received(:new).with(wallet: w)
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
        verifier_wallet = BSV::Wallet::Client.new(verifier_key, storage: store_factory.call, allow_memory_store: true)
        prover_identity = wallet.key_deriver.identity_key

        result = wallet.prove_certificate({
                                            certificate: { type: cert_type, serial_number: serial_number, certifier: certifier_hex },
                                            fields_to_reveal: ['name'],
                                            verifier: verifier_hex
                                          })

        decrypted = verifier_wallet.decrypt({
                                              ciphertext: result[:keyring_for_verifier]['name'],
                                              protocol_id: [2, 'certificate field encryption'],
                                              key_id: "#{serial_number} name",
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
end
