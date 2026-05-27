# frozen_string_literal: true

module BSV
  module Wallet
    module Wire
      # BRC-103 call byte constants and dispatch tables.
      #
      # Each constant maps to the corresponding Go SDK CallXxx constant in
      # go-sdk/wallet/substrates/wallet_wire_calls.go. The CALL_TO_METHOD
      # table maps each byte to the actual Ruby method name on Interface::BRC100.
      #
      # Note: call byte 23 maps to :authenticated? (predicate suffix preserved),
      # not :is_authenticated, to match the existing Interface::BRC100 definition.
      module Calls
        CREATE_ACTION                    = 1
        SIGN_ACTION                      = 2
        ABORT_ACTION                     = 3
        LIST_ACTIONS                     = 4
        INTERNALIZE_ACTION               = 5
        LIST_OUTPUTS                     = 6
        RELINQUISH_OUTPUT                = 7
        GET_PUBLIC_KEY                   = 8
        REVEAL_COUNTERPARTY_KEY_LINKAGE  = 9
        REVEAL_SPECIFIC_KEY_LINKAGE      = 10
        ENCRYPT                          = 11
        DECRYPT                          = 12
        CREATE_HMAC                      = 13
        VERIFY_HMAC                      = 14
        CREATE_SIGNATURE                 = 15
        VERIFY_SIGNATURE                 = 16
        ACQUIRE_CERTIFICATE              = 17
        LIST_CERTIFICATES                = 18
        PROVE_CERTIFICATE                = 19
        RELINQUISH_CERTIFICATE           = 20
        DISCOVER_BY_IDENTITY_KEY         = 21
        DISCOVER_BY_ATTRIBUTES           = 22
        IS_AUTHENTICATED                 = 23
        WAIT_FOR_AUTHENTICATION          = 24
        GET_HEIGHT                       = 25
        GET_HEADER_FOR_HEIGHT            = 26
        GET_NETWORK                      = 27
        GET_VERSION                      = 28

        CALL_TO_METHOD = {
          CREATE_ACTION => :create_action,
          SIGN_ACTION => :sign_action,
          ABORT_ACTION => :abort_action,
          LIST_ACTIONS => :list_actions,
          INTERNALIZE_ACTION => :internalize_action,
          LIST_OUTPUTS => :list_outputs,
          RELINQUISH_OUTPUT => :relinquish_output,
          GET_PUBLIC_KEY => :get_public_key,
          REVEAL_COUNTERPARTY_KEY_LINKAGE => :reveal_counterparty_key_linkage,
          REVEAL_SPECIFIC_KEY_LINKAGE => :reveal_specific_key_linkage,
          ENCRYPT => :encrypt,
          DECRYPT => :decrypt,
          CREATE_HMAC => :create_hmac,
          VERIFY_HMAC => :verify_hmac,
          CREATE_SIGNATURE => :create_signature,
          VERIFY_SIGNATURE => :verify_signature,
          ACQUIRE_CERTIFICATE => :acquire_certificate,
          LIST_CERTIFICATES => :list_certificates,
          PROVE_CERTIFICATE => :prove_certificate,
          RELINQUISH_CERTIFICATE => :relinquish_certificate,
          DISCOVER_BY_IDENTITY_KEY => :discover_by_identity_key,
          DISCOVER_BY_ATTRIBUTES => :discover_by_attributes,
          IS_AUTHENTICATED => :authenticated?,
          WAIT_FOR_AUTHENTICATION => :wait_for_authentication,
          GET_HEIGHT => :get_height,
          GET_HEADER_FOR_HEIGHT => :get_header_for_height,
          GET_NETWORK => :get_network,
          GET_VERSION => :get_version
        }.freeze

        METHOD_TO_CALL = CALL_TO_METHOD.invert.freeze
      end
    end
  end
end
