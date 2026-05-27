# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 serialiser for list_actions (call byte 4).
      #
      # Wire layout (port of go-sdk/wallet/serializer/list_actions.go):
      #
      # Args:
      #   [string_slice]     labels
      #   [1 byte]           label_query_mode: 0x01=any, 0x02=all, 0xFF=absent
      #   [go_optional_bool] include_labels
      #   [go_optional_bool] include_inputs
      #   [go_optional_bool] include_input_source_locking_scripts
      #   [go_optional_bool] include_input_unlocking_scripts
      #   [go_optional_bool] include_outputs
      #   [go_optional_bool] include_output_locking_scripts
      #   [optional_uint32]  limit
      #   [optional_uint32]  offset
      #   [go_optional_bool] seek_permission
      #
      # Result:
      #   [varint]           total_actions
      #   For each action:
      #     [32 bytes]       txid (display order — reversed from wire storage)
      #     [varint]         satoshis (int64 as varint)
      #     [1 byte]         status code
      #     [go_optional_bool ptr] is_outgoing (written as optional_bool pointer in Go)
      #     [string]         description
      #     [string_slice]   labels
      #     [varint]         version
      #     [varint]         lock_time
      #     [inputs]         NegativeOne | varint count + input_record…
      #     [outputs]        NegativeOne | varint count + output_record…
      #
      # Input record:
      #   [36 bytes] source_outpoint (32-byte wire txid + varint vout)
      #   [varint]   source_satoshis
      #   [int_bytes_optional] source_locking_script
      #   [int_bytes_optional] unlocking_script
      #   [string]   input_description
      #   [varint]   sequence_number
      #
      # Output record:
      #   [varint]   output_index
      #   [varint]   satoshis
      #   [int_bytes_optional] locking_script
      #   [go_optional_bool ptr] spendable
      #   [string]   output_description
      #   [string]   basket
      #   [string_slice] tags
      #   [optional_string] custom_instructions
      module ListActionsArgs
        LABEL_QUERY_MODE_ANY = 1
        LABEL_QUERY_MODE_ALL = 2

        module_function

        # @param args [Hash]
        # @return [String] binary
        def serialize(args)
          w = Wire::Writer.new

          w.write_string_slice(args[:labels])

          case args[:label_query_mode]
          when :any
            w.write_byte(LABEL_QUERY_MODE_ANY)
          when :all
            w.write_byte(LABEL_QUERY_MODE_ALL)
          else
            w.write_byte(0xFF)
          end

          w.write_go_optional_bool(args[:include_labels])
          w.write_go_optional_bool(args[:include_inputs])
          w.write_go_optional_bool(args[:include_input_source_locking_scripts])
          w.write_go_optional_bool(args[:include_input_unlocking_scripts])
          w.write_go_optional_bool(args[:include_outputs])
          w.write_go_optional_bool(args[:include_output_locking_scripts])

          w.write_optional_uint32(args[:limit])
          w.write_optional_uint32(args[:offset])
          w.write_go_optional_bool(args[:seek_permission])

          w.buf
        end

        # @param bytes [String] binary
        # @return [Hash]
        def deserialize(bytes)
          r = Wire::Reader.new(bytes)

          labels = r.read_string_slice

          mode_byte = r.read_byte
          label_query_mode = case mode_byte
                             when LABEL_QUERY_MODE_ANY then :any
                             when LABEL_QUERY_MODE_ALL then :all
                             end

          result = {}
          result[:labels]           = labels           unless labels.nil?
          result[:label_query_mode] = label_query_mode unless label_query_mode.nil?

          v = r.read_go_optional_bool
          result[:include_labels] = v unless v.nil?
          v = r.read_go_optional_bool
          result[:include_inputs] = v unless v.nil?
          v = r.read_go_optional_bool
          result[:include_input_source_locking_scripts] = v unless v.nil?
          v = r.read_go_optional_bool
          result[:include_input_unlocking_scripts] = v unless v.nil?
          v = r.read_go_optional_bool
          result[:include_outputs] = v unless v.nil?
          v = r.read_go_optional_bool
          result[:include_output_locking_scripts] = v unless v.nil?

          lim = r.read_optional_uint32
          result[:limit] = lim unless lim.nil?
          off = r.read_optional_uint32
          result[:offset] = off unless off.nil?

          v = r.read_go_optional_bool
          result[:seek_permission] = v unless v.nil?

          result
        end
      end

      module ListActionsResult
        ACTION_STATUS_CODES = {
          completed: 1,
          unprocessed: 2,
          sending: 3,
          unproven: 4,
          unsigned: 5,
          no_send: 6,
          non_final: 7
        }.freeze

        ACTION_CODE_STATUSES = ACTION_STATUS_CODES.invert.freeze

        module_function

        # @param result [Hash] { total_actions: Integer, actions: Array<Hash> }
        # @return [String] binary
        def serialize(result)
          w = Wire::Writer.new

          actions = result[:actions] || []
          w.write_varint(actions.length)

          actions.each do |action|
            txid_hex = action[:txid].to_s
            w.write_bytes([txid_hex].pack('H*').reverse)
            w.write_varint(action[:satoshis].to_i)

            code = ACTION_STATUS_CODES.fetch(action[:status]) do
              raise ArgumentError, "invalid action status: #{action[:status]}"
            end
            w.write_byte(code)

            # is_outgoing: non-optional bool written as optional_bool pointer in Go
            w.write_byte(action[:is_outgoing] ? 1 : 0)

            w.write_string(action[:description].to_s)
            w.write_string_slice(action[:labels])
            w.write_varint(action[:version].to_i)
            w.write_varint(action[:lock_time].to_i)

            serialize_action_inputs(w, action[:inputs])
            serialize_action_outputs(w, action[:outputs])
          end

          w.buf
        end

        # @param bytes [String] binary
        # @return [Hash]
        def deserialize(bytes)
          r = Wire::Reader.new(bytes)

          total = r.read_varint
          actions = total.times.map do
            txid_hex = r.read_bytes(32).reverse.unpack1('H*')
            satoshis = r.read_varint
            code     = r.read_byte
            status   = ACTION_CODE_STATUSES.fetch(code) do
              raise ArgumentError, "invalid action status code: #{code}"
            end

            is_outgoing = r.read_byte == 1
            description = r.read_string
            labels      = r.read_string_slice
            version     = r.read_varint
            lock_time   = r.read_varint

            inputs  = deserialize_action_inputs(r)
            outputs = deserialize_action_outputs(r)

            action = {
              txid: txid_hex,
              satoshis: satoshis,
              status: status,
              is_outgoing: is_outgoing,
              description: description,
              version: version,
              lock_time: lock_time
            }
            action[:labels]  = labels  unless labels.nil?
            action[:inputs]  = inputs  unless inputs.nil?
            action[:outputs] = outputs unless outputs.nil?
            action
          end

          { total_actions: total, actions: actions }
        end

        def serialize_action_inputs(writer, inputs)
          if inputs.nil? || inputs.empty?
            writer.write_negative_one
            return
          end

          writer.write_varint(inputs.length)
          inputs.each do |inp|
            txid_hex, vout = inp[:source_outpoint].split('.')
            writer.write_bytes([txid_hex].pack('H*').reverse)
            writer.write_varint(vout.to_i)

            writer.write_varint(inp[:source_satoshis].to_i)

            script = inp[:source_locking_script]
            if script && !script.b.empty?
              writer.write_int_bytes(script)
            else
              writer.write_negative_one
            end

            unlock_script = inp[:unlocking_script]
            if unlock_script && !unlock_script.b.empty?
              writer.write_int_bytes(unlock_script)
            else
              writer.write_negative_one
            end

            writer.write_string(inp[:input_description].to_s)
            writer.write_varint(inp[:sequence_number].to_i)
          end
        end

        def serialize_action_outputs(writer, outputs)
          if outputs.nil? || outputs.empty?
            writer.write_negative_one
            return
          end

          writer.write_varint(outputs.length)
          outputs.each do |out|
            writer.write_varint(out[:output_index].to_i)
            writer.write_varint(out[:satoshis].to_i)

            script = out[:locking_script]
            if script && !script.b.empty?
              writer.write_int_bytes(script)
            else
              writer.write_negative_one
            end

            writer.write_byte(out[:spendable] ? 1 : 0)
            writer.write_string(out[:output_description].to_s)
            writer.write_string(out[:basket].to_s)
            writer.write_string_slice(out[:tags])
            writer.write_optional_string(out[:custom_instructions])
          end
        end

        def deserialize_action_inputs(reader)
          count = reader.read_varint
          return nil if count == 0xFFFF_FFFF_FFFF_FFFF

          count.times.map do
            txid_hex = reader.read_bytes(32).reverse.unpack1('H*')
            vout     = reader.read_varint
            source_outpoint = "#{txid_hex}.#{vout}"

            source_satoshis = reader.read_varint

            source_locking_script = reader.read_int_bytes
            source_locking_script = nil if source_locking_script.empty?

            unlocking_script = reader.read_int_bytes
            unlocking_script = nil if unlocking_script.empty?

            input_description = reader.read_string
            sequence_number   = reader.read_varint

            inp = {
              source_outpoint: source_outpoint,
              source_satoshis: source_satoshis,
              input_description: input_description,
              sequence_number: sequence_number
            }
            inp[:source_locking_script] = source_locking_script unless source_locking_script.nil?
            inp[:unlocking_script]      = unlocking_script      unless unlocking_script.nil?
            inp
          end
        end

        def deserialize_action_outputs(reader)
          count = reader.read_varint
          return nil if count == 0xFFFF_FFFF_FFFF_FFFF

          count.times.map do
            output_index = reader.read_varint
            satoshis     = reader.read_varint

            locking_script = reader.read_int_bytes
            locking_script = nil if locking_script.empty?

            spendable = reader.read_byte == 1
            output_description = reader.read_string
            basket            = reader.read_string
            tags              = reader.read_string_slice
            custom            = reader.read_optional_string

            out = {
              output_index: output_index,
              satoshis: satoshis,
              spendable: spendable,
              output_description: output_description,
              basket: basket
            }
            out[:locking_script]      = locking_script unless locking_script.nil?
            out[:tags]                = tags           unless tags.nil?
            out[:custom_instructions] = custom         unless custom.nil?
            out
          end
        end

        private_class_method :serialize_action_inputs, :serialize_action_outputs,
                             :deserialize_action_inputs, :deserialize_action_outputs
      end
    end
  end
end
