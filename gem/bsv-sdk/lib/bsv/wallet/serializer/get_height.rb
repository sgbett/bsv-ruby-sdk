# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 serialiser for the get_height call (call byte 25).
      #
      # Wire format — result only (no args payload):
      #   [VarInt] block height (uint32 range)
      #
      # Port of go-sdk/wallet/serializer/get_height.go.
      module GetHeight
        module Args
          module_function

          def serialize(_args = {})
            ''.b
          end

          def deserialize(_bytes)
            {}
          end
        end

        module Result
          module_function

          # @param result [Hash] { height: Integer }
          # @return [String] binary (varint-encoded height)
          def serialize(result)
            BSV::Transaction::VarInt.encode(result[:height].to_i)
          end

          # @param bytes [String] binary
          # @return [Hash] { height: Integer }
          def deserialize(bytes)
            raise BSV::Wallet::InvalidParameterError.new('get_height result', 'at least 1 byte') if bytes.b.empty?

            height, = BSV::Transaction::VarInt.decode(bytes.b, 0)
            { height: height }
          end
        end
      end
    end
  end
end
