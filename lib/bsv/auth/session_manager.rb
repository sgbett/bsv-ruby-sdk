# frozen_string_literal: true

module BSV
  module Auth
    # Thread-safe store for {PeerSession} objects.
    #
    # Supports dual-index lookup: by +session_nonce+ (primary) or by
    # +peer_identity_key+ (secondary). Multiple concurrent sessions per
    # peer identity key are supported — the most recently updated session
    # is returned when looking up by identity key.
    #
    # Matches the ts-sdk SessionManager dual-index design.
    class SessionManager
      def initialize
        # session_nonce -> PeerSession
        @by_nonce    = {}
        # peer_identity_key -> Set of session_nonces
        @by_identity = {}
        @mutex       = Mutex.new
      end

      # Adds a session to the manager.
      #
      # @param session [PeerSession]
      # @raise [ArgumentError] if +session_nonce+ is blank
      def add_session(session)
        raise ArgumentError, 'session_nonce is required' unless session.session_nonce.is_a?(String) && !session.session_nonce.empty?

        @mutex.synchronize do
          @by_nonce[session.session_nonce] = session

          if session.peer_identity_key.is_a?(String)
            nonces = @by_identity[session.peer_identity_key] ||= []
            nonces << session.session_nonce unless nonces.include?(session.session_nonce)
          end
        end
      end

      # Updates an existing session (removes old references and re-adds).
      #
      # @param session [PeerSession]
      def update_session(session)
        @mutex.synchronize do
          remove_session_locked(session)
          add_session_locked(session)
        end
      end

      # Retrieves a session by +session_nonce+ or +peer_identity_key+.
      #
      # When the identifier is a session nonce, returns that exact session.
      # When the identifier is a peer identity key, returns the most recently
      # updated session for that peer.
      #
      # @param identifier [String]
      # @return [PeerSession, nil]
      def get_session(identifier)
        @mutex.synchronize do
          direct = @by_nonce[identifier]
          return direct if direct

          nonces = @by_identity[identifier]
          return nil if nonces.nil? || nonces.empty?

          best = nil
          nonces.each do |nonce|
            s = @by_nonce[nonce]
            next if s.nil?

            best = s if best.nil? || (s.last_update || 0) > (best.last_update || 0)
          end
          best
        end
      end

      # Removes a session from the manager.
      #
      # @param session [PeerSession]
      def remove_session(session)
        @mutex.synchronize { remove_session_locked(session) }
      end

      # @param identifier [String] session nonce or identity key
      # @return [Boolean]
      def session?(identifier)
        @mutex.synchronize do
          return true if @by_nonce.key?(identifier)

          nonces = @by_identity[identifier]
          !nonces.nil? && !nonces.empty?
        end
      end

      private

      def add_session_locked(session)
        return unless session.session_nonce.is_a?(String) && !session.session_nonce.empty?

        @by_nonce[session.session_nonce] = session

        return unless session.peer_identity_key.is_a?(String)

        nonces = @by_identity[session.peer_identity_key] ||= []
        nonces << session.session_nonce unless nonces.include?(session.session_nonce)
      end

      def remove_session_locked(session)
        @by_nonce.delete(session.session_nonce)

        return unless session.peer_identity_key.is_a?(String)

        nonces = @by_identity[session.peer_identity_key]
        return unless nonces

        nonces.delete(session.session_nonce)
        @by_identity.delete(session.peer_identity_key) if nonces.empty?
      end
    end
  end
end
