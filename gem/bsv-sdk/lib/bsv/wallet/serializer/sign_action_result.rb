# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 serialiser for sign_action result (call byte 2).
      #
      # Wire layout (port of go-sdk/wallet/serializer/sign_action_result.go):
      #   [flag + 32 bytes] txid with flag byte: 0=absent, 1=present (wire-order)
      #   [flag + int_bytes] tx (BEEF bytes) with flag byte: 0=absent, 1=present + varint_len
      #   [send_with_results] varint count + txid (32 bytes) + status_byte each
      module SignActionResult
        module_function

        # @param result [Hash]
        # @return [String] binary
        def serialize(result)
          w = Wire::Writer.new

          txid_bytes = result[:txid] ? [result[:txid]].pack('H*').reverse : nil
          w.write_optional_bytes_with_flag(txid_bytes, fixed_size: 32)
          w.write_optional_bytes_with_flag(result[:tx])

          Common.write_send_with_results(w, result[:send_with_results])

          w.buf
        end

        # @param bytes [String] binary
        # @return [Hash]
        def deserialize(bytes)
          r = Wire::Reader.new(bytes)

          txid_raw = r.read_optional_bytes_with_flag(fixed_size: 32)
          txid_hex = txid_raw&.reverse&.unpack1('H*')
          tx       = r.read_optional_bytes_with_flag

          send_with_results = Common.read_send_with_results(r)

          result = {}
          result[:txid]              = txid_hex          unless txid_hex.nil?
          result[:tx]                = tx                unless tx.nil?
          result[:send_with_results] = send_with_results unless send_with_results.nil?
          result
        end
      end
    end
  end
end
