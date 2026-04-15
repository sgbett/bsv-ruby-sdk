# frozen_string_literal: true

module BSV
  module Auth
    # Utility module for validating certificates received in an authenticated message.
    #
    # Exposes a single module method, {.call}, which is also available as
    # +BSV::Auth.validate_certificates+ via +extend+.
    #
    # Algorithm:
    # 1. Raise +AuthError+ if +message[:certificates]+ is nil or empty.
    # 2. For each certificate in the array:
    #    a. Verify cert subject == message identity key.
    #    b. Construct a +VerifiableCertificate+ if the input is a plain Hash.
    #    c. Call +cert.verify+ — raise if signature is invalid.
    #    d. If +requested_certificates+ is provided, check certifier and type.
    #    e. Call +cert.decrypt_fields(wallet)+ — wrap any error in +AuthError+.
    #
    # Wallet is duck-typed — any object responding to +verify_signature+ and
    # +decrypt+ is accepted.
    module ValidateCertificates
      module_function

      # Validates certificates attached to an incoming authenticated message.
      #
      # @param wallet [#verify_signature, #decrypt] the verifier's wallet
      # @param message [Hash] incoming authenticated message; must contain
      #   +:certificates+ and +:identity_key+ (symbol or string keys accepted)
      # @param requested_certificates [Hash, nil] optional filter with keys
      #   +:certifiers+ (Array of pubkey hex strings) and +:types+
      #   (Hash of type string => fields)
      # @raise [AuthError] on any validation failure
      def validate_certificates(wallet, message, requested_certificates = nil)
        certs = message[:certificates] || message['certificates']
        raise AuthError, 'No certificates were provided in the message.' if certs.nil? || certs.empty?

        identity_key = message[:identity_key] || message['identity_key']

        certs.each do |incoming_cert|
          subject = if incoming_cert.is_a?(Hash)
                      incoming_cert[:subject] || incoming_cert['subject']
                    else
                      incoming_cert.subject
                    end

          if subject != identity_key
            raise AuthError,
                  "The subject of one of your certificates (\"#{subject}\") is not the same as " \
                  "the message sender (\"#{identity_key}\")."
          end

          cert = if incoming_cert.is_a?(VerifiableCertificate)
                   incoming_cert
                 else
                   VerifiableCertificate.from_hash(incoming_cert)
                 end

          begin
            valid = cert.verify
          rescue ArgumentError => e
            raise AuthError, "Certificate signature verification failed: #{e.message}"
          end

          unless valid
            raise AuthError,
                  "The signature for the certificate with serial number #{cert.serial_number} is invalid!"
          end

          if requested_certificates
            certifiers = requested_certificates[:certifiers] || requested_certificates['certifiers'] || []
            types = requested_certificates[:types] || requested_certificates['types'] || {}

            unless certifiers.include?(cert.certifier)
              raise AuthError,
                    "Certificate with serial number #{cert.serial_number} has an unrequested certifier: #{cert.certifier}"
            end

            unless types.key?(cert.type)
              raise AuthError,
                    "Certificate with type #{cert.type} was not requested"
            end
          end

          begin
            cert.decrypt_fields(wallet)
          rescue ArgumentError, RuntimeError => e
            raise AuthError, "Failed to decrypt certificate fields: #{e.message}"
          end
        end
      end
    end
  end
end
