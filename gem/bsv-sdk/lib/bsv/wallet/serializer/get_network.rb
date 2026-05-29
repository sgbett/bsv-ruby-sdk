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
          # @raise [InvalidParameterError] if +:network+ is not :mainnet or :testnet
          def serialize(result)
            code = case result[:network]
                   when :mainnet then MAINNET_CODE
                   when :testnet then TESTNET_CODE
                   else
                     raise BSV::Wallet::InvalidParameterError.new(
                       'network', ":mainnet or :testnet, got #{result[:network].inspect}"
                     )
                   end
            [code].pack('C')
          end

          # @param bytes [String] 1-byte binary
          # @return [Hash] { network: :mainnet | :testnet }
          # @raise [InvalidParameterError] if the byte is not 0x00 or 0x01
          def deserialize(bytes)
            data = bytes.b
            raise BSV::Wallet::InvalidParameterError.new('get_network result', 'exactly 1 byte') unless data.bytesize == 1

            case data.getbyte(0)
            when MAINNET_CODE then { network: :mainnet }
            when TESTNET_CODE then { network: :testnet }
            else
              raise BSV::Wallet::InvalidParameterError.new(
                'get_network result', "0x00 (mainnet) or 0x01 (testnet), got 0x#{data.unpack1('H*')}"
              )
            end
          end
        end
      end
    end
  end
end
