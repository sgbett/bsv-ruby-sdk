# frozen_string_literal: true

module BSV
  module Wallet
    # Server-side BRC-103 dispatcher.
    #
    # Takes any {Interface::BRC100} implementation and exposes it as a
    # {WalletWire}. Decodes incoming binary request frames, dispatches to the
    # wallet, serialises the result, and returns a binary result frame.
    #
    # Error boundary: any {Error} from the wallet is serialised into an error
    # frame so the client can rehydrate it. Any other {StandardError} is wrapped
    # in {Error} (code 1) before framing — the processor never lets a Ruby
    # exception propagate past this boundary.
    #
    # @example Wrap a ProtoWallet for loopback testing
    #   processor = BSV::Wallet::WalletWireProcessor.new(proto_wallet)
    #   transceiver = BSV::Wallet::WalletWireTransceiver.new(processor)
    class WalletWireProcessor
      include WalletWire

      def initialize(wallet)
        @wallet = wallet
      end

      # Process a binary request frame and return a binary result frame.
      #
      # @param request_bytes [String] binary request frame
      # @return [String] binary result frame (success or error)
      def transmit_to_wallet(request_bytes)
        req = Wire::Frame.read_request(request_bytes)
        call_byte = req[:call]

        method_name = Wire::Calls::CALL_TO_METHOD.fetch(call_byte) do
          raise Error.new("unknown call byte: #{call_byte}", code: 1)
        end

        serialize_result = Serializer::SERIALIZE_RESULT.fetch(call_byte) do
          raise Error.new("no result serialiser for call #{call_byte}", code: 1)
        end

        args = Serializer::DESERIALIZE_ARGS.fetch(call_byte) do
          raise Error.new("no args deserialiser for call #{call_byte}", code: 1)
        end.call(req[:params])

        args[:originator] = req[:originator] unless req[:originator].empty?

        result  = @wallet.public_send(method_name, **args)
        payload = serialize_result.call(result)
        Wire::Frame.write_result(payload: payload)
      rescue NotImplementedError => e
        Wire::Frame.write_error(error: UnsupportedActionError.new(e.message.to_s))
      rescue Error => e
        Wire::Frame.write_error(error: e)
      rescue StandardError => e
        Wire::Frame.write_error(error: Error.new(e.message.to_s, code: 1))
      end
    end
  end
end
