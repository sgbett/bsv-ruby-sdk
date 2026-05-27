# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +create_hmac+ call (call byte 13).
      #
      # Port of go-sdk/wallet/serializer/create_hmac.go.
      module CreateHmac
        HMAC_SIZE = 32

        # Args wire layout:
        #   [key-related params]
        #   [VarInt data_len][data bytes]
        #   [optional_bool seek_permission]
        module Args
          module_function

          def serialize(args)
            BSV::Wallet::Wire::Validation.wallet_protocol!('protocol_id', args[:protocol_id])
            BSV::Wallet::Wire::Validation.key_id_string_1_to_800!('key_id', args[:key_id])
            BSV::Wallet::Wire::Validation.wallet_counterparty!('counterparty', args[:counterparty])

            w = BSV::Wallet::Wire::Writer.new
            Common.write_key_related_params(
              w,
              protocol_id: args[:protocol_id],
              key_id: args[:key_id],
              counterparty: args[:counterparty],
              privileged: args[:privileged],
              privileged_reason: args[:privileged_reason]
            )
            data = Common.to_binary(args[:data])
            w.write_varint(data.bytesize)
            w.write_bytes(data)
            w.write_optional_bool(args[:seek_permission])
            w.buf
          end

          def deserialize(bytes)
            r = BSV::Wallet::Wire::Reader.new(bytes)
            params = Common.read_key_related_params(r)
            len = r.read_varint
            data = r.read_bytes(len)
            seek_permission = r.read_optional_bool
            params.merge(data: data, seek_permission: seek_permission)
          end
        end

        # Result wire layout:
        #   [32 bytes: HMAC-SHA-256]
        module Result
          module_function

          def serialize(result)
            hmac = Common.to_binary(result[:hmac])
            raise ArgumentError, "HMAC must be #{HMAC_SIZE} bytes, got #{hmac.bytesize}" unless hmac.bytesize == HMAC_SIZE

            hmac
          end

          def deserialize(bytes)
            raise ArgumentError, "HMAC result too short: #{bytes.bytesize}" if bytes.bytesize < HMAC_SIZE

            { hmac: bytes.byteslice(0, HMAC_SIZE) }
          end
        end
      end
    end
  end
end
