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
    # Sessions expire after +default_ttl+ seconds (default: 3600). Pass
    # +default_ttl: nil+ to disable expiry entirely. Expired sessions are
    # removed lazily on access; call {#sweep_expired} for proactive cleanup.
    #
    # Matches the ts-sdk SessionManager dual-index design.
    class SessionManager
      # @param default_ttl [Integer, nil] seconds before a session expires;
      #   +nil+ disables TTL entirely.
      def initialize(default_ttl: 3600)
        @default_ttl = default_ttl
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
      # updated non-expired session for that peer.
      #
      # Returns +nil+ if the session has expired (and removes it from the store).
      #
      # @param identifier [String]
      # @return [PeerSession, nil]
      def get_session(identifier)
        @mutex.synchronize do
          direct = @by_nonce[identifier]
          if direct
            if expired_locked?(direct)
              remove_session_locked(direct)
              return nil
            end
            return direct
          end

          nonces = @by_identity[identifier]
          return nil if nonces.nil? || nonces.empty?

          best = nil
          expired_nonces = []
          nonces.each do |nonce|
            s = @by_nonce[nonce]
            next if s.nil?

            if expired_locked?(s)
              expired_nonces << s
              next
            end

            best = s if best.nil? || (s.last_update || 0) > (best.last_update || 0)
          end
          expired_nonces.each { |s| remove_session_locked(s) }
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
          direct = @by_nonce[identifier]
          if direct
            if expired_locked?(direct)
              remove_session_locked(direct)
              return false
            end
            return true
          end

          nonces = @by_identity[identifier]
          return false if nonces.nil? || nonces.empty?

          has_active = false
          expired_sessions = []
          nonces.each do |nonce|
            s = @by_nonce[nonce]
            next if s.nil?

            if expired_locked?(s)
              expired_sessions << s
            else
              has_active = true
            end
          end
          expired_sessions.each { |s| remove_session_locked(s) }
          has_active
        end
      end

      # Removes all expired sessions from the store.
      #
      # Not called automatically — intended for use in long-running servers
      # that want to proactively reclaim memory.
      #
      # @return [Integer] number of sessions removed
      def sweep_expired
        removed = 0
        @mutex.synchronize do
          expired = @by_nonce.values.select { |s| expired_locked?(s) }
          expired.each do |s|
            remove_session_locked(s)
            removed += 1
          end
        end
        removed
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

      # Must be called within @mutex.
      def expired_locked?(session)
        return false if @default_ttl.nil?

        last = session.last_update
        return true if last.nil? || last.zero?

        current_time_ms - last > @default_ttl * 1000
      end

      def current_time_ms
        (Time.now.to_f * 1000).to_i
      end
    end
  end
end
