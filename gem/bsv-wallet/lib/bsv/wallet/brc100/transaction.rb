# frozen_string_literal: true

module BSV
  module Wallet
    module BRC100
      # BRC-100 Transaction Operations (call codes 1-7).
      #
      # Provides abstract stubs for the transaction-related methods of the
      # BRC-100 wallet interface. Include this module and override the methods
      # your implementation supports. Unimplemented methods raise
      # {BSV::Wallet::UnsupportedActionError}.
      module Transaction
        # rubocop:disable Lint/UnusedMethodArgument

        def create_action(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'create_action'
        end

        def sign_action(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'sign_action'
        end

        def abort_action(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'abort_action'
        end

        def list_actions(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'list_actions'
        end

        def internalize_action(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'internalize_action'
        end

        def list_outputs(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'list_outputs'
        end

        def relinquish_output(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'relinquish_output'
        end

        # rubocop:enable Lint/UnusedMethodArgument
      end
    end
  end
end
