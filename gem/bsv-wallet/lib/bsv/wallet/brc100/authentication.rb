# frozen_string_literal: true

module BSV
  module Wallet
    module BRC100
      # BRC-100 Authentication Operations (call codes 23-24).
      #
      # Provides abstract stubs for the authentication methods of the
      # BRC-100 wallet interface. Include this module and override the methods
      # your implementation supports. Unimplemented methods raise
      # {BSV::Wallet::UnsupportedActionError}.
      module Authentication
        # rubocop:disable Lint/UnusedMethodArgument

        def is_authenticated(args = {}, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'is_authenticated'
        end

        def wait_for_authentication(args = {}, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'wait_for_authentication'
        end

        # rubocop:enable Lint/UnusedMethodArgument
      end
    end
  end
end
