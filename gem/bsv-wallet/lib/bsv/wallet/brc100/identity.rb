# frozen_string_literal: true

module BSV
  module Wallet
    module BRC100
      # BRC-100 Identity and Certificate Management (call codes 17-22).
      #
      # Provides abstract stubs for the certificate management methods of the
      # BRC-100 wallet interface. Include this module and override the methods
      # your implementation supports. Unimplemented methods raise
      # {BSV::Wallet::UnsupportedActionError}.
      module Identity
        # rubocop:disable Lint/UnusedMethodArgument

        def acquire_certificate(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'acquire_certificate'
        end

        def list_certificates(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'list_certificates'
        end

        def prove_certificate(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'prove_certificate'
        end

        def relinquish_certificate(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'relinquish_certificate'
        end

        def discover_by_identity_key(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'discover_by_identity_key'
        end

        def discover_by_attributes(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'discover_by_attributes'
        end

        # rubocop:enable Lint/UnusedMethodArgument
      end
    end
  end
end
