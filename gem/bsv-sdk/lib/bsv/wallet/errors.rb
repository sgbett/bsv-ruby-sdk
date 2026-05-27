# frozen_string_literal: true

module BSV
  module Wallet
    # Base error for all wallet operations. Carries a machine-readable code
    # per the BRC-100 error structure and a wire-protocol stack string.
    class Error < StandardError
      attr_reader :code, :wallet_stack

      def initialize(message = nil, code: 1, stack: '')
        @code = code
        @wallet_stack = stack
        super(message || '')
      end

      # Serialise to a hash suitable for embedding in a wire result frame.
      # Never leaks Ruby's internal backtrace — only the wallet_stack string.
      def to_wire
        { code: code, message: message.to_s, stack: wallet_stack.to_s }
      end
    end

    # Code 2 — operation not supported by this wallet implementation.
    class UnsupportedActionError < Error
      def initialize(message = 'this method is not supported by this wallet implementation', stack: '')
        super(message, code: 2, stack: stack)
      end
    end

    # Code 3 — HMAC verification failed.
    class InvalidHmacError < Error
      def initialize(message = 'the provided HMAC is invalid', stack: '')
        super(message, code: 3, stack: stack)
      end
    end

    # Code 4 — signature verification failed.
    class InvalidSignatureError < Error
      def initialize(message = 'the provided signature is invalid', stack: '')
        super(message, code: 4, stack: stack)
      end
    end

    # Code 5 — wallet has insufficient funds for the requested operation.
    class InsufficientFundsError < Error
      def initialize(message = 'insufficient funds', stack: '')
        super(message, code: 5, stack: stack)
      end
    end

    # Code 6 — a required parameter is missing or invalid.
    #
    # Two calling conventions:
    #   InvalidParameterError.new('pubkey', 'a hex string')  # raises "the pubkey parameter must be ..."
    #   InvalidParameterError.new('raw message')              # wire-rehydration path
    class InvalidParameterError < Error
      attr_reader :parameter

      def initialize(parameter, must_be = nil, stack: '')
        @parameter = must_be ? parameter : nil
        message = must_be ? "the #{parameter} parameter must be #{must_be}" : parameter
        super(message, code: 6, stack: stack)
      end
    end

    # Code 7 — actions require review before they can be processed.
    class ReviewActionsError < Error
      def initialize(message = 'actions require review', stack: '')
        super(message, code: 7, stack: stack)
      end
    end

    # Rehydrate a wire error frame into the appropriate subclass.
    #
    # @param code [Integer] error code byte from the result frame
    # @param message [String] error message from the frame
    # @param stack [String] stack trace from the frame (may be empty)
    # @return [Error] an instance of the matching subclass
    def self.error_from_wire(code, message, stack = '')
      case code
      when 2 then UnsupportedActionError.new(message, stack: stack)
      when 3 then InvalidHmacError.new(message, stack: stack)
      when 4 then InvalidSignatureError.new(message, stack: stack)
      when 5 then InsufficientFundsError.new(message, stack: stack)
      when 6 then InvalidParameterError.new(message, nil, stack: stack)
      when 7 then ReviewActionsError.new(message, stack: stack)
      else        Error.new(message, code: code, stack: stack)
      end
    end
  end
end
