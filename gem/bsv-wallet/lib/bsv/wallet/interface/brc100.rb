# frozen_string_literal: true

module BSV
  module Wallet
    # BRC-100 abstract wallet interface — all 28 methods.
    #
    # Include this module and override the methods your implementation supports.
    # Unimplemented methods raise {UnsupportedActionError}.
    #
    # The 28 methods are grouped into six functional areas matching
    # the BRC-100 Interface Structure specification.
    #
    # @example
    #   class MyWallet
    #     include BSV::Wallet::Interface::BRC100
    #
    #     def get_height(args = {}, originator: nil)
    #       { height: 800_000 }
    #     end
    #   end
    module Interface
      module BRC100
        # rubocop:disable Lint/UnusedMethodArgument

        # --- Transaction Operations (codes 1-7) ---

        def create_action(args, originator: nil)
          raise UnsupportedActionError, 'create_action'
        end

        def sign_action(args, originator: nil)
          raise UnsupportedActionError, 'sign_action'
        end

        def abort_action(args, originator: nil)
          raise UnsupportedActionError, 'abort_action'
        end

        def list_actions(args, originator: nil)
          raise UnsupportedActionError, 'list_actions'
        end

        def internalize_action(args, originator: nil)
          raise UnsupportedActionError, 'internalize_action'
        end

        def list_outputs(args, originator: nil)
          raise UnsupportedActionError, 'list_outputs'
        end

        def relinquish_output(args, originator: nil)
          raise UnsupportedActionError, 'relinquish_output'
        end

        # --- Public Key Management (codes 8-10) ---

        def get_public_key(args, originator: nil)
          raise UnsupportedActionError, 'get_public_key'
        end

        def reveal_counterparty_key_linkage(args, originator: nil)
          raise UnsupportedActionError, 'reveal_counterparty_key_linkage'
        end

        def reveal_specific_key_linkage(args, originator: nil)
          raise UnsupportedActionError, 'reveal_specific_key_linkage'
        end

        # --- Cryptography Operations (codes 11-16) ---

        def encrypt(args, originator: nil)
          raise UnsupportedActionError, 'encrypt'
        end

        def decrypt(args, originator: nil)
          raise UnsupportedActionError, 'decrypt'
        end

        def create_hmac(args, originator: nil)
          raise UnsupportedActionError, 'create_hmac'
        end

        def verify_hmac(args, originator: nil)
          raise UnsupportedActionError, 'verify_hmac'
        end

        def create_signature(args, originator: nil)
          raise UnsupportedActionError, 'create_signature'
        end

        def verify_signature(args, originator: nil)
          raise UnsupportedActionError, 'verify_signature'
        end

        # --- Identity and Certificate Management (codes 17-22) ---

        def acquire_certificate(args, originator: nil)
          raise UnsupportedActionError, 'acquire_certificate'
        end

        def list_certificates(args, originator: nil)
          raise UnsupportedActionError, 'list_certificates'
        end

        def prove_certificate(args, originator: nil)
          raise UnsupportedActionError, 'prove_certificate'
        end

        def relinquish_certificate(args, originator: nil)
          raise UnsupportedActionError, 'relinquish_certificate'
        end

        def discover_by_identity_key(args, originator: nil)
          raise UnsupportedActionError, 'discover_by_identity_key'
        end

        def discover_by_attributes(args, originator: nil)
          raise UnsupportedActionError, 'discover_by_attributes'
        end

        # --- Authentication (codes 23-24) ---

        def is_authenticated(args = {}, originator: nil)
          raise UnsupportedActionError, 'is_authenticated'
        end

        def wait_for_authentication(args = {}, originator: nil)
          raise UnsupportedActionError, 'wait_for_authentication'
        end

        # --- Blockchain and Network Data (codes 25-28) ---

        def get_height(args = {}, originator: nil)
          raise UnsupportedActionError, 'get_height'
        end

        def get_header_for_height(args, originator: nil)
          raise UnsupportedActionError, 'get_header_for_height'
        end

        def get_network(args = {}, originator: nil)
          raise UnsupportedActionError, 'get_network'
        end

        def get_version(args = {}, originator: nil)
          raise UnsupportedActionError, 'get_version'
        end

        # rubocop:enable Lint/UnusedMethodArgument
      end
    end
  end
end
