# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module BSV
  module Wallet
    class Client
      module IdentityOps
        # Acquires an identity certificate via direct storage or issuance.
        #
        # @param args [Hash]
        # @return [Hash] the stored certificate
        def acquire_certificate(args, originator: nil)
          return @substrate.acquire_certificate(args, originator: originator) if @substrate

          validate_acquire_certificate!(args)

          cert = if args[:acquisition_protocol] == 'issuance'
                   acquire_via_issuance(args)
                 else
                   acquire_via_direct(args)
                 end

          @storage.store_certificate(cert)
          cert_without_keyring(cert)
        end

        # Lists identity certificates filtered by certifier and type.
        #
        # @param args [Hash]
        # @return [Hash] { total_certificates:, certificates: [...] }
        def list_certificates(args, originator: nil)
          return @substrate.list_certificates(args, originator: originator) if @substrate

          raise InvalidParameterError.new('certifiers', 'a non-empty Array') unless args[:certifiers].is_a?(Array) && !args[:certifiers].empty?
          raise InvalidParameterError.new('types', 'a non-empty Array') unless args[:types].is_a?(Array) && !args[:types].empty?

          query = {
            certifiers: args[:certifiers],
            types: args[:types],
            limit: args[:limit] || 10,
            offset: args[:offset] || 0
          }
          total = @storage.count_certificates(query)
          certs = @storage.find_certificates(query)
          { total_certificates: total, certificates: certs.map { |c| cert_without_keyring(c) } }
        end

        # Proves select fields of an identity certificate to a verifier.
        #
        # @param args [Hash]
        # @return [Hash] { keyring_for_verifier: { field_name => Array<Integer> } }
        def prove_certificate(args, originator: nil)
          return @substrate.prove_certificate(args, originator: originator) if @substrate

          cert_arg = args[:certificate]
          fields_to_reveal = args[:fields_to_reveal]
          verifier = args[:verifier]

          raise InvalidParameterError.new('certificate', 'a Hash') unless cert_arg.is_a?(Hash)
          raise InvalidParameterError.new('fields_to_reveal', 'a non-empty Array') unless fields_to_reveal.is_a?(Array) && !fields_to_reveal.empty?

          Validators.validate_pub_key_hex!(verifier, 'verifier')

          stored = find_stored_certificate(cert_arg)
          raise WalletError, 'Certificate not found in wallet' unless stored
          raise WalletError, 'Certificate has no keyring' unless stored[:keyring]

          keyring_for_verifier = {}
          fields_to_reveal.each do |field_name|
            key_value = stored[:keyring][field_name] || stored[:keyring][field_name.to_sym]
            raise WalletError, "Keyring entry not found for field '#{field_name}'" unless key_value

            encrypted = encrypt({
                                  plaintext: key_value.bytes,
                                  protocol_id: [2, 'certificate field encryption'],
                                  key_id: "#{cert_arg[:serial_number]} #{field_name}",
                                  counterparty: verifier
                                })
            keyring_for_verifier[field_name] = encrypted[:ciphertext]
          end

          { keyring_for_verifier: keyring_for_verifier }
        end

        # Removes a certificate from the wallet.
        #
        # @param args [Hash]
        # @return [Hash] { relinquished: true }
        def relinquish_certificate(args, originator: nil)
          return @substrate.relinquish_certificate(args, originator: originator) if @substrate

          deleted = @storage.delete_certificate(
            type: args[:type],
            serial_number: args[:serial_number],
            certifier: args[:certifier]
          )
          raise WalletError, 'Certificate not found' unless deleted

          { relinquished: true }
        end

        # Discovers certificates issued to a given identity key.
        #
        # @param args [Hash]
        # @return [Hash] { total_certificates:, certificates: [...] }
        def discover_by_identity_key(args, originator: nil)
          return @substrate.discover_by_identity_key(args, originator: originator) if @substrate

          Validators.validate_pub_key_hex!(args[:identity_key], 'identity_key')

          query = { subject: args[:identity_key], limit: args[:limit] || 10, offset: args[:offset] || 0 }
          total = @storage.count_certificates(query)
          certs = @storage.find_certificates(query)
          { total_certificates: total, certificates: certs.map { |c| cert_without_keyring(c) } }
        end

        # Discovers certificates matching specific attribute values.
        #
        # @param args [Hash]
        # @return [Hash] { total_certificates:, certificates: [...] }
        def discover_by_attributes(args, originator: nil)
          return @substrate.discover_by_attributes(args, originator: originator) if @substrate

          raise InvalidParameterError.new('attributes', 'a non-empty Hash') unless args[:attributes].is_a?(Hash) && !args[:attributes].empty?

          query = { attributes: args[:attributes], limit: args[:limit] || 10, offset: args[:offset] || 0 }
          total = @storage.count_certificates(query)
          certs = @storage.find_certificates(query)
          { total_certificates: total, certificates: certs.map { |c| cert_without_keyring(c) } }
        end

        private

        def validate_acquire_certificate!(args)
          raise InvalidParameterError.new('type', 'a String') unless args[:type].is_a?(String)

          Validators.validate_pub_key_hex!(args[:certifier], 'certifier')
          raise InvalidParameterError.new('fields', 'a Hash') unless args[:fields].is_a?(Hash)

          protocol = args[:acquisition_protocol]
          raise InvalidParameterError.new('acquisition_protocol', '"direct" or "issuance"') unless %w[direct issuance].include?(protocol)

          if protocol == 'direct'
            raise InvalidParameterError.new('serial_number', 'present for direct acquisition') unless args[:serial_number]
            raise InvalidParameterError.new('revocation_outpoint', 'present for direct acquisition') unless args[:revocation_outpoint]
            raise InvalidParameterError.new('signature', 'present for direct acquisition') unless args[:signature]
            raise InvalidParameterError.new('keyring_for_subject', 'a Hash for direct acquisition') unless args[:keyring_for_subject].is_a?(Hash)
          elsif protocol == 'issuance'
            raise InvalidParameterError.new('certifier_url', 'present for issuance acquisition') unless args[:certifier_url].is_a?(String)
          end
        end

        def acquire_via_direct(args)
          cert = {
            type: args[:type],
            subject: @key_deriver.identity_key,
            serial_number: args[:serial_number],
            certifier: args[:certifier],
            revocation_outpoint: args[:revocation_outpoint],
            signature: args[:signature],
            fields: args[:fields],
            keyring: args[:keyring_for_subject]
          }

          CertificateSignature.verify!(cert)

          cert
        end

        def acquire_via_issuance(args)
          response = auth_fetch_client.fetch(
            args[:certifier_url],
            method: 'POST',
            headers: { 'content-type' => 'application/json' },
            body: JSON.generate({
                                  type: args[:type],
                                  subject: @key_deriver.identity_key,
                                  certifier: args[:certifier],
                                  fields: args[:fields]
                                })
          )

          raise WalletError, "Certificate issuance failed: HTTP #{response.status}" unless (200..299).cover?(response.status)

          body = JSON.parse(response.body)

          cert = {
            type: body['type'] || args[:type],
            subject: @key_deriver.identity_key,
            serial_number: body['serialNumber'],
            certifier: args[:certifier],
            revocation_outpoint: body['revocationOutpoint'],
            signature: body['signature'],
            fields: body['fields'] || args[:fields],
            keyring: body['keyringForSubject']
          }

          CertificateSignature.verify!(cert)

          cert
        rescue JSON::ParserError
          raise WalletError, 'Certificate issuance failed: invalid JSON response'
        end

        def auth_fetch_client
          @auth_fetch_client ||= BSV::Auth::AuthFetch.new(wallet: self)
        end

        def execute_http(uri, request)
          if @http_client
            @http_client.request(uri, request)
          else
            Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
              http.request(request)
            end
          end
        end

        def find_stored_certificate(cert_arg)
          results = @storage.find_certificates({
                                                 certifiers: [cert_arg[:certifier]],
                                                 types: [cert_arg[:type]],
                                                 limit: 10_000
                                               })
          results.find { |c| c[:serial_number] == cert_arg[:serial_number] }
        end

        def cert_without_keyring(cert)
          result = cert.dup
          result.delete(:keyring)
          result
        end
      end
    end
  end
end
