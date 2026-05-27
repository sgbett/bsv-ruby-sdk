# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 serialiser for create_action args (call byte 1).
      #
      # Wire layout (port of go-sdk/wallet/serializer/create_action_args.go):
      #   [string]          description
      #   [optional_bytes]  input_beef (NegativeOne = nil)
      #   [inputs]          NegativeOne | varint_count + input_record…
      #   [outputs]         NegativeOne | varint_count + output_record…
      #   [optional_uint32] lock_time
      #   [optional_uint32] version
      #   [string_slice]    labels
      #   [options_block]   0x00 = absent | 0x01 + fields
      #
      # Input record:
      #   [32 bytes] outpoint txid (wire order)
      #   [varint]   outpoint vout
      #   [int_bytes or NegativeOne + varint] unlocking_script or length placeholder
      #   [string]   input_description
      #   [optional_uint32] sequence_number
      #
      # Output record:
      #   [int_bytes] locking_script
      #   [varint]    satoshis
      #   [string]    output_description
      #   [optional_string] basket
      #   [optional_string] custom_instructions
      #   [string_slice] tags
      #
      # Options block (after 0x01 presence byte):
      #   [optional_bool] sign_and_process
      #   [optional_bool] accept_delayed_broadcast
      #   [0x01 or 0xFF]     trust_self (1=known, 0xFF=absent)
      #   [txid_slice]       known_txids
      #   [optional_bool] return_txid_only
      #   [optional_bool] no_send
      #   [optional_bytes]   no_send_change (encoded outpoints, NegativeOne = nil)
      #   [txid_slice]       send_with
      #   [optional_bool] randomize_outputs
      module CreateActionArgs
        TRUST_SELF_KNOWN = 1

        module_function

        # @param args [Hash]
        # @return [String] binary
        def serialize(args)
          w = Wire::Writer.new

          w.write_string(args[:description].to_s)
          w.write_int_bytes(args[:input_beef])

          serialize_inputs(w, args[:inputs])
          serialize_outputs(w, args[:outputs])

          w.write_optional_uint32(args[:lock_time])
          w.write_optional_uint32(args[:version])
          w.write_string_slice(args[:labels])

          serialize_options(w, args[:options])

          w.buf
        end

        # @param bytes [String] binary
        # @return [Hash]
        def deserialize(bytes)
          raise ArgumentError, 'empty message' if bytes.b.empty?

          r = Wire::Reader.new(bytes)

          description = r.read_string
          input_beef  = r.read_int_bytes
          input_beef  = nil if input_beef.empty?

          inputs  = deserialize_inputs(r)
          outputs = deserialize_outputs(r)

          lock_time = r.read_optional_uint32
          version   = r.read_optional_uint32
          labels    = r.read_string_slice

          options = deserialize_options(r)

          result = { description: description }
          result[:input_beef] = input_beef unless input_beef.nil?
          result[:inputs]  = inputs  unless inputs.nil?
          result[:outputs] = outputs unless outputs.nil?
          result[:lock_time] = lock_time unless lock_time.nil?
          result[:version]   = version   unless version.nil?
          result[:labels]    = labels    unless labels.nil?
          result[:options]   = options   unless options.nil?
          result
        end

        def serialize_inputs(writer, inputs)
          if inputs.nil?
            writer.write_negative_one
            return
          end

          writer.write_varint(inputs.length)
          inputs.each do |inp|
            txid_hex, vout = inp[:outpoint].split('.')
            writer.write_bytes([txid_hex].pack('H*').reverse)
            writer.write_varint(vout.to_i)

            script = inp[:unlocking_script]
            if script && !script.b.empty?
              writer.write_int_bytes(script)
            else
              writer.write_negative_one
              writer.write_varint(inp[:unlocking_script_length].to_i)
            end

            writer.write_string(inp[:input_description].to_s)
            writer.write_optional_uint32(inp[:sequence_number])
          end
        end

        def serialize_outputs(writer, outputs)
          if outputs.nil?
            writer.write_negative_one
            return
          end

          writer.write_varint(outputs.length)
          outputs.each do |out|
            writer.write_int_bytes(out[:locking_script])
            writer.write_varint(out[:satoshis].to_i)
            writer.write_string(out[:output_description].to_s)
            writer.write_optional_string(out[:basket])
            writer.write_optional_string(out[:custom_instructions])
            writer.write_string_slice(out[:tags])
          end
        end

        def serialize_options(writer, opts)
          if opts.nil?
            writer.write_byte(0)
            return
          end

          writer.write_byte(1)
          writer.write_optional_bool(opts[:sign_and_process])
          writer.write_optional_bool(opts[:accept_delayed_broadcast])

          if opts[:trust_self] == :known
            writer.write_byte(TRUST_SELF_KNOWN)
          else
            writer.write_byte(0xFF)
          end

          writer.write_txid_slice(opts[:known_txids])
          writer.write_optional_bool(opts[:return_txid_only])
          writer.write_optional_bool(opts[:no_send])

          no_send_change_bytes = Common.encode_outpoints(opts[:no_send_change])
          writer.write_int_bytes(no_send_change_bytes)

          writer.write_txid_slice(opts[:send_with])
          writer.write_optional_bool(opts[:randomize_outputs])
        end

        def deserialize_inputs(reader)
          count = reader.read_varint
          return nil if count == 0xFFFF_FFFF_FFFF_FFFF

          count.times.map do
            txid_hex = reader.read_bytes(32).reverse.unpack1('H*')
            vout     = reader.read_varint
            outpoint = "#{txid_hex}.#{vout}"

            script_len = reader.read_varint
            inp = { outpoint: outpoint }

            if script_len == 0xFFFF_FFFF_FFFF_FFFF
              length = reader.read_varint
              inp[:unlocking_script_length] = length
            else
              script = reader.read_bytes(script_len)
              inp[:unlocking_script] = script
              inp[:unlocking_script_length] = script_len
            end

            inp[:input_description] = reader.read_string
            seq = reader.read_optional_uint32
            inp[:sequence_number] = seq unless seq.nil?
            inp
          end
        end

        def deserialize_outputs(reader)
          count = reader.read_varint
          return nil if count == 0xFFFF_FFFF_FFFF_FFFF

          count.times.map do
            script   = reader.read_int_bytes
            satoshis = reader.read_varint
            out_desc = reader.read_string
            basket   = reader.read_optional_string
            custom   = reader.read_optional_string
            tags     = reader.read_string_slice

            out = { locking_script: script, satoshis: satoshis, output_description: out_desc }
            out[:basket]              = basket unless basket.nil?
            out[:custom_instructions] = custom unless custom.nil?
            out[:tags]                = tags   unless tags.nil?
            out
          end
        end

        def deserialize_options(reader)
          return nil if reader.read_byte != 1

          opts = {}

          sign_and_process         = reader.read_optional_bool
          accept_delayed_broadcast = reader.read_optional_bool

          trust_byte = reader.read_byte
          trust_self = trust_byte == TRUST_SELF_KNOWN ? :known : nil

          known_txids = reader.read_txid_slice
          return_txid_only = reader.read_optional_bool
          no_send          = reader.read_optional_bool

          no_send_change_bytes = reader.read_int_bytes
          no_send_change = Common.decode_outpoints(no_send_change_bytes.empty? ? nil : no_send_change_bytes)

          send_with          = reader.read_txid_slice
          randomize_outputs  = reader.read_optional_bool

          opts[:sign_and_process]          = sign_and_process         unless sign_and_process.nil?
          opts[:accept_delayed_broadcast]  = accept_delayed_broadcast unless accept_delayed_broadcast.nil?
          opts[:trust_self]                = trust_self                unless trust_self.nil?
          opts[:known_txids]               = known_txids               unless known_txids.nil?
          opts[:return_txid_only]          = return_txid_only          unless return_txid_only.nil?
          opts[:no_send]                   = no_send                   unless no_send.nil?
          opts[:no_send_change]            = no_send_change            unless no_send_change.nil?
          opts[:send_with]                 = send_with                 unless send_with.nil?
          opts[:randomize_outputs]         = randomize_outputs         unless randomize_outputs.nil?
          opts
        end

        private_class_method :serialize_inputs, :serialize_outputs, :serialize_options,
                             :deserialize_inputs, :deserialize_outputs, :deserialize_options
      end
    end
  end
end
