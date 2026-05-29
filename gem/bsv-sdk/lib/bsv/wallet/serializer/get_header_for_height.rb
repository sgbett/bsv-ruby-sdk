# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 serialiser for the get_header_for_height call (call byte 26).
      #
      # Wire format:
      #   Args:   [VarInt] height
      #   Result: [80 bytes] raw block header
      #
      # Port of go-sdk/wallet/serializer/get_header.go.
      module GetHeaderForHeight
        HEADER_BYTES = 80

        module Args
          module_function

          # @param args [Hash] { height: Integer }
          # @return [String] binary (varint-encoded height)
          def serialize(args)
            BSV::Transaction::VarInt.encode(args[:height].to_i)
          end

          # @param bytes [String] binary
          # @return [Hash] { height: Integer }
          def deserialize(bytes)
            raise BSV::Wallet::InvalidParameterError.new('get_header_for_height args', 'at least 1 byte') if bytes.b.empty?

            height, = BSV::Transaction::VarInt.decode(bytes.b, 0)
            { height: height }
          end
        end

        module Result
          module_function

          # @param result [Hash] { header: String } — 80-byte binary block header
          # @return [String] 80-byte binary
          # @raise [InvalidParameterError] if header is not exactly 80 bytes
          def serialize(result)
            header = result[:header].to_s.b
            unless header.bytesize == HEADER_BYTES
              raise BSV::Wallet::InvalidParameterError.new(
                'get_header_for_height result header',
                "exactly #{HEADER_BYTES} bytes, got #{header.bytesize}"
              )
            end

            header
          end

          # @param bytes [String] binary
          # @return [Hash] { header: String }
          # @raise [InvalidParameterError] if payload is not exactly 80 bytes
          def deserialize(bytes)
            data = bytes.b
            unless data.bytesize == HEADER_BYTES
              raise BSV::Wallet::InvalidParameterError.new(
                'get_header_for_height result',
                "exactly #{HEADER_BYTES} bytes, got #{data.bytesize}"
              )
            end

            { header: data }
          end
        end
      end
    end
  end
end
