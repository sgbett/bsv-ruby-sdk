# frozen_string_literal: true

module BSV
  module Auth
    autoload :AuthError,      'bsv/auth/auth_error'
    autoload :AuthHeaders,    'bsv/auth/auth_headers'
    autoload :AuthPayload,    'bsv/auth/auth_payload'
    autoload :Nonce,          'bsv/auth/nonce'
    autoload :PeerSession,    'bsv/auth/peer_session'
    autoload :SessionManager, 'bsv/auth/session_manager'
    autoload :Transport,      'bsv/auth/transport'
    autoload :Peer,           'bsv/auth/peer'
    autoload :Certificate,             'bsv/auth/certificate'
    autoload :VerifiableCertificate,   'bsv/auth/verifiable_certificate'
    autoload :MasterCertificate,       'bsv/auth/master_certificate'
    autoload :ValidateCertificates,        'bsv/auth/validate_certificates'
    autoload :GetVerifiableCertificates,   'bsv/auth/get_verifiable_certificates'

    # Protocol version
    AUTH_VERSION = '0.1'

    # Message type string constants (matching ts-sdk/go-sdk)
    MSG_INITIAL_REQUEST  = 'initialRequest'
    MSG_INITIAL_RESPONSE = 'initialResponse'
    MSG_CERT_REQUEST     = 'certificateRequest'
    MSG_CERT_RESPONSE    = 'certificateResponse'
    MSG_GENERAL          = 'general'

    # Validates certificates attached to an incoming authenticated message.
    #
    # Delegates to {ValidateCertificates#validate_certificates}.
    #
    # @param wallet [#verify_signature, #decrypt] the verifier's wallet
    # @param message [Hash] incoming authenticated message
    # @param requested_certificates [Hash, nil] optional certifier/type filter
    # @raise [AuthError] on any validation failure
    def self.validate_certificates(wallet, message, requested_certificates = nil)
      ValidateCertificates.validate_certificates(wallet, message, requested_certificates)
    end

    # Retrieves verifiable certificates from a wallet for presentation to a verifier.
    #
    # Delegates to {GetVerifiableCertificates#get_verifiable_certificates}.
    #
    # @param wallet [#list_certificates, #prove_certificate] the subject's wallet
    # @param requested_certificates [Hash] certifiers and type-to-fields mapping
    # @param verifier_identity_key [String] verifier's compressed public key hex
    # @return [Array<VerifiableCertificate>]
    def self.get_verifiable_certificates(wallet, requested_certificates, verifier_identity_key)
      GetVerifiableCertificates.get_verifiable_certificates(wallet, requested_certificates, verifier_identity_key)
    end
  end
end
