# frozen_string_literal: true

module BSV
  module Wallet
    # Registry of per-call BRC-103 binary serialisers.
    #
    # Each table maps a Wire::Calls constant to the module_function on the
    # matching Serializer sub-module. Other developer agents populate their
    # tiers in parallel — add one entry per call, one line each.
    module Serializer
      autoload :Common,                       'bsv/wallet/serializer/common'

      # Crypto tier (call bytes 8-16)
      autoload :GetPublicKey,                 'bsv/wallet/serializer/get_public_key'
      autoload :RevealCounterpartyKeyLinkage, 'bsv/wallet/serializer/reveal_counterparty_key_linkage'
      autoload :RevealSpecificKeyLinkage,     'bsv/wallet/serializer/reveal_specific_key_linkage'
      autoload :Encrypt,                      'bsv/wallet/serializer/encrypt'
      autoload :Decrypt,                      'bsv/wallet/serializer/decrypt'
      autoload :CreateHmac,                   'bsv/wallet/serializer/create_hmac'
      autoload :VerifyHmac,                   'bsv/wallet/serializer/verify_hmac'
      autoload :CreateSignature,              'bsv/wallet/serializer/create_signature'
      autoload :VerifySignature,              'bsv/wallet/serializer/verify_signature'

      # Trivial tier (call bytes 23-28)
      autoload :GetNetwork,               'bsv/wallet/serializer/get_network'
      autoload :GetVersion,               'bsv/wallet/serializer/get_version'
      autoload :GetHeight,                'bsv/wallet/serializer/get_height'
      autoload :GetHeaderForHeight,       'bsv/wallet/serializer/get_header_for_height'
      autoload :IsAuthenticated,          'bsv/wallet/serializer/status'
      autoload :WaitForAuthentication,    'bsv/wallet/serializer/status'
      autoload :CreateActionArgs,           'bsv/wallet/serializer/create_action_args'
      autoload :CreateActionResult,         'bsv/wallet/serializer/create_action_result'
      autoload :SignActionArgs,             'bsv/wallet/serializer/sign_action_args'
      autoload :SignActionResult,           'bsv/wallet/serializer/sign_action_result'
      autoload :AbortAction,               'bsv/wallet/serializer/abort_action'
      autoload :InternalizeActionArgs,     'bsv/wallet/serializer/internalize_action'
      autoload :InternalizeActionResult,   'bsv/wallet/serializer/internalize_action'
      autoload :ListActionsArgs,           'bsv/wallet/serializer/list_actions'
      autoload :ListActionsResult,         'bsv/wallet/serializer/list_actions'
      autoload :Certificate,               'bsv/wallet/serializer/certificate'
      autoload :DiscoverCertificatesResult, 'bsv/wallet/serializer/discover_certificates_result'
      autoload :ListOutputs,               'bsv/wallet/serializer/list_outputs'
      autoload :RelinquishOutput,          'bsv/wallet/serializer/relinquish_output'
      autoload :AcquireCertificate,        'bsv/wallet/serializer/acquire_certificate'
      autoload :ListCertificates,          'bsv/wallet/serializer/list_certificates'
      autoload :ProveCertificate,          'bsv/wallet/serializer/prove_certificate'
      autoload :RelinquishCertificate,     'bsv/wallet/serializer/relinquish_certificate'
      autoload :DiscoverByIdentityKey,     'bsv/wallet/serializer/discover_by_identity_key'
      autoload :DiscoverByAttributes,      'bsv/wallet/serializer/discover_by_attributes'

      # Client-side: serialise outgoing args for each call.
      SERIALIZE_ARGS = {
        Wire::Calls::GET_PUBLIC_KEY => GetPublicKey::Args.method(:serialize),
        Wire::Calls::REVEAL_COUNTERPARTY_KEY_LINKAGE => RevealCounterpartyKeyLinkage::Args.method(:serialize),
        Wire::Calls::REVEAL_SPECIFIC_KEY_LINKAGE => RevealSpecificKeyLinkage::Args.method(:serialize),
        Wire::Calls::ENCRYPT => Encrypt::Args.method(:serialize),
        Wire::Calls::DECRYPT => Decrypt::Args.method(:serialize),
        Wire::Calls::CREATE_HMAC => CreateHmac::Args.method(:serialize),
        Wire::Calls::VERIFY_HMAC => VerifyHmac::Args.method(:serialize),
        Wire::Calls::CREATE_SIGNATURE => CreateSignature::Args.method(:serialize),
        Wire::Calls::VERIFY_SIGNATURE => VerifySignature::Args.method(:serialize),
        Wire::Calls::GET_NETWORK => GetNetwork::Args.method(:serialize),
        Wire::Calls::GET_VERSION => GetVersion::Args.method(:serialize),
        Wire::Calls::GET_HEIGHT => GetHeight::Args.method(:serialize),
        Wire::Calls::GET_HEADER_FOR_HEIGHT => GetHeaderForHeight::Args.method(:serialize),
        Wire::Calls::IS_AUTHENTICATED => IsAuthenticated::Args.method(:serialize),
        Wire::Calls::WAIT_FOR_AUTHENTICATION => WaitForAuthentication::Args.method(:serialize),
        Wire::Calls::CREATE_ACTION => CreateActionArgs.method(:serialize),
        Wire::Calls::SIGN_ACTION => SignActionArgs.method(:serialize),
        Wire::Calls::ABORT_ACTION => AbortAction.method(:serialize_args),
        Wire::Calls::INTERNALIZE_ACTION => InternalizeActionArgs.method(:serialize),
        Wire::Calls::LIST_ACTIONS => ListActionsArgs.method(:serialize),
        Wire::Calls::LIST_OUTPUTS => ListOutputs.method(:serialize_args),
        Wire::Calls::RELINQUISH_OUTPUT => RelinquishOutput.method(:serialize_args),
        Wire::Calls::ACQUIRE_CERTIFICATE => AcquireCertificate.method(:serialize_args),
        Wire::Calls::LIST_CERTIFICATES => ListCertificates.method(:serialize_args),
        Wire::Calls::PROVE_CERTIFICATE => ProveCertificate.method(:serialize_args),
        Wire::Calls::RELINQUISH_CERTIFICATE => RelinquishCertificate.method(:serialize_args),
        Wire::Calls::DISCOVER_BY_IDENTITY_KEY => DiscoverByIdentityKey.method(:serialize_args),
        Wire::Calls::DISCOVER_BY_ATTRIBUTES => DiscoverByAttributes.method(:serialize_args)
      }.freeze

      # Client-side: deserialise incoming result payload for each call.
      DESERIALIZE_RESULT = {
        Wire::Calls::GET_PUBLIC_KEY => GetPublicKey::Result.method(:deserialize),
        Wire::Calls::REVEAL_COUNTERPARTY_KEY_LINKAGE => RevealCounterpartyKeyLinkage::Result.method(:deserialize),
        Wire::Calls::REVEAL_SPECIFIC_KEY_LINKAGE => RevealSpecificKeyLinkage::Result.method(:deserialize),
        Wire::Calls::ENCRYPT => Encrypt::Result.method(:deserialize),
        Wire::Calls::DECRYPT => Decrypt::Result.method(:deserialize),
        Wire::Calls::CREATE_HMAC => CreateHmac::Result.method(:deserialize),
        Wire::Calls::VERIFY_HMAC => VerifyHmac::Result.method(:deserialize),
        Wire::Calls::CREATE_SIGNATURE => CreateSignature::Result.method(:deserialize),
        Wire::Calls::VERIFY_SIGNATURE => VerifySignature::Result.method(:deserialize),
        Wire::Calls::GET_NETWORK => GetNetwork::Result.method(:deserialize),
        Wire::Calls::GET_VERSION => GetVersion::Result.method(:deserialize),
        Wire::Calls::GET_HEIGHT => GetHeight::Result.method(:deserialize),
        Wire::Calls::GET_HEADER_FOR_HEIGHT => GetHeaderForHeight::Result.method(:deserialize),
        Wire::Calls::IS_AUTHENTICATED => IsAuthenticated::Result.method(:deserialize),
        Wire::Calls::WAIT_FOR_AUTHENTICATION => WaitForAuthentication::Result.method(:deserialize),
        Wire::Calls::CREATE_ACTION => CreateActionResult.method(:deserialize),
        Wire::Calls::SIGN_ACTION => SignActionResult.method(:deserialize),
        Wire::Calls::ABORT_ACTION => AbortAction.method(:deserialize_result),
        Wire::Calls::INTERNALIZE_ACTION => InternalizeActionResult.method(:deserialize),
        Wire::Calls::LIST_ACTIONS => ListActionsResult.method(:deserialize),
        Wire::Calls::LIST_OUTPUTS => ListOutputs.method(:deserialize_result),
        Wire::Calls::RELINQUISH_OUTPUT => RelinquishOutput.method(:deserialize_result),
        Wire::Calls::ACQUIRE_CERTIFICATE => AcquireCertificate.method(:deserialize_result),
        Wire::Calls::LIST_CERTIFICATES => ListCertificates.method(:deserialize_result),
        Wire::Calls::PROVE_CERTIFICATE => ProveCertificate.method(:deserialize_result),
        Wire::Calls::RELINQUISH_CERTIFICATE => RelinquishCertificate.method(:deserialize_result),
        Wire::Calls::DISCOVER_BY_IDENTITY_KEY => DiscoverByIdentityKey.method(:deserialize_result),
        Wire::Calls::DISCOVER_BY_ATTRIBUTES => DiscoverByAttributes.method(:deserialize_result)
      }.freeze

      # Server-side: deserialise incoming args payload for each call.
      DESERIALIZE_ARGS = {
        Wire::Calls::GET_PUBLIC_KEY => GetPublicKey::Args.method(:deserialize),
        Wire::Calls::REVEAL_COUNTERPARTY_KEY_LINKAGE => RevealCounterpartyKeyLinkage::Args.method(:deserialize),
        Wire::Calls::REVEAL_SPECIFIC_KEY_LINKAGE => RevealSpecificKeyLinkage::Args.method(:deserialize),
        Wire::Calls::ENCRYPT => Encrypt::Args.method(:deserialize),
        Wire::Calls::DECRYPT => Decrypt::Args.method(:deserialize),
        Wire::Calls::CREATE_HMAC => CreateHmac::Args.method(:deserialize),
        Wire::Calls::VERIFY_HMAC => VerifyHmac::Args.method(:deserialize),
        Wire::Calls::CREATE_SIGNATURE => CreateSignature::Args.method(:deserialize),
        Wire::Calls::VERIFY_SIGNATURE => VerifySignature::Args.method(:deserialize),
        Wire::Calls::GET_NETWORK => GetNetwork::Args.method(:deserialize),
        Wire::Calls::GET_VERSION => GetVersion::Args.method(:deserialize),
        Wire::Calls::GET_HEIGHT => GetHeight::Args.method(:deserialize),
        Wire::Calls::GET_HEADER_FOR_HEIGHT => GetHeaderForHeight::Args.method(:deserialize),
        Wire::Calls::IS_AUTHENTICATED => IsAuthenticated::Args.method(:deserialize),
        Wire::Calls::WAIT_FOR_AUTHENTICATION => WaitForAuthentication::Args.method(:deserialize),
        Wire::Calls::CREATE_ACTION => CreateActionArgs.method(:deserialize),
        Wire::Calls::SIGN_ACTION => SignActionArgs.method(:deserialize),
        Wire::Calls::ABORT_ACTION => AbortAction.method(:deserialize_args),
        Wire::Calls::INTERNALIZE_ACTION => InternalizeActionArgs.method(:deserialize),
        Wire::Calls::LIST_ACTIONS => ListActionsArgs.method(:deserialize),
        Wire::Calls::LIST_OUTPUTS => ListOutputs.method(:deserialize_args),
        Wire::Calls::RELINQUISH_OUTPUT => RelinquishOutput.method(:deserialize_args),
        Wire::Calls::ACQUIRE_CERTIFICATE => AcquireCertificate.method(:deserialize_args),
        Wire::Calls::LIST_CERTIFICATES => ListCertificates.method(:deserialize_args),
        Wire::Calls::PROVE_CERTIFICATE => ProveCertificate.method(:deserialize_args),
        Wire::Calls::RELINQUISH_CERTIFICATE => RelinquishCertificate.method(:deserialize_args),
        Wire::Calls::DISCOVER_BY_IDENTITY_KEY => DiscoverByIdentityKey.method(:deserialize_args),
        Wire::Calls::DISCOVER_BY_ATTRIBUTES => DiscoverByAttributes.method(:deserialize_args)
      }.freeze

      # Server-side: serialise outgoing result for each call.
      SERIALIZE_RESULT = {
        Wire::Calls::GET_PUBLIC_KEY => GetPublicKey::Result.method(:serialize),
        Wire::Calls::REVEAL_COUNTERPARTY_KEY_LINKAGE => RevealCounterpartyKeyLinkage::Result.method(:serialize),
        Wire::Calls::REVEAL_SPECIFIC_KEY_LINKAGE => RevealSpecificKeyLinkage::Result.method(:serialize),
        Wire::Calls::ENCRYPT => Encrypt::Result.method(:serialize),
        Wire::Calls::DECRYPT => Decrypt::Result.method(:serialize),
        Wire::Calls::CREATE_HMAC => CreateHmac::Result.method(:serialize),
        Wire::Calls::VERIFY_HMAC => VerifyHmac::Result.method(:serialize),
        Wire::Calls::CREATE_SIGNATURE => CreateSignature::Result.method(:serialize),
        Wire::Calls::VERIFY_SIGNATURE => VerifySignature::Result.method(:serialize),
        Wire::Calls::GET_NETWORK => GetNetwork::Result.method(:serialize),
        Wire::Calls::GET_VERSION => GetVersion::Result.method(:serialize),
        Wire::Calls::GET_HEIGHT => GetHeight::Result.method(:serialize),
        Wire::Calls::GET_HEADER_FOR_HEIGHT => GetHeaderForHeight::Result.method(:serialize),
        Wire::Calls::IS_AUTHENTICATED => IsAuthenticated::Result.method(:serialize),
        Wire::Calls::WAIT_FOR_AUTHENTICATION => WaitForAuthentication::Result.method(:serialize),
        Wire::Calls::CREATE_ACTION => CreateActionResult.method(:serialize),
        Wire::Calls::SIGN_ACTION => SignActionResult.method(:serialize),
        Wire::Calls::ABORT_ACTION => AbortAction.method(:serialize_result),
        Wire::Calls::INTERNALIZE_ACTION => InternalizeActionResult.method(:serialize),
        Wire::Calls::LIST_ACTIONS => ListActionsResult.method(:serialize),
        Wire::Calls::LIST_OUTPUTS => ListOutputs.method(:serialize_result),
        Wire::Calls::RELINQUISH_OUTPUT => RelinquishOutput.method(:serialize_result),
        Wire::Calls::ACQUIRE_CERTIFICATE => AcquireCertificate.method(:serialize_result),
        Wire::Calls::LIST_CERTIFICATES => ListCertificates.method(:serialize_result),
        Wire::Calls::PROVE_CERTIFICATE => ProveCertificate.method(:serialize_result),
        Wire::Calls::RELINQUISH_CERTIFICATE => RelinquishCertificate.method(:serialize_result),
        Wire::Calls::DISCOVER_BY_IDENTITY_KEY => DiscoverByIdentityKey.method(:serialize_result),
        Wire::Calls::DISCOVER_BY_ATTRIBUTES => DiscoverByAttributes.method(:serialize_result)
      }.freeze
    end
  end
end
