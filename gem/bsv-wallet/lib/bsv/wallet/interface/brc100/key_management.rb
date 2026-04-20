# frozen_string_literal: true

module BSV
  module Wallet
    module BRC100
      # BRC-100 Key Management Operations (call codes 8-10).
      #
      # Provides abstract stubs for the public key management methods of the
      # BRC-100 wallet interface. Include this module and override the methods
      # your implementation supports. Unimplemented methods raise
      # {BSV::Wallet::UnsupportedActionError}.
      module KeyManagement
        # rubocop:disable Lint/UnusedMethodArgument

        def get_public_key(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'get_public_key'
        end

        def reveal_counterparty_key_linkage(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'reveal_counterparty_key_linkage'
        end

        def reveal_specific_key_linkage(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'reveal_specific_key_linkage'
        end

        # rubocop:enable Lint/UnusedMethodArgument
      end
    end
  end
end
