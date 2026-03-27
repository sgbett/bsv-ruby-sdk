# frozen_string_literal: true

module BSV
  module Wallet
    class InvalidParameterError < WalletError
      attr_reader :parameter

      def initialize(parameter, must_be = 'valid')
        @parameter = parameter
        super("The #{parameter} parameter must be #{must_be}", 6)
      end
    end
  end
end
