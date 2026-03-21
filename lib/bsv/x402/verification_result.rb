# frozen_string_literal: true

module BSV
  module X402
    # The result of a verification procedure run by {Verifier}.
    #
    # On success, {#step} and {#reason} are nil and {#success?} returns true.
    # On failure, {#step} holds the step number that failed (1–9) and {#reason}
    # holds a human-readable explanation.
    #
    # HTTP status codes follow spec §9:
    # - Steps 1, 2, 4, 6 → 400 Bad Request  (client sent a malformed proof)
    # - Steps 3, 5, 7, 8, 9 → 402 Payment Required (valid proof but payment problem)
    class VerificationResult
      # Steps that map to HTTP 400 Bad Request.
      BAD_REQUEST_STEPS = [1, 2, 4, 6].freeze

      # @return [Integer, nil] the step number that failed, or nil on success
      attr_reader :step

      # @return [String, nil] human-readable failure reason, or nil on success
      attr_reader :reason

      # @param step [Integer, nil] nil for success
      # @param reason [String, nil] nil for success
      def initialize(step: nil, reason: nil)
        @step   = step
        @reason = reason
        freeze
      end

      # Returns a successful result.
      #
      # @return [VerificationResult]
      def self.success
        new
      end

      # Returns a failure result for the given step.
      #
      # @param step [Integer] the step number that failed (1–9)
      # @param reason [String] human-readable failure reason
      # @return [VerificationResult]
      def self.failure(step:, reason:)
        new(step: step, reason: reason)
      end

      # @return [Boolean] true if verification passed all steps
      def success?
        @step.nil?
      end

      # @return [Boolean] true if any step failed
      def failure?
        !success?
      end

      # Returns the appropriate HTTP status code for this result.
      #
      # Success → 200 (caller decides the final passthrough status).
      # Failure at steps 1, 2, 4, 6 → 400 Bad Request.
      # Failure at steps 3, 5, 7, 8, 9 → 402 Payment Required.
      #
      # @return [Integer] HTTP status code
      def http_status
        return 200 if success?

        BAD_REQUEST_STEPS.include?(@step) ? 400 : 402
      end
    end
  end
end
