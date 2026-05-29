# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 serialisers for is_authenticated (call byte 23) and
      # wait_for_authentication (call byte 24).
      #
      # Both calls take no args payload (originator is in the frame header).
      #
      # Result wire format:
      #   is_authenticated:        [1 byte] 0x01 = true, 0x00 = false
      #   wait_for_authentication: empty payload → always returns authenticated: true
      #
      # Port of go-sdk/wallet/serializer/authenticated.go.
      module IsAuthenticated
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

          # @param result [Hash] { authenticated: Boolean }
          # @return [String] 1-byte binary
          def serialize(result)
            [result[:authenticated] ? 1 : 0].pack('C')
          end

          # @param bytes [String] binary — must be exactly 1 byte
          # @return [Hash] { authenticated: Boolean }
          def deserialize(bytes)
            data = bytes.b
            unless data.bytesize == 1
              raise BSV::Wallet::InvalidParameterError.new(
                'is_authenticated result',
                'exactly 1 byte'
              )
            end

            { authenticated: data.getbyte(0) == 1 }
          end
        end
      end

      module WaitForAuthentication
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

          # @param _result [Hash] ignored — always serialises as empty payload
          # @return [String] empty binary
          def serialize(_result = {})
            ''.b
          end

          # @param _bytes [String] ignored — always returns authenticated: true
          # @return [Hash] { authenticated: true }
          def deserialize(_bytes = nil)
            { authenticated: true }
          end
        end
      end
    end
  end
end
