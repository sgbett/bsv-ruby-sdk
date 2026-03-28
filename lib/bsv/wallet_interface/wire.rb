# frozen_string_literal: true

module BSV
  module Wallet
    # BRC-100 binary wire protocol.
    #
    # Provides low-level serialisation primitives ({Writer}, {Reader}) and a
    # higher-level {Serializer} that encodes/decodes all 28 BRC-100 method calls.
    #
    # Usage:
    #   frame = BSV::Wallet::Wire::Serializer.serialize_request(:get_height, {})
    #   method_name, args, originator = BSV::Wallet::Wire::Serializer.deserialize_request(frame)
    module Wire
      autoload :Writer,     'bsv/wallet_interface/wire/writer'
      autoload :Reader,     'bsv/wallet_interface/wire/reader'
      autoload :Serializer, 'bsv/wallet_interface/wire/serializer'
    end
  end
end
