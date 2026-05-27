# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +list_outputs+ call (call byte 6).
      #
      # Args wire layout:
      #   [varint-str: basket]
      #   [string-slice: tags]  nil → NegativeOne
      #   [1 byte: tag_query_mode]  1=all, 2=any, 0xFF=nil
      #   [1 byte: include]  1=locking_scripts, 2=entire_transactions, 0xFF=nil
      #   [optional_bool: include_custom_instructions]
      #   [optional_bool: include_tags]
      #   [optional_bool: include_labels]
      #   [optional_uint32: limit]
      #   [optional_uint32: offset]
      #   [optional_bool: seek_permission]
      #
      # Result wire layout:
      #   [varint: total_outputs]
      #   [varint: beef_len, or NegativeOne if nil][beef bytes]
      #   per output:
      #     [32-byte wire txid][4-byte LE vout]
      #     [varint: satoshis]
      #     [varint: locking_script_len, or NegativeOne][script bytes]
      #     [varint-str: custom_instructions]  0-length string if nil
      #     [string-slice: tags]
      #     [string-slice: labels]
      module ListOutputs
        TAG_QUERY_MODE_ALL = 1
        TAG_QUERY_MODE_ANY = 2
        INCLUDE_LOCKING_SCRIPTS     = 1
        INCLUDE_ENTIRE_TRANSACTIONS = 2
        NEGATIVE_ONE_BYTE = 0xFF

        module_function

        def serialize_args(args)
          w = Wire::Writer.new
          w.write_str_with_varint_len(args.fetch(:basket, ''))
          w.write_string_slice(args[:tags])

          mode_byte = case args[:tag_query_mode]
                      when :all then TAG_QUERY_MODE_ALL
                      when :any then TAG_QUERY_MODE_ANY
                      else           NEGATIVE_ONE_BYTE
                      end
          w.write_byte(mode_byte)

          include_byte = case args[:include]
                         when :locking_scripts      then INCLUDE_LOCKING_SCRIPTS
                         when :entire_transactions  then INCLUDE_ENTIRE_TRANSACTIONS
                         else                            NEGATIVE_ONE_BYTE
                         end
          w.write_byte(include_byte)

          w.write_optional_bool(args[:include_custom_instructions])
          w.write_optional_bool(args[:include_tags])
          w.write_optional_bool(args[:include_labels])
          w.write_optional_uint32(args[:limit])
          w.write_optional_uint32(args[:offset])
          w.write_optional_bool(args[:seek_permission])
          w.buf
        end

        def deserialize_args(bytes)
          r = Wire::Reader.new(bytes)
          basket = r.read_str_with_varint_len
          tags   = r.read_string_slice

          mode = case r.read_byte
                 when TAG_QUERY_MODE_ALL then :all
                 when TAG_QUERY_MODE_ANY then :any
                 end

          inc = case r.read_byte
                when INCLUDE_LOCKING_SCRIPTS     then :locking_scripts
                when INCLUDE_ENTIRE_TRANSACTIONS then :entire_transactions
                end

          {
            basket: basket,
            tags: tags,
            tag_query_mode: mode,
            include: inc,
            include_custom_instructions: r.read_optional_bool,
            include_tags: r.read_optional_bool,
            include_labels: r.read_optional_bool,
            limit: r.read_optional_uint32,
            offset: r.read_optional_uint32,
            seek_permission: r.read_optional_bool
          }
        end

        def serialize_result(result)
          w = Wire::Writer.new
          outputs = result[:outputs] || []
          w.write_varint(outputs.length)

          beef = result[:beef]
          if beef
            w.write_int_bytes(beef.b)
          else
            w.write_negative_one
          end

          outputs.each do |output|
            outpoint = output[:outpoint] || ''
            txid_hex, vout = outpoint.to_s.split('.', 2)
            w.write_outpoint(txid_hex.to_s, vout.to_i)
            w.write_varint(output[:satoshis].to_i)
            locking_script = output[:locking_script]
            if locking_script && !locking_script.empty?
              w.write_int_bytes(locking_script.b)
            else
              w.write_negative_one
            end
            w.write_str_with_varint_len(output[:custom_instructions].to_s)
            w.write_string_slice(output[:tags])
            w.write_string_slice(output[:labels])
          end
          w.buf
        end

        def deserialize_result(bytes)
          r = Wire::Reader.new(bytes)
          total_outputs = r.read_varint

          beef_len = r.read_varint
          beef = if beef_len == 0xFFFF_FFFF_FFFF_FFFF
                   nil
                 else
                   r.read_bytes(beef_len)
                 end

          outputs = total_outputs.times.map do
            outpoint_data = r.read_outpoint
            outpoint = "#{outpoint_data[:txid_hex]}.#{outpoint_data[:vout]}"
            satoshis = r.read_varint
            locking_script_len = r.read_varint
            locking_script = if locking_script_len == 0xFFFF_FFFF_FFFF_FFFF
                               nil
                             else
                               r.read_bytes(locking_script_len)
                             end
            custom_instructions = r.read_str_with_varint_len
            tags   = r.read_string_slice
            labels = r.read_string_slice

            {
              outpoint: outpoint,
              satoshis: satoshis,
              locking_script: locking_script,
              custom_instructions: custom_instructions.empty? ? nil : custom_instructions,
              tags: tags,
              labels: labels,
              spendable: true
            }
          end

          { total_outputs: total_outputs, beef: beef, outputs: outputs }
        end
      end
    end
  end
end
