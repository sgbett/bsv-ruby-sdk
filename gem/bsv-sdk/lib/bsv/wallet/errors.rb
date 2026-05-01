# frozen_string_literal: true

module BSV
  module Wallet
    # Base error for all wallet operations. Carries a machine-readable code
    # per the BRC-100 error structure.
    class Error < StandardError
      attr_reader :code

      def initialize(message, code = 1)
        @code = code
        super(message)
      end
    end

    # Raised when a required parameter is missing or invalid.
    class InvalidParameterError < Error
      attr_reader :parameter

      def initialize(parameter, must_be = 'valid')
        @parameter = parameter
        super("the #{parameter} parameter must be #{must_be}", 6)
      end
    end

    # Raised when an HMAC fails to verify.
    class InvalidHmacError < Error
      def initialize(message = 'the provided HMAC is invalid')
        super(message, 3)
      end
    end

    # Raised when a signature fails to verify.
    class InvalidSignatureError < Error
      def initialize(message = 'the provided signature is invalid')
        super(message, 4)
      end
    end

    # Raised when an operation is not supported by this wallet implementation.
    class UnsupportedActionError < Error
      def initialize(method_name = 'this method')
        super("#{method_name} is not supported by this wallet implementation", 2)
      end
    end
  end
end
