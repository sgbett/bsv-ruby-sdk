# frozen_string_literal: true

module BSV
  module Auth
    # Represents the state of an authentication session with a peer.
    #
    # Sessions are indexed by +session_nonce+ (our nonce for the session),
    # which is the primary key in {SessionManager}. The +peer_identity_key+
    # is a secondary index used to look up sessions by peer.
    #
    # @example Creating a session
    #   session = PeerSession.new(session_nonce: nonce)
    #   session.peer_identity_key = 'abc123...'
    #   session.peer_nonce = 'xyz...'
    class PeerSession
      # @return [String] our nonce for this session (base64) — primary key
      attr_reader :session_nonce

      # @return [String, nil] the peer's identity key (public key hex)
      attr_accessor :peer_identity_key

      # @return [String, nil] the nonce we received from the peer (base64)
      attr_accessor :peer_nonce

      # @return [Boolean] whether mutual authentication is complete
      attr_accessor :is_authenticated

      # @return [Integer] Unix timestamp (milliseconds) of last update
      attr_accessor :last_update

      # @return [Boolean] whether certificates are required from this peer
      attr_accessor :certificates_required

      # @return [Boolean] whether required certificates have been validated
      attr_accessor :certificates_validated

      # @param session_nonce [String] our nonce for this session (base64)
      def initialize(session_nonce:)
        @session_nonce          = session_nonce
        @peer_identity_key      = nil
        @peer_nonce             = nil
        @is_authenticated       = false
        @last_update            = current_time_ms
        @certificates_required  = false
        @certificates_validated = true
      end

      # @return [Boolean]
      def authenticated?
        @is_authenticated
      end

      private

      def current_time_ms
        (Time.now.to_f * 1000).to_i
      end
    end
  end
end
