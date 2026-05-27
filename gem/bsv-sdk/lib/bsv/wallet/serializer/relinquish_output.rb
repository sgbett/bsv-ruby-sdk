# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +relinquish_output+ call (call byte 7).
      #
      # Args wire layout:
      #   [varint-str: basket]
      #   [32-byte wire txid][4-byte LE vout]
      #
      # Result wire layout:
      #   [empty — relinquished is implicit from the frame error byte]
      module RelinquishOutput
        module_function

        def serialize_args(args)
          Wire::Validation.outpoint_string!('output', args[:output].to_s)
          txid_hex, vout = args[:output].to_s.split('.', 2)
          w = Wire::Writer.new
          w.write_str_with_varint_len(args.fetch(:basket, ''))
          w.write_outpoint(txid_hex, vout.to_i)
          w.buf
        end

        def deserialize_args(bytes)
          r = Wire::Reader.new(bytes)
          basket = r.read_str_with_varint_len
          outpoint_data = r.read_outpoint
          output = "#{outpoint_data[:txid_hex]}.#{outpoint_data[:vout]}"
          { basket: basket, output: output }
        end

        def serialize_result(_result)
          ''.b
        end

        def deserialize_result(_bytes)
          { relinquished: true }
        end
      end
    end
  end
end
