# frozen_string_literal: true

module BSV
  module Wallet
    module BRC100
      # BRC-100 Network and Blockchain Data (call codes 25-28).
      #
      # Provides abstract stubs for the blockchain query methods of the
      # BRC-100 wallet interface. Include this module and override the methods
      # your implementation supports. Unimplemented methods raise
      # {BSV::Wallet::UnsupportedActionError}.
      module Network
        # rubocop:disable Lint/UnusedMethodArgument

        def get_height(args = {}, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'get_height'
        end

        def get_header_for_height(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'get_header_for_height'
        end

        def get_network(args = {}, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'get_network'
        end

        def get_version(args = {}, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'get_version'
        end

        # rubocop:enable Lint/UnusedMethodArgument
      end
    end
  end
end
