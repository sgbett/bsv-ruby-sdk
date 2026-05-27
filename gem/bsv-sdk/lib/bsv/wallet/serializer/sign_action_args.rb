# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 serialiser for sign_action args (call byte 2).
      #
      # Wire layout (port of go-sdk/wallet/serializer/sign_action_args.go):
      #   [varint]     spends count
      #   For each spend (sorted by input_index):
      #     [varint]   input_index
      #     [int_bytes] unlocking_script
      #     [optional_uint32] sequence_number
      #   [int_bytes]  reference
      #   [1 byte]     options present flag (0=absent, 1=present)
      #   If options present:
      #     [go_optional_bool] accept_delayed_broadcast
      #     [go_optional_bool] return_txid_only
      #     [go_optional_bool] no_send
      #     [txid_slice]       send_with
      module SignActionArgs
        module_function

        # @param args [Hash]
        # @return [String] binary
        def serialize(args)
          w = Wire::Writer.new

          spends = args[:spends] || {}
          w.write_varint(spends.length)
          spends.keys.sort.each do |idx|
            spend = spends[idx]
            w.write_varint(idx)
            w.write_int_bytes(spend[:unlocking_script])
            w.write_optional_uint32(spend[:sequence_number])
          end

          w.write_int_bytes(args[:reference])

          opts = args[:options]
          if opts
            w.write_byte(1)
            w.write_go_optional_bool(opts[:accept_delayed_broadcast])
            w.write_go_optional_bool(opts[:return_txid_only])
            w.write_go_optional_bool(opts[:no_send])
            w.write_txid_slice(opts[:send_with])
          else
            w.write_byte(0)
          end

          w.buf
        end

        # @param bytes [String] binary
        # @return [Hash]
        def deserialize(bytes)
          r = Wire::Reader.new(bytes)

          spend_count = r.read_varint
          spends = {}
          spend_count.times do
            idx    = r.read_varint
            script = r.read_int_bytes
            seq    = r.read_optional_uint32
            spend  = { unlocking_script: script }
            spend[:sequence_number] = seq unless seq.nil?
            spends[idx] = spend
          end

          reference = r.read_int_bytes

          options_present = r.read_byte
          options = if options_present == 1
                      opts = {}
                      v = r.read_go_optional_bool
                      opts[:accept_delayed_broadcast] = v unless v.nil?
                      v = r.read_go_optional_bool
                      opts[:return_txid_only] = v unless v.nil?
                      v = r.read_go_optional_bool
                      opts[:no_send] = v unless v.nil?
                      sw = r.read_txid_slice
                      opts[:send_with] = sw unless sw.nil?
                      opts
                    end

          result = { spends: spends }
          result[:reference] = reference unless reference.nil? || reference.empty?
          result[:options]   = options   unless options.nil?
          result
        end
      end
    end
  end
end
