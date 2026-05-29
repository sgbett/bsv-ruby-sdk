# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +verify_signature+ call (call byte 16).
      #
      # Port of go-sdk/wallet/serializer/verify_signature.go.
      module VerifySignature
        HASH_SIZE = 32

        # Args wire layout:
        #   [key-related params]
        #   [optional_bool for_self]
        #   [VarInt sig_len][DER signature bytes]
        #   [1 byte: data-type flag — 1=data, 2=hash_to_directly_verify]
        #   If flag=1: [VarInt data_len][data bytes]
        #   If flag=2: [32 bytes: hash]
        #   [optional_bool seek_permission]
        module Args
          module_function

          def serialize(args)
            data = args[:data] && Common.to_binary(args[:data])
            hash = args[:hash_to_directly_verify] && Common.to_binary(args[:hash_to_directly_verify])
            sig  = args[:signature] && Common.to_binary(args[:signature])

            if data && hash
              raise BSV::Wallet::InvalidParameterError.new(
                'data and hash_to_directly_verify',
                'not both provided — supply one or the other'
              )
            end
            raise BSV::Wallet::InvalidParameterError.new('data or hash_to_directly_verify', 'present') unless data || hash
            raise BSV::Wallet::InvalidParameterError.new('signature', 'present') unless sig

            w = BSV::Wallet::Wire::Writer.new
            Common.write_key_related_params(
              w,
              protocol_id: args[:protocol_id],
              key_id: args[:key_id],
              counterparty: args[:counterparty],
              privileged: args[:privileged],
              privileged_reason: args[:privileged_reason]
            )

            w.write_optional_bool(args[:for_self])

            w.write_varint(sig.bytesize)
            w.write_bytes(sig)

            if data
              w.write_byte(1)
              w.write_varint(data.bytesize)
              w.write_bytes(data)
            else
              w.write_byte(2)
              w.write_bytes(hash)
            end

            w.write_optional_bool(args[:seek_permission])
            w.buf
          end

          def deserialize(bytes)
            r = BSV::Wallet::Wire::Reader.new(bytes)
            params = Common.read_key_related_params(r)
            for_self = r.read_optional_bool
            sig_len = r.read_varint
            signature = r.read_bytes(sig_len)
            flag = r.read_byte
            payload = case flag
                      when 1
                        len = r.read_varint
                        { data: r.read_bytes(len) }
                      when 2
                        { hash_to_directly_verify: r.read_bytes(HASH_SIZE) }
                      else
                        raise ArgumentError, "invalid data-type flag: #{flag}"
                      end
            seek_permission = r.read_optional_bool
            params.merge(for_self: for_self, signature: signature).merge(payload).merge(seek_permission: seek_permission)
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
