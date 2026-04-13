# frozen_string_literal: true

module BSV
  module Auth
    autoload :AuthError,      'bsv/auth/auth_error'
    autoload :Nonce,          'bsv/auth/nonce'
    autoload :PeerSession,    'bsv/auth/peer_session'
    autoload :SessionManager, 'bsv/auth/session_manager'
    autoload :Transport,      'bsv/auth/transport'
    autoload :Peer,           'bsv/auth/peer'
    autoload :Certificate,           'bsv/auth/certificate'
    autoload :MasterCertificate,     'bsv/auth/master_certificate'

    # Protocol version
    AUTH_VERSION = '0.1'

    # Message type string constants (matching ts-sdk/go-sdk)
    MSG_INITIAL_REQUEST  = 'initialRequest'
    MSG_INITIAL_RESPONSE = 'initialResponse'
    MSG_CERT_REQUEST     = 'certificateRequest'
    MSG_CERT_RESPONSE    = 'certificateResponse'
    MSG_GENERAL          = 'general'
  end
end
