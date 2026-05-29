# frozen_string_literal: true

module BSV
  module Wallet
    # Client-side BRC-103 transceiver.
    #
    # Implements every {Interface::BRC100} method by serialising the call
    # arguments to a binary request frame, transmitting it over a {WalletWire},
    # unframing the result, and deserialising the payload back to a Ruby hash.
    #
    # @example In-process loopback (testing / same-process use)
    #   proto     = BSV::Wallet::ProtoWallet.new(key)
    #   processor = BSV::Wallet::WalletWireProcessor.new(proto)
    #   client    = BSV::Wallet::WalletWireTransceiver.new(processor)
    #   client.get_public_key(identity_key: true)
    #   #=> { public_key: "02..." }
    #
    # @example Over HTTP
    #   wire   = BSV::Wallet::Substrates::HTTPWalletWire.new(base_url: 'https://wallet.example')
    #   client = BSV::Wallet::WalletWireTransceiver.new(wire)
    #
    # Thread safety: each call is independent. The wire transport is the
    # synchronisation boundary — concurrent calls are serialised only if the
    # underlying wire implementation serialises them.
    class WalletWireTransceiver
      include Interface::BRC100

      # @param wire [#transmit_to_wallet] any object that includes {WalletWire}
      def initialize(wire)
        @wire = wire
      end

      # Generate the 28 BRC-100 methods via metaprogramming.
      #
      # For each call byte → method name mapping in CALL_TO_METHOD, define a
      # method that:
      #   1. Extracts originator from kwargs (default '').
      #   2. Serialises the args via the SERIALIZE_ARGS dispatch table.
      #   3. Frames and transmits the binary request.
      #   4. Unframes the result (raises on error frame).
      #   5. Deserialises the payload via DESERIALIZE_RESULT.
      Wire::Calls::CALL_TO_METHOD.each do |call_byte, method_name|
        define_method(method_name) do |**args|
          _dispatch(call_byte, args)
        end
      end

      private

      def _dispatch(call_byte, args)
        originator = args[:originator].to_s
        Wire::Validation.originator_domain!('originator', originator) unless originator.empty?
        params  = Serializer::SERIALIZE_ARGS.fetch(call_byte).call(args)
        frame   = Wire::Frame.write_request(call: call_byte, originator: originator, params: params)
        reply   = @wire.transmit_to_wallet(frame)
        payload = Wire::Frame.read_result(reply)
        Serializer::DESERIALIZE_RESULT.fetch(call_byte).call(payload)
      end
    end
  end
end
