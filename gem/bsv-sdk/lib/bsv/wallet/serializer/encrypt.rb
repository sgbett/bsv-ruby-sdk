# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +encrypt+ call (call byte 11).
      #
      # Port of go-sdk/wallet/serializer/encrypt.go.
      module Encrypt
        # Args wire layout:
        #   [key-related params: protocol + key_id + counterparty + privileged]
        #   [VarInt plaintext_len][plaintext bytes]
        #   [optional_bool seek_permission]
        module Args
          module_function

          def serialize(args)
            w = BSV::Wallet::Wire::Writer.new
            Common.write_key_related_params(
              w,
              protocol_id: args[:protocol_id],
              key_id: args[:key_id],
              counterparty: args[:counterparty],
              privileged: args[:privileged],
              privileged_reason: args[:privileged_reason]
            )
            plaintext = Common.to_binary(args[:plaintext])
            w.write_varint(plaintext.bytesize)
            w.write_bytes(plaintext)
            w.write_optional_bool(args[:seek_permission])
            w.buf
          end

          def deserialize(bytes)
            r = BSV::Wallet::Wire::Reader.new(bytes)
            params = Common.read_key_related_params(r)
            len = r.read_varint
            plaintext = r.read_bytes(len)
            seek_permission = r.read_optional_bool
            params.merge(plaintext: plaintext, seek_permission: seek_permission)
          end
        end

        # Result wire layout:
        #   [ciphertext bytes — remaining payload]
        module Result
          module_function

          def serialize(result)
            Common.to_binary(result[:ciphertext])
          end

          def deserialize(bytes)
            { ciphertext: bytes.b }
          end
        end
      end
    end
  end
end
