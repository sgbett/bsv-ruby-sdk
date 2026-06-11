# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +create_signature+ call (call byte 15).
      #
      # Port of go-sdk/wallet/serializer/create_signature.go.
      module CreateSignature
        HASH_SIZE = 32

        # Args wire layout:
        #   [key-related params]
        #   [1 byte: data-type flag — 1=data, 2=hash_to_directly_sign]
        #   If flag=1: [VarInt data_len][data bytes]
        #   If flag=2: [32 bytes: hash]
        #   [optional_bool seek_permission]
        module Args
          module_function

          def serialize(args)
            data = args[:data] && Common.to_binary(args[:data])
            hash = args[:hash_to_directly_sign] && Common.to_binary(args[:hash_to_directly_sign])

            if data && hash
              raise BSV::Wallet::InvalidParameterError.new(
                'data and hash_to_directly_sign',
                'not both provided — supply one or the other'
              )
            end
            raise BSV::Wallet::InvalidParameterError.new('data or hash_to_directly_sign', 'present') unless data || hash

            if hash && hash.bytesize != HASH_SIZE
              raise BSV::Wallet::InvalidParameterError.new(
                'hash_to_directly_sign',
                "exactly #{HASH_SIZE} bytes, got #{hash.bytesize}"
              )
            end

            w = BSV::Wallet::Wire::Writer.new
            Common.write_key_related_params(
              w,
              protocol_id: args[:protocol_id],
              key_id: args[:key_id],
              counterparty: args[:counterparty],
              privileged: args[:privileged],
              privileged_reason: args[:privileged_reason]
            )

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
            flag = r.read_byte
            payload = case flag
                      when 1
                        len = r.read_varint
                        { data: r.read_bytes(len) }
                      when 2
                        { hash_to_directly_sign: r.read_bytes(HASH_SIZE) }
                      else
                        raise ArgumentError, "invalid data-type flag: #{flag}"
                      end
            seek_permission = r.read_optional_bool
            params.merge(payload).merge(seek_permission: seek_permission)
          end
        end

        # Result wire layout:
        #   [DER signature bytes — remaining payload]
        module Result
          module_function

          def serialize(result)
            Common.to_binary(result[:signature])
          end

          def deserialize(bytes)
            { signature: bytes.b }
          end
        end
      end
    end
  end
end
