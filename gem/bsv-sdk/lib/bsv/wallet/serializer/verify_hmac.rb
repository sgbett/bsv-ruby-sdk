# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +verify_hmac+ call (call byte 14).
      #
      # Port of go-sdk/wallet/serializer/verify_hmac.go.
      module VerifyHmac
        HMAC_SIZE = 32

        # Args wire layout:
        #   [key-related params]
        #   [32 bytes: HMAC]
        #   [VarInt data_len][data bytes]
        #   [optional_bool seek_permission]
        module Args
          module_function

          def serialize(args)
            BSV::Wallet::Wire::Validation.wallet_protocol!('protocol_id', args[:protocol_id])
            BSV::Wallet::Wire::Validation.key_id_string_1_to_800!('key_id', args[:key_id])
            BSV::Wallet::Wire::Validation.wallet_counterparty!('counterparty', args[:counterparty])

            hmac = args[:hmac] || ''.b
            raise BSV::Wallet::InvalidParameterError.new('hmac', "exactly #{HMAC_SIZE} bytes") unless hmac.bytesize == HMAC_SIZE

            w = BSV::Wallet::Wire::Writer.new
            Common.write_key_related_params(
              w,
              protocol_id: args[:protocol_id],
              key_id: args[:key_id],
              counterparty: args[:counterparty],
              privileged: args[:privileged],
              privileged_reason: args[:privileged_reason]
            )
            w.write_bytes(hmac)
            data = args.fetch(:data, ''.b)
            w.write_varint(data.bytesize)
            w.write_bytes(data)
            w.write_optional_bool(args[:seek_permission])
            w.buf
          end

          def deserialize(bytes)
            r = BSV::Wallet::Wire::Reader.new(bytes)
            params = Common.read_key_related_params(r)
            hmac = r.read_bytes(HMAC_SIZE)
            data_len = r.read_varint
            data = r.read_bytes(data_len)
            seek_permission = r.read_optional_bool
            params.merge(hmac: hmac, data: data, seek_permission: seek_permission)
          end
        end

        # Result wire layout: empty — success implies valid.
        module Result
          module_function

          def serialize(_result)
            ''.b
          end

          def deserialize(_bytes)
            { valid: true }
          end
        end
      end
    end
  end
end
