# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # Shared binary encoding helpers for BRC-103 per-call serializers.
      #
      # Port of the shared helpers in go-sdk/wallet/serializer/serializer.go.
      # All methods operate on BSV::Wallet::Wire::Writer / Reader instances.
      module Common
        COUNTERPARTY_SELF    = 11 # 0x0B
        COUNTERPARTY_ANYONE  = 12 # 0x0C
        PUBKEY_SIZE          = 33 # compressed secp256k1 public key

        module_function

        # Coerce a byte payload to a binary String (ASCII-8BIT encoding).
        #
        # Accepts either an Array<Integer> (as returned by ProtoWallet) or a
        # String. Serialisers use this so they remain compatible with both the
        # in-process wallet interface (Arrays) and the wire interface (Strings).
        def to_binary(bytes)
          return ''.b if bytes.nil?
          return bytes.pack('C*').b if bytes.is_a?(Array)

          bytes.b
        end

        # Encode a BRC-43 protocol ID: [security_level (0-2), protocol_name].
        #
        # Wire format: 1-byte security level + varint-len string.
        def write_protocol(writer, protocol_id)
          level, name = protocol_id
          writer.write_byte(level.to_i)
          writer.write_str_with_varint_len(name.to_s)
        end

        def read_protocol(reader)
          level = reader.read_byte
          name  = reader.read_str_with_varint_len
          [level, name]
        end

        # Encode a counterparty: 'self' | 'anyone' | 66-char hex compressed pubkey.
        #
        # Wire format:
        #   0x0B — self
        #   0x0C — anyone
        #   02/03 <32 bytes> — specific pubkey (first byte is the prefix of the 33-byte key)
        def write_counterparty(writer, counterparty)
          case counterparty
          when 'self'
            writer.write_byte(COUNTERPARTY_SELF)
          when 'anyone'
            writer.write_byte(COUNTERPARTY_ANYONE)
          else
            writer.write_bytes([counterparty].pack('H*'))
          end
        end

        def read_counterparty(reader)
          first = reader.read_byte
          case first
          when COUNTERPARTY_SELF
            'self'
          when COUNTERPARTY_ANYONE
            'anyone'
          else
            rest = reader.read_bytes(PUBKEY_SIZE - 1)
            ([first].pack('C') + rest).unpack1('H*')
          end
        end

        # Encode privileged flag + privileged_reason.
        #
        # Wire format: optional_bool (0xFF=nil, 0x00=false, 0x01=true) + reason as varint-len string,
        # or 0xFF if reason is nil/empty (NegativeOneByte sentinel).
        def write_privileged_params(writer, privileged, privileged_reason)
          writer.write_optional_bool(privileged)
          reason = privileged_reason.to_s
          if reason.empty?
            writer.write_byte(0xFF)
          else
            writer.write_str_with_varint_len(reason)
          end
        end

        def read_privileged_params(reader)
          privileged = reader.read_optional_bool
          # 0xFF as the leading byte is the nil-reason sentinel. Otherwise the
          # bytes start a Bitcoin varint length prefix (which can be 0xFD or
          # 0xFE for reasons >= 253 bytes; 0xFF would only collide if the
          # reason exceeded 4 GiB, which the protocol does not permit).
          if reader.peek_byte == 0xFF
            reader.read_byte
            [privileged, nil]
          else
            [privileged, reader.read_str_with_varint_len]
          end
        end

        # Encode key-related params: protocol + key_id + counterparty + privileged params.
        def write_key_related_params(writer, protocol_id:, key_id:, counterparty:,
                                     privileged: nil, privileged_reason: nil)
          write_protocol(writer, protocol_id)
          writer.write_str_with_varint_len(key_id.to_s)
          write_counterparty(writer, counterparty)
          write_privileged_params(writer, privileged, privileged_reason)
        end

        def read_key_related_params(reader)
          protocol_id       = read_protocol(reader)
          key_id            = reader.read_str_with_varint_len
          counterparty      = read_counterparty(reader)
          privileged, reason = read_privileged_params(reader)
          {
            protocol_id: protocol_id,
            key_id: key_id,
            counterparty: counterparty,
            privileged: privileged,
            privileged_reason: reason
          }
        end

        # Encode a list of outpoints (varint count + 32-byte wire-order txid + varint vout each).
        # Returns nil bytes for nil input.
        # @param outpoints [Array<String>, nil] array of "txid_hex.vout" strings
        # @return [String, nil] binary or nil
        def encode_outpoints(outpoints)
          return nil if outpoints.nil?

          w = Wire::Writer.new
          w.write_varint(outpoints.length)
          outpoints.each do |op|
            txid_hex, vout = op.split('.')
            w.write_bytes([txid_hex].pack('H*'))
            w.write_varint(vout.to_i)
          end
          w.buf
        end

        # Decode a list of outpoints from binary (encoded as encode_outpoints).
        # @param bytes [String, nil] binary data
        # @return [Array<String>, nil] array of "txid_hex.vout" strings
        def decode_outpoints(bytes)
          return nil if bytes.nil? || bytes.b.empty?

          r = Wire::Reader.new(bytes)
          count = r.read_varint
          return nil if count == 0xFFFF_FFFF_FFFF_FFFF

          count.times.map do
            txid_hex = r.read_bytes(32).unpack1('H*')
            vout = r.read_varint
            "#{txid_hex}.#{vout}"
          end
        end

        # Send-with result status codes (Go status.go).
        SEND_WITH_STATUS_UNPROVEN = 1
        SEND_WITH_STATUS_SENDING  = 2
        SEND_WITH_STATUS_FAILED   = 3

        SEND_WITH_STATUS_CODES = {
          unproven: SEND_WITH_STATUS_UNPROVEN,
          sending: SEND_WITH_STATUS_SENDING,
          failed: SEND_WITH_STATUS_FAILED
        }.freeze

        SEND_WITH_CODE_STATUSES = SEND_WITH_STATUS_CODES.invert.freeze

        # Write a send_with_results array: varint count + txid (32 bytes) + status byte each.
        # nil or empty → writes 0 count.
        # @param writer [Wire::Writer]
        # @param results [Array<Hash>, nil] array of { txid: String, status: Symbol }
        def write_send_with_results(writer, results)
          arr = results || []
          writer.write_varint(arr.length)
          arr.each do |res|
            writer.write_bytes([res[:txid]].pack('H*'))
            code = SEND_WITH_STATUS_CODES.fetch(res[:status]) do
              raise ArgumentError, "invalid send_with status: #{res[:status]}"
            end
            writer.write_byte(code)
          end
        end

        # Read a send_with_results array.
        # @param reader [Wire::Reader]
        # @return [Array<Hash>, nil]
        def read_send_with_results(reader)
          count = reader.read_varint
          return nil if count.zero?

          count.times.map do
            txid_hex = reader.read_bytes(32).unpack1('H*')
            code = reader.read_byte
            status = SEND_WITH_CODE_STATUSES.fetch(code) do
              raise ArgumentError, "invalid send_with status code: #{code}"
            end
            { txid: txid_hex, status: status }
          end
        end
      end
    end
  end
end
