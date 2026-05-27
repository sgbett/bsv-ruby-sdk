# frozen_string_literal: true

module BSV
  module Wallet
    # Registry of per-call BRC-103 binary serialisers.
    #
    # Each table maps a Wire::Calls constant to the module_function on the
    # matching Serializer sub-module. Other developer agents populate their
    # tiers in parallel — add one entry per call, one line each.
    module Serializer
      autoload :GetNetwork,          'bsv/wallet/serializer/get_network'
      autoload :GetVersion,          'bsv/wallet/serializer/get_version'
      autoload :GetHeight,           'bsv/wallet/serializer/get_height'
      autoload :GetHeaderForHeight,  'bsv/wallet/serializer/get_header_for_height'
      autoload :IsAuthenticated,     'bsv/wallet/serializer/status'
      autoload :WaitForAuthentication, 'bsv/wallet/serializer/status'

      # Client-side: serialise outgoing args for each call.
      SERIALIZE_ARGS = {
        Wire::Calls::GET_NETWORK => GetNetwork::Args.method(:serialize),
        Wire::Calls::GET_VERSION => GetVersion::Args.method(:serialize),
        Wire::Calls::GET_HEIGHT => GetHeight::Args.method(:serialize),
        Wire::Calls::GET_HEADER_FOR_HEIGHT => GetHeaderForHeight::Args.method(:serialize),
        Wire::Calls::IS_AUTHENTICATED => IsAuthenticated::Args.method(:serialize),
        Wire::Calls::WAIT_FOR_AUTHENTICATION => WaitForAuthentication::Args.method(:serialize)
      }.freeze

      # Client-side: deserialise incoming result payload for each call.
      DESERIALIZE_RESULT = {
        Wire::Calls::GET_NETWORK => GetNetwork::Result.method(:deserialize),
        Wire::Calls::GET_VERSION => GetVersion::Result.method(:deserialize),
        Wire::Calls::GET_HEIGHT => GetHeight::Result.method(:deserialize),
        Wire::Calls::GET_HEADER_FOR_HEIGHT => GetHeaderForHeight::Result.method(:deserialize),
        Wire::Calls::IS_AUTHENTICATED => IsAuthenticated::Result.method(:deserialize),
        Wire::Calls::WAIT_FOR_AUTHENTICATION => WaitForAuthentication::Result.method(:deserialize)
      }.freeze

      # Server-side: deserialise incoming args payload for each call.
      DESERIALIZE_ARGS = {
        Wire::Calls::GET_NETWORK => GetNetwork::Args.method(:deserialize),
        Wire::Calls::GET_VERSION => GetVersion::Args.method(:deserialize),
        Wire::Calls::GET_HEIGHT => GetHeight::Args.method(:deserialize),
        Wire::Calls::GET_HEADER_FOR_HEIGHT => GetHeaderForHeight::Args.method(:deserialize),
        Wire::Calls::IS_AUTHENTICATED => IsAuthenticated::Args.method(:deserialize),
        Wire::Calls::WAIT_FOR_AUTHENTICATION => WaitForAuthentication::Args.method(:deserialize)
      }.freeze

      # Server-side: serialise outgoing result for each call.
      SERIALIZE_RESULT = {
        Wire::Calls::GET_NETWORK => GetNetwork::Result.method(:serialize),
        Wire::Calls::GET_VERSION => GetVersion::Result.method(:serialize),
        Wire::Calls::GET_HEIGHT => GetHeight::Result.method(:serialize),
        Wire::Calls::GET_HEADER_FOR_HEIGHT => GetHeaderForHeight::Result.method(:serialize),
        Wire::Calls::IS_AUTHENTICATED => IsAuthenticated::Result.method(:serialize),
        Wire::Calls::WAIT_FOR_AUTHENTICATION => WaitForAuthentication::Result.method(:serialize)
      }.freeze
    end
  end
end
