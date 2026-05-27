# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +decrypt+ call (call byte 12).
      #
      # Port of go-sdk/wallet/serializer/decrypt.go.
      module Decrypt
        # Args wire layout:
        #   [key-related params]
        #   [VarInt ciphertext_len][ciphertext bytes]
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
            ciphertext = args.fetch(:ciphertext, ''.b)
            w.write_varint(ciphertext.bytesize)
            w.write_bytes(ciphertext)
            w.write_optional_bool(args[:seek_permission])
            w.buf
          end

          def deserialize(bytes)
            r = BSV::Wallet::Wire::Reader.new(bytes)
            params = Common.read_key_related_params(r)
            len = r.read_varint
            ciphertext = r.read_bytes(len)
            seek_permission = r.read_optional_bool
            params.merge(ciphertext: ciphertext, seek_permission: seek_permission)
          end
        end

        # Result wire layout:
        #   [plaintext bytes — remaining payload]
        module Result
          module_function

          def serialize(result)
            (result[:plaintext] || ''.b).b
          end

          def deserialize(bytes)
            { plaintext: bytes.b }
          end
        end
      end
    end
  end
end
