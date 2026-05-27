# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 serialiser for internalize_action (call byte 5).
      #
      # Wire layout (port of go-sdk/wallet/serializer/internalize_action.go):
      #   [varint + bytes] tx (BEEF) — length-prefixed raw bytes
      #   [varint]         outputs count
      #   For each output:
      #     [varint]       output_index
      #     [1 byte]       protocol: 0x01=wallet_payment, 0x02=basket_insertion
      #     If wallet_payment:
      #       [33 bytes]   sender_identity_key (compressed pubkey)
      #       [int_bytes]  derivation_prefix
      #       [int_bytes]  derivation_suffix
      #     If basket_insertion:
      #       [string]     basket
      #       [optional_string] custom_instructions
      #       [string_slice] tags
      #   [string_slice]   labels
      #   [string]         description
      #   [go_optional_bool] seek_permission
      #
      # Result wire layout: empty (success is implicit from the frame error byte).
      module InternalizeActionArgs
        PROTOCOL_WALLET_PAYMENT   = 1
        PROTOCOL_BASKET_INSERTION = 2
        PUBKEY_SIZE               = 33

        module_function

        # @param args [Hash]
        # @return [String] binary
        def serialize(args)
          w = Wire::Writer.new

          tx = (args[:tx] || ''.b).b
          w.write_varint(tx.bytesize)
          w.write_bytes(tx)

          outputs = args[:outputs] || []
          w.write_varint(outputs.length)
          outputs.each { |out| serialize_output(w, out) }

          w.write_string_slice(args[:labels])
          w.write_string(args[:description].to_s)
          w.write_go_optional_bool(args[:seek_permission])

          w.buf
        end

        # @param bytes [String] binary
        # @return [Hash]
        def deserialize(bytes)
          r = Wire::Reader.new(bytes)

          tx_len = r.read_varint
          tx     = r.read_bytes(tx_len)

          output_count = r.read_varint
          outputs = output_count.times.map { deserialize_output(r) }

          labels         = r.read_string_slice
          description    = r.read_string
          seek_permission = r.read_go_optional_bool

          result = { tx: tx, outputs: outputs, description: description }
          result[:labels] = labels unless labels.nil?
          result[:seek_permission] = seek_permission unless seek_permission.nil?
          result
        end

        def serialize_output(writer, out)
          writer.write_varint(out[:output_index].to_i)

          case out[:protocol]
          when :wallet_payment
            writer.write_byte(PROTOCOL_WALLET_PAYMENT)
            payment = out[:payment_remittance] || {}
            writer.write_bytes([payment[:sender_identity_key]].pack('H*'))
            writer.write_int_bytes(payment[:derivation_prefix])
            writer.write_int_bytes(payment[:derivation_suffix])
          when :basket_insertion
            writer.write_byte(PROTOCOL_BASKET_INSERTION)
            insertion = out[:insertion_remittance] || {}
            writer.write_string(insertion[:basket].to_s)
            writer.write_optional_string(insertion[:custom_instructions])
            writer.write_string_slice(insertion[:tags])
          else
            raise ArgumentError, "unknown internalize protocol: #{out[:protocol]}"
          end
        end

        def deserialize_output(reader)
          output_index = reader.read_varint
          protocol_byte = reader.read_byte

          case protocol_byte
          when PROTOCOL_WALLET_PAYMENT
            key_bytes  = reader.read_bytes(PUBKEY_SIZE)
            prefix     = reader.read_int_bytes
            suffix     = reader.read_int_bytes
            {
              output_index: output_index,
              protocol: :wallet_payment,
              payment_remittance: {
                sender_identity_key: key_bytes.unpack1('H*'),
                derivation_prefix: prefix,
                derivation_suffix: suffix
              }
            }
          when PROTOCOL_BASKET_INSERTION
            basket  = reader.read_string
            custom  = reader.read_optional_string
            tags    = reader.read_string_slice
            result  = {
              output_index: output_index,
              protocol: :basket_insertion,
              insertion_remittance: { basket: basket }
            }
            result[:insertion_remittance][:custom_instructions] = custom unless custom.nil?
            result[:insertion_remittance][:tags] = tags unless tags.nil?
            result
          else
            raise ArgumentError, "invalid internalize protocol byte: #{protocol_byte}"
          end
        end

        private_class_method :serialize_output, :deserialize_output
      end

      module InternalizeActionResult
        module_function

        # @param _result [Hash] ignored
        # @return [String] empty binary
        def serialize(_result = {})
          ''.b
        end

        # @param _bytes [String] ignored
        # @return [Hash] { accepted: true }
        def deserialize(_bytes = nil)
          { accepted: true }
        end
      end
    end
  end
end
