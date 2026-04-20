# frozen_string_literal: true

module BSV
  module Wallet
    module BRC100
      # BRC-100 Cryptography Operations (call codes 11-16).
      #
      # Provides abstract stubs for the encryption and signing methods of the
      # BRC-100 wallet interface. Include this module and override the methods
      # your implementation supports. Unimplemented methods raise
      # {BSV::Wallet::UnsupportedActionError}.
      module Crypto
        # rubocop:disable Lint/UnusedMethodArgument

        def encrypt(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'encrypt'
        end

        def decrypt(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'decrypt'
        end

        def create_hmac(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'create_hmac'
        end

        def verify_hmac(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'verify_hmac'
        end

        def create_signature(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'create_signature'
        end

        def verify_signature(args, originator: nil)
          raise BSV::Wallet::UnsupportedActionError, 'verify_signature'
        end

        # rubocop:enable Lint/UnusedMethodArgument
      end
    end
  end
end
