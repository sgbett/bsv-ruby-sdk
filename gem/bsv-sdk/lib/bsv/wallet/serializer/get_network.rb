# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 serialiser for the get_network call (call byte 27).
      #
      # Wire format — result only (no args payload):
      #   [1 byte] 0x00 = mainnet, 0x01 = testnet
      module GetNetwork
        # Args is always empty — get_network takes no parameters.
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
          MAINNET_CODE = 0
          TESTNET_CODE = 1

          module_function

          # @param result [Hash] { network: :mainnet | :testnet }
          # @return [String] 1-byte binary
          def serialize(result)
            code = result[:network] == :testnet ? TESTNET_CODE : MAINNET_CODE
            [code].pack('C')
          end

          # @param bytes [String] 1-byte binary
          # @return [Hash] { network: :mainnet | :testnet }
          def deserialize(bytes)
            data = bytes.b
            raise BSV::Wallet::InvalidParameterError.new('get_network result', 'exactly 1 byte') unless data.bytesize == 1

            network = data.getbyte(0) == TESTNET_CODE ? :testnet : :mainnet
            { network: network }
          end
        end
      end
    end
  end
end
