# frozen_string_literal: true

module BSV
  module X402
    # Base error class for all BSV x402 errors.
    class Error < StandardError; end

    # Raised when base64url or JSON decoding fails.
    class EncodingError < Error; end

    # Raised when a protocol object fails field-level validation.
    class ValidationError < Error; end

    # Raised when the client's UTXOs cannot cover the required payment plus fee.
    class InsufficientFundsError < Error; end

    # Raised when the challenge has already expired before the client can pay.
    class ChallengeExpiredError < Error; end

    # Raised when the client has exhausted its configured payment retry budget.
    class PaymentRetryExhaustedError < Error; end
  end
end
