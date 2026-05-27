# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +get_public_key+ call (call byte 8).
      #
      # Port of go-sdk/wallet/serializer/get_public_key.go.
      module GetPublicKey
        IDENTITY_KEY_FLAG = 1
        PUBKEY_SIZE       = 33

        # Args wire layout:
        #   [1 byte: identity_key flag — 0=no, 1=yes]
        #   If 0: [key-related params][optional_bool for_self]
        #   If 1: [privileged params only]
        #   [optional_bool seek_permission]
        module Args
          module_function

          def serialize(args)
            identity_key = args[:identity_key]
            w = BSV::Wallet::Wire::Writer.new

            if identity_key
              w.write_byte(IDENTITY_KEY_FLAG)
              Common.write_privileged_params(w, args[:privileged], args[:privileged_reason])
            else
              BSV::Wallet::Wire::Validation.wallet_protocol!('protocol_id', args[:protocol_id])
              BSV::Wallet::Wire::Validation.key_id_string_1_to_800!('key_id', args[:key_id])
              BSV::Wallet::Wire::Validation.wallet_counterparty!('counterparty', args[:counterparty])
              w.write_byte(0)
              Common.write_key_related_params(
                w,
                protocol_id: args[:protocol_id],
                key_id: args[:key_id],
                counterparty: args[:counterparty],
                privileged: args[:privileged],
                privileged_reason: args[:privileged_reason]
              )
              w.write_optional_bool(args[:for_self])
            end

            w.write_optional_bool(args[:seek_permission])
            w.buf
          end

          def deserialize(bytes)
            r = BSV::Wallet::Wire::Reader.new(bytes)
            flag = r.read_byte

            if flag == IDENTITY_KEY_FLAG
              privileged, reason = Common.read_privileged_params(r)
              seek_permission = r.read_optional_bool
              {
                identity_key: true,
                privileged: privileged,
                privileged_reason: reason,
                seek_permission: seek_permission
              }
            else
              params = Common.read_key_related_params(r)
              for_self = r.read_optional_bool
              seek_permission = r.read_optional_bool
              params.merge(identity_key: false, for_self: for_self, seek_permission: seek_permission)
            end
          end
        end

        # Result wire layout:
        #   [33 bytes: compressed public key]
        module Result
          module_function

          def serialize(result)
            pubkey = result[:public_key] || ''.b
            pubkey.b
          end

          def deserialize(bytes)
            raise ArgumentError, "public key too short: #{bytes.bytesize}" if bytes.bytesize < PUBKEY_SIZE

            { public_key: bytes.byteslice(0, PUBKEY_SIZE) }
          end
        end
      end
    end
  end
end
