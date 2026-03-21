# frozen_string_literal: true

module BSV
  module X402
    # Duck-type interface for challenge storage backends.
    #
    # A challenge store persists issued {Challenge} objects so they can be
    # retrieved during proof verification. The key used for storage and retrieval
    # is the challenge SHA-256 hex digest (+challenge.sha256+), which the client
    # copies into +proof.challenge_sha256+.
    #
    # Implementations MUST ensure that:
    # - +store+ is called at most once per SHA-256 key (challenges are immutable)
    # - +fetch+ returns +nil+ for unknown keys rather than raising
    # - Thread safety is the responsibility of the implementation
    #
    # Include this module to document intent; the default +store+/+fetch+ raise
    # +NotImplementedError+ if not overridden.
    module ChallengeStore
      # Persists a challenge.
      #
      # @param sha256    [String] hex SHA-256 digest of the canonical challenge JSON
      # @param challenge [Challenge]
      def store(sha256, challenge)
        raise NotImplementedError, "#{self.class}#store is not implemented"
      end

      # Retrieves a previously stored challenge.
      #
      # @param sha256 [String] hex SHA-256 digest
      # @return [Challenge, nil] the stored challenge, or nil if not found
      def fetch(sha256)
        raise NotImplementedError, "#{self.class}#fetch is not implemented"
      end
    end

    # Thread-safe in-memory challenge store.
    #
    # Suitable for single-process deployments and testing. For multi-process or
    # distributed deployments, replace with a Redis- or database-backed store.
    #
    # Challenges are not automatically expired from the store; they remain until
    # the process restarts. For long-running processes, consider a store with TTL
    # support to prevent unbounded memory growth.
    class MemoryChallengeStore
      include ChallengeStore

      def initialize
        @store = {}
        @mutex = Mutex.new
      end

      # Stores a challenge keyed by its SHA-256 digest.
      #
      # @param sha256    [String]
      # @param challenge [Challenge]
      def store(sha256, challenge)
        @mutex.synchronize { @store[sha256] = challenge }
      end

      # Retrieves a challenge by its SHA-256 digest.
      #
      # @param sha256 [String]
      # @return [Challenge, nil]
      def fetch(sha256)
        @mutex.synchronize { @store[sha256] }
      end

      # Returns the number of stored challenges.
      #
      # @return [Integer]
      def size
        @mutex.synchronize { @store.size }
      end

      # Removes all stored challenges. Useful for testing.
      def clear
        @mutex.synchronize { @store.clear }
      end
    end
  end
end
