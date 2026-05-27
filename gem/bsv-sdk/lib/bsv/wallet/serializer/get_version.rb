# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 serialiser for the get_version call (call byte 28).
      #
      # Wire format — result only (no args payload):
      #   [N bytes] raw UTF-8 version string (no length prefix)
      #
      # Port of go-sdk/wallet/serializer/get_version.go — the Go SDK emits
      # the string bytes directly, with no varint length prefix.
      module GetVersion
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

          # @param result [Hash] { version: String }
          # @return [String] binary (raw UTF-8 bytes)
          def serialize(result)
            result[:version].to_s.b
          end

          # @param bytes [String] binary
          # @return [Hash] { version: String }
          def deserialize(bytes)
            { version: bytes.b.force_encoding('UTF-8') }
          end
        end
      end
    end
  end
end
