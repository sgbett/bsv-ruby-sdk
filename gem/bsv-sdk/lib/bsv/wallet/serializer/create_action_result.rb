# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 serialiser for create_action result (call byte 1).
      #
      # Wire layout (port of go-sdk/wallet/serializer/create_action_result.go):
      #   [1 byte]           0x00 success sentinel (frame-level, already checked by Frame)
      #   [flag + 32 bytes]  txid (wire-order) with flag byte: 0=absent, 1=present
      #   [flag + int_bytes] tx (BEEF bytes) with flag byte: 0=absent, 1=present + varint_len
      #   [optional_bytes]   no_send_change encoded outpoints (NegativeOne = nil)
      #   [send_with_results] varint count + txid + status_byte each
      #   [1 byte flag]      signable_transaction: 0=absent, 1=present
      #   If signable_transaction present:
      #     [int_bytes]      tx (BEEF bytes)
      #     [int_bytes]      reference bytes
      module CreateActionResult
        module_function

        # @param result [Hash]
        # @return [String] binary
        def serialize(result)
          w = Wire::Writer.new
          w.write_byte(0) # success sentinel

          txid_bytes = result[:txid] ? [result[:txid]].pack('H*').reverse : nil
          w.write_optional_bytes_with_flag(txid_bytes, fixed_size: 32)
          w.write_optional_bytes_with_flag(result[:tx])

          no_send_change_bytes = Common.encode_outpoints(result[:no_send_change])
          w.write_int_bytes(no_send_change_bytes)

          Common.write_send_with_results(w, result[:send_with_results])

          signable = result[:signable_transaction]
          if signable
            w.write_byte(1)
            w.write_int_bytes(signable[:tx])
            w.write_int_bytes(signable[:reference])
          else
            w.write_byte(0)
          end

          w.buf
        end

        # @param bytes [String] binary
        # @return [Hash]
        def deserialize(bytes)
          raise ArgumentError, 'empty response data' if bytes.b.empty?

          r = Wire::Reader.new(bytes)

          status = r.read_byte
          raise ArgumentError, "response indicates failure: #{status}" unless status.zero?

          txid_raw = r.read_optional_bytes_with_flag(fixed_size: 32)
          txid_hex = txid_raw&.reverse&.unpack1('H*')
          tx       = r.read_optional_bytes_with_flag

          no_send_change_bytes = r.read_int_bytes
          no_send_change = Common.decode_outpoints(no_send_change_bytes.empty? ? nil : no_send_change_bytes)

          send_with_results = Common.read_send_with_results(r)

          signable_flag = r.read_byte
          signable_transaction = if signable_flag == 1
                                   tx_bytes  = r.read_int_bytes
                                   ref_bytes = r.read_int_bytes
                                   { tx: tx_bytes, reference: ref_bytes }
                                 end

          result = {}
          result[:txid]                = txid_hex            unless txid_hex.nil?
          result[:tx]                  = tx                  unless tx.nil?
          result[:no_send_change]      = no_send_change      unless no_send_change.nil?
          result[:send_with_results]   = send_with_results   unless send_with_results.nil?
          result[:signable_transaction] = signable_transaction unless signable_transaction.nil?
          result
        end
      end
    end
  end
end
