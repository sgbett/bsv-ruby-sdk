# frozen_string_literal: true

module BSV
  module Wallet
    # Base class for all wallet errors.
    class WalletError < StandardError
      attr_reader :code

      def initialize(message, code = 1)
        @code = code
        super(message)
      end
    end

    # Raised when a signature fails to verify.
    class InvalidSignatureError < WalletError
      def initialize(message = 'invalid signature')
        super(message, 4)
      end
    end

    # Raised when an HMAC fails to verify.
    class InvalidHmacError < WalletError
      def initialize(message = 'invalid HMAC')
        super(message, 3)
      end
    end

    # Raised when a required parameter is missing or invalid.
    class InvalidParameterError < WalletError
      def initialize(parameter, must_be = 'valid')
        super("the #{parameter} parameter must be #{must_be}", 6)
      end
    end

    # Raised when an operation is not supported by this wallet implementation.
    class UnsupportedActionError < WalletError
      def initialize(message = 'unsupported action')
        super(message, 2)
      end
    end
  end
end
