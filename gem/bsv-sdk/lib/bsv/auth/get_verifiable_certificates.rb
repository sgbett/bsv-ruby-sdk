# frozen_string_literal: true

module BSV
  module Auth
    # Utility module for retrieving verifiable certificates from a wallet.
    #
    # Used during the certificate exchange phase of the BSV Auth peer protocol.
    # Lists certificates matching the requested certifiers and types, then calls
    # +prove_certificate+ for each to obtain a verifier-specific keyring for
    # selective field revelation.
    #
    # NOTE: Issue #424 documents a known bug in +WalletClient#prove_certificate+ — it
    # uses the wrong protocol ID (+certificate field revelation+ vs +certificate field
    # encryption+) and an incorrect key ID format. Until that bug is fixed, the keyring
    # produced here will be cryptographically incompatible with the TS/Go SDKs.
    module GetVerifiableCertificates
      module_function

      # Retrieve verifiable certificates from a wallet for presentation to a verifier.
      #
      # @param wallet [#list_certificates, #prove_certificate] the subject's wallet.
      #   Duck-typed — if the wallet does not respond to both methods, returns +[]+.
      # @param requested_certificates [Hash] with keys:
      #   - +:certifiers+ [Array<String>] list of certifier public key hexes
      #   - +:types+ [Hash] type (Base64 string) → array of field names to reveal
      # @param verifier_identity_key [String] the verifier's compressed public key hex
      # @return [Array<VerifiableCertificate>] list of verifiable certificates ready for
      #   presentation, or +[]+ on any failure
      def get_verifiable_certificates(wallet, requested_certificates, verifier_identity_key)
        return [] unless wallet.respond_to?(:list_certificates) && wallet.respond_to?(:prove_certificate)

        certifiers = requested_certificates[:certifiers] || requested_certificates['certifiers'] || []
        types_map  = requested_certificates[:types]      || requested_certificates['types']      || {}

        list_result = wallet.list_certificates(
          certifiers: certifiers,
          types: types_map.keys
        )

        certificates = list_result[:certificates] || list_result['certificates'] || []
        return [] if certificates.empty?

        certificates.map do |cert|
          cert_type = cert[:type] || cert['type']
          fields_to_reveal = types_map[cert_type] || types_map[cert_type.to_s] || types_map[cert_type.to_sym] || []

          prove_result = wallet.prove_certificate(
            certificate: cert,
            fields_to_reveal: fields_to_reveal,
            verifier: verifier_identity_key
          )

          keyring = prove_result[:keyring_for_verifier] ||
                    prove_result['keyring_for_verifier'] ||
                    prove_result[:keyringForVerifier]    ||
                    prove_result['keyringForVerifier']   ||
                    {}

          VerifiableCertificate.new(
            type: cert_type,
            serial_number: cert[:serial_number] || cert['serial_number'] ||
                           cert[:serialNumber] || cert['serialNumber'],
            subject: cert[:subject] || cert['subject'],
            certifier: cert[:certifier] || cert['certifier'],
            revocation_outpoint: cert[:revocation_outpoint] || cert['revocation_outpoint'] ||
                                 cert[:revocationOutpoint] || cert['revocationOutpoint'],
            fields: cert[:fields] || cert['fields'] || {},
            keyring: keyring,
            signature: cert[:signature] || cert['signature']
          )
        end
      rescue StandardError
        # Auto-fetch is best-effort: wallet may raise UnsupportedActionError,
        # key derivation errors, or other failures. The peer protocol handles
        # "no certificates" gracefully — the requesting peer enforces its own
        # certificate requirements independently.
        []
      end
    end
  end
end
