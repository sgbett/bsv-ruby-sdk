# frozen_string_literal: true

module BSV
  module Wallet
    module Wire
      # Serialises and deserialises all 28 BRC-100 wire protocol method calls.
      #
      # Frame layout:
      #   Request:  [UInt8 call_code] [UInt8 originator_length] [UTF-8 originator] [params…]
      #   Response: [UInt8 error_code] [result…]
      #   Error:    [UInt8 error_code ≠ 0] [VarInt msg_len] [UTF-8 message] [VarInt stack_len] [UTF-8 stack]
      #
      # For every method:
      #   serialize_request(method_name, args, originator:)  → binary String
      #   deserialize_request(data)                          → [method_name, args, originator]
      #   serialize_response(method_name, result)            → binary String (error_code=0 prefix)
      #   deserialize_response(method_name, data)            → result Hash  (raises on error_code≠0)
      #   serialize_error(code, message, stack_trace:)       → binary String
      module Serializer
        # Maps method name symbols to their wire call codes (1-28).
        CALL_CODES = {
          create_action: 1,
          sign_action: 2,
          abort_action: 3,
          list_actions: 4,
          internalize_action: 5,
          list_outputs: 6,
          relinquish_output: 7,
          get_public_key: 8,
          reveal_counterparty_key_linkage: 9,
          reveal_specific_key_linkage: 10,
          encrypt: 11,
          decrypt: 12,
          create_hmac: 13,
          verify_hmac: 14,
          create_signature: 15,
          verify_signature: 16,
          acquire_certificate: 17,
          list_certificates: 18,
          prove_certificate: 19,
          relinquish_certificate: 20,
          discover_by_identity_key: 21,
          discover_by_attributes: 22,
          is_authenticated: 23,
          wait_for_authentication: 24,
          get_height: 25,
          get_header_for_height: 26,
          get_network: 27,
          get_version: 28
        }.freeze

        # Inverse mapping: call code Integer → method name Symbol.
        METHODS_BY_CODE = CALL_CODES.invert.freeze

        module_function

        # Serialises a method call request into a binary frame.
        #
        # @param method_name [Symbol]
        # @param args [Hash]
        # @param originator [String, nil] FQDN of the calling application
        # @return [String] binary frame (ASCII-8BIT)
        def serialize_request(method_name, args, originator: nil)
          code = CALL_CODES.fetch(method_name) do
            raise ArgumentError, "unknown method: #{method_name}"
          end

          w = Writer.new
          w.write_byte(code)

          orig = originator.to_s
          orig_bytes = orig.encode('UTF-8').b
          w.write_byte(orig_bytes.bytesize)
          w.write_bytes(orig_bytes)

          params_writer = Writer.new
          send(:"write_#{method_name}_params", params_writer, args)
          w.write_bytes(params_writer.to_binary)

          w.to_binary
        end

        # Deserialises a binary request frame.
        #
        # @param data [String] binary frame
        # @return [Array(Symbol, Hash, String)] [method_name, args, originator]
        def deserialize_request(data)
          r = Reader.new(data)
          code = r.read_byte
          method_name = METHODS_BY_CODE.fetch(code) do
            raise ArgumentError, "unknown call code: #{code}"
          end

          orig_len = r.read_byte
          originator = r.read_bytes(orig_len).force_encoding('UTF-8')

          args = send(:"read_#{method_name}_params", r)
          [method_name, args, originator]
        end

        # Serialises a successful response.
        #
        # @param method_name [Symbol]
        # @param result [Hash]
        # @return [String] binary frame
        def serialize_response(method_name, result)
          w = Writer.new
          w.write_byte(0) # error_code = 0
          result_writer = Writer.new
          send(:"write_#{method_name}_result", result_writer, result)
          w.write_bytes(result_writer.to_binary)
          w.to_binary
        end

        # Serialises an error response.
        #
        # @param code [Integer] non-zero error code
        # @param message [String]
        # @param stack_trace [String, nil]
        # @return [String] binary frame
        def serialize_error(code, message, stack_trace: nil)
          w = Writer.new
          w.write_byte(code)
          w.write_utf8_string(message.to_s)
          w.write_utf8_string(stack_trace.to_s)
          w.to_binary
        end

        # Deserialises a response frame, raising a WalletError on non-zero error code.
        #
        # @param method_name [Symbol]
        # @param data [String] binary frame
        # @return [Hash] result
        def deserialize_response(method_name, data)
          r = Reader.new(data)
          error_code = r.read_byte

          unless error_code.zero?
            message = r.read_utf8_string
            raise BSV::Wallet::WalletError.new(message, error_code)
          end

          send(:"read_#{method_name}_result", r)
        end

        # -----------------------------------------------------------------------
        # Private helpers — all defined via module_function so they become
        # private module-level methods callable from within the module.
        # -----------------------------------------------------------------------

        # --- write_outpoint / read_outpoint helpers ---

        def write_outpoint_str(w, outpoint_str)
          txid, index = outpoint_str.split('.')
          w.write_outpoint(txid, index.to_i)
        end

        def read_outpoint_str(r)
          txid, index = r.read_outpoint
          "#{txid}.#{index}"
        end

        # --- key-related params (shared by encrypt/decrypt/hmac/signature/revealSpecific) ---

        def write_key_related_params(w, args)
          w.write_protocol_id(args[:protocol_id])
          w.write_utf8_string(args[:key_id].to_s)
          w.write_counterparty(args[:counterparty])
          w.write_privileged(args[:privileged], args[:privileged_reason])
        end

        # Reads key-related params: protocolID, keyID, counterparty, privileged, privilegedReason.
        def read_key_related_from_reader(r)
          protocol_id = r.read_protocol_id
          key_id = r.read_utf8_string
          counterparty = r.read_counterparty
          privileged, privileged_reason = r.read_privileged
          {
            protocol_id: protocol_id,
            key_id: key_id,
            counterparty: counterparty,
            privileged: privileged,
            privileged_reason: privileged_reason
          }
        end

        # --- certificate binary encoding helpers ---

        # Writes a certificate struct to the writer (without length prefix).
        def write_certificate_fields(w, cert)
          # type: 32 bytes (base64-decoded)
          w.write_bytes(decode_base64_32(cert[:type]))
          # subject: 33 bytes (hex-decoded compressed pubkey)
          w.write_bytes([cert[:subject]].pack('H*'))
          # serial_number: 32 bytes (base64-decoded)
          w.write_bytes(decode_base64_32(cert[:serial_number]))
          # certifier: 33 bytes
          w.write_bytes([cert[:certifier]].pack('H*'))
          # revocation_outpoint
          write_outpoint_str(w, cert[:revocation_outpoint])
          # signature: VarInt-prefixed hex
          sig_bytes = [cert[:signature]].pack('H*')
          w.write_varint(sig_bytes.bytesize)
          w.write_bytes(sig_bytes)
          # fields: map
          fields = cert[:fields] || {}
          w.write_varint(fields.length)
          fields.each do |k, v|
            w.write_utf8_string(k.to_s)
            w.write_utf8_string(v.to_s)
          end
        end

        # Reads a certificate struct from the reader (without length prefix).
        def read_cert_from_reader(r)
          require 'base64'
          type = encode_base64(r.read_bytes(32))
          subject = r.read_bytes(33).unpack1('H*')
          serial_number = encode_base64(r.read_bytes(32))
          certifier = r.read_bytes(33).unpack1('H*')
          revocation_outpoint = read_outpoint_str(r)
          sig_len = r.read_varint
          signature = r.read_bytes(sig_len).unpack1('H*')
          fields_count = r.read_varint
          fields = {}
          fields_count.times do
            k = r.read_utf8_string
            v = r.read_utf8_string
            fields[k] = v
          end
          {
            type: type,
            subject: subject,
            serial_number: serial_number,
            certifier: certifier,
            revocation_outpoint: revocation_outpoint,
            signature: signature,
            fields: fields
          }
        end

        def decode_base64_32(b64_str)
          require 'base64'
          raw = Base64.strict_decode64(b64_str)
          raise ArgumentError, "expected 32-byte base64 value, got #{raw.bytesize}" unless raw.bytesize == 32

          raw
        end

        def encode_base64(raw_bytes)
          require 'base64'
          Base64.strict_encode64(raw_bytes)
        end

        # Serialises a discovery certificate result (shared by discoverByIdentityKey/Attributes).
        def write_discovery_result(w, result)
          certs = result[:certificates] || []
          w.write_varint(result[:total_certificates] || certs.length)
          certs.each do |cert|
            # Write certificate binary (length-prefixed)
            cert_w = Writer.new
            write_certificate_fields(cert_w, cert)
            cert_bin = cert_w.to_binary
            w.write_varint(cert_bin.bytesize)
            w.write_bytes(cert_bin)

            # certifierInfo
            info = cert[:certifier_info] || {}
            w.write_utf8_string(info[:name].to_s)
            w.write_utf8_string(info[:icon_url].to_s)
            w.write_utf8_string(info[:description].to_s)
            w.write_byte(info[:trust].to_i)

            # publiclyRevealedKeyring: map of field→base64
            keyring = cert[:publicly_revealed_keyring] || {}
            w.write_varint(keyring.length)
            keyring.each do |k, v|
              w.write_utf8_string(k.to_s)
              val_bytes = decode_base64_32_safe(v.to_s)
              w.write_varint(val_bytes.bytesize)
              w.write_bytes(val_bytes)
            end

            # decryptedFields: map of field→utf8
            decrypted = cert[:decrypted_fields] || {}
            w.write_varint(decrypted.length)
            decrypted.each do |k, v|
              w.write_utf8_string(k.to_s)
              w.write_utf8_string(v.to_s)
            end
          end
        end

        def read_discovery_result(r)
          total = r.read_varint
          certs = total.times.map do
            cert_len = r.read_varint
            cert_r = Reader.new(r.read_bytes(cert_len))
            cert = read_cert_from_reader(cert_r)

            info_name = r.read_utf8_string
            info_icon = r.read_utf8_string
            info_desc = r.read_utf8_string
            info_trust = r.read_byte

            pub_count = r.read_varint
            public_keyring = {}
            pub_count.times do
              k = r.read_utf8_string
              v_len = r.read_varint
              public_keyring[k] = encode_base64(r.read_bytes(v_len))
            end

            dec_count = r.read_varint
            decrypted = {}
            dec_count.times do
              k = r.read_utf8_string
              decrypted[k] = r.read_utf8_string
            end

            cert.merge(
              certifier_info: {
                name: info_name,
                icon_url: info_icon,
                description: info_desc,
                trust: info_trust
              },
              publicly_revealed_keyring: public_keyring,
              decrypted_fields: decrypted
            )
          end
          { total_certificates: total, certificates: certs }
        end

        def decode_base64_32_safe(str)
          require 'base64'
          Base64.strict_decode64(str)
        rescue StandardError
          str.b
        end

        # -----------------------------------------------------------------------
        # 1. createAction
        # -----------------------------------------------------------------------

        def write_create_action_params(w, args)
          w.write_utf8_string(args[:description].to_s)
          w.write_optional_byte_array(args[:input_beef]&.pack('C*'))

          inputs = args[:inputs]
          if inputs.nil?
            w.write_signed_varint(-1)
          else
            w.write_varint(inputs.length)
            inputs.each do |inp|
              write_outpoint_str(w, inp[:outpoint])
              if inp[:unlocking_script]
                script_bytes = [inp[:unlocking_script]].pack('H*')
                w.write_varint(script_bytes.bytesize)
                w.write_bytes(script_bytes)
              else
                w.write_signed_varint(-1)
                w.write_varint(inp[:unlocking_script_length] || 0)
              end
              w.write_utf8_string(inp[:input_description].to_s)
              if inp[:sequence_number]
                w.write_varint(inp[:sequence_number])
              else
                w.write_signed_varint(-1)
              end
            end
          end

          outputs = args[:outputs]
          if outputs.nil?
            w.write_signed_varint(-1)
          else
            w.write_varint(outputs.length)
            outputs.each do |out|
              script_bytes = [out[:locking_script].to_s].pack('H*')
              w.write_varint(script_bytes.bytesize)
              w.write_bytes(script_bytes)
              w.write_varint(out[:satoshis].to_i)
              w.write_utf8_string(out[:output_description].to_s)
              w.write_optional_utf8_string(out[:basket])
              w.write_optional_utf8_string(out[:custom_instructions])
              w.write_string_array(out[:tags])
            end
          end

          if args[:lock_time]
            w.write_varint(args[:lock_time])
          else
            w.write_signed_varint(-1)
          end

          if args[:version]
            w.write_varint(args[:version])
          else
            w.write_signed_varint(-1)
          end

          w.write_string_array(args[:labels])

          opts = args[:options]
          if opts.nil?
            w.write_int8(0)
          else
            w.write_int8(1)
            w.write_optional_bool(opts[:sign_and_process])
            w.write_optional_bool(opts[:accept_delayed_broadcast])
            if opts[:trust_self] == 'known'
              w.write_int8(1)
            elsif opts[:trust_self].nil?
              w.write_int8(-1)
            else
              w.write_int8(0)
            end
            known_txids = opts[:known_txids]
            if known_txids.nil?
              w.write_signed_varint(-1)
            else
              w.write_varint(known_txids.length)
              known_txids.each { |txid| w.write_bytes([txid].pack('H*')) }
            end
            w.write_optional_bool(opts[:return_txid_only])
            w.write_optional_bool(opts[:no_send])
            no_send_change = opts[:no_send_change]
            if no_send_change.nil?
              w.write_signed_varint(-1)
            else
              w.write_varint(no_send_change.length)
              no_send_change.each { |op| write_outpoint_str(w, op) }
            end
            send_with = opts[:send_with]
            if send_with.nil?
              w.write_signed_varint(-1)
            else
              w.write_varint(send_with.length)
              send_with.each { |txid| w.write_bytes([txid].pack('H*')) }
            end
            w.write_optional_bool(opts[:randomize_outputs])
          end
        end

        def read_create_action_params(r)
          args = {}
          args[:description] = r.read_utf8_string

          input_beef_raw = r.read_optional_byte_array
          args[:input_beef] = input_beef_raw&.bytes

          inputs_count = r.read_signed_varint
          args[:inputs] = if inputs_count == -1
                            nil
                          else
                            inputs_count.times.map do
                              inp = {}
                              inp[:outpoint] = read_outpoint_str(r)
                              script_len = r.read_signed_varint
                              if script_len >= 0
                                inp[:unlocking_script] = r.read_bytes(script_len).unpack1('H*')
                              else
                                inp[:unlocking_script] = nil
                                inp[:unlocking_script_length] = r.read_varint
                              end
                              inp[:input_description] = r.read_utf8_string
                              seq = r.read_signed_varint
                              inp[:sequence_number] = seq == -1 ? nil : seq
                              inp
                            end
                          end

          outputs_count = r.read_signed_varint
          args[:outputs] = if outputs_count == -1
                             nil
                           else
                             outputs_count.times.map do
                               out = {}
                               ls_len = r.read_varint
                               out[:locking_script] = r.read_bytes(ls_len).unpack1('H*')
                               out[:satoshis] = r.read_varint
                               out[:output_description] = r.read_utf8_string
                               out[:basket] = r.read_optional_utf8_string
                               out[:custom_instructions] = r.read_optional_utf8_string
                               out[:tags] = r.read_string_array
                               out
                             end
                           end

          lock_time = r.read_signed_varint
          args[:lock_time] = lock_time == -1 ? nil : lock_time
          version = r.read_signed_varint
          args[:version] = version == -1 ? nil : version
          args[:labels] = r.read_string_array

          opts_flag = r.read_int8
          if opts_flag == 1
            opts = {}
            opts[:sign_and_process] = r.read_optional_bool
            opts[:accept_delayed_broadcast] = r.read_optional_bool
            trust_self_flag = r.read_int8
            opts[:trust_self] = if trust_self_flag == -1
                                  nil
                                elsif trust_self_flag == 1
                                  'known'
                                end
            known_count = r.read_signed_varint
            opts[:known_txids] = if known_count == -1
                                   nil
                                 else
                                   known_count.times.map { r.read_bytes(32).unpack1('H*') }
                                 end
            opts[:return_txid_only] = r.read_optional_bool
            opts[:no_send] = r.read_optional_bool
            no_send_change_count = r.read_signed_varint
            opts[:no_send_change] = if no_send_change_count == -1
                                      nil
                                    else
                                      no_send_change_count.times.map { read_outpoint_str(r) }
                                    end
            send_with_count = r.read_signed_varint
            opts[:send_with] = if send_with_count == -1
                                 nil
                               else
                                 send_with_count.times.map { r.read_bytes(32).unpack1('H*') }
                               end
            opts[:randomize_outputs] = r.read_optional_bool
            args[:options] = opts
          else
            args[:options] = nil
          end

          args
        end

        def write_create_action_result(w, result)
          txid = result[:txid]
          if txid && !txid.empty?
            w.write_int8(1)
            w.write_bytes([txid].pack('H*'))
          else
            w.write_int8(0)
          end

          tx = result[:tx]
          if tx
            w.write_int8(1)
            tx_bytes = tx.is_a?(Array) ? tx.pack('C*') : tx
            w.write_varint(tx_bytes.bytesize)
            w.write_bytes(tx_bytes)
          else
            w.write_int8(0)
          end

          no_send_change = result[:no_send_change]
          if no_send_change
            w.write_varint(no_send_change.length)
            no_send_change.each { |op| write_outpoint_str(w, op) }
          else
            w.write_signed_varint(-1)
          end

          send_with_results = result[:send_with_results]
          if send_with_results
            w.write_varint(send_with_results.length)
            send_with_results.each do |swr|
              w.write_bytes([swr[:txid]].pack('H*'))
              status_code = { 'unproven' => 1, 'sending' => 2, 'failed' => 3 }[swr[:status]] || 1
              w.write_int8(status_code)
            end
          else
            w.write_signed_varint(-1)
          end

          signable = result[:signable_transaction]
          if signable
            w.write_int8(1)
            tx_bytes = signable[:tx].is_a?(Array) ? signable[:tx].pack('C*') : signable[:tx]
            w.write_varint(tx_bytes.bytesize)
            w.write_bytes(tx_bytes)
            require 'base64'
            ref_bytes = Base64.strict_decode64(signable[:reference])
            w.write_varint(ref_bytes.bytesize)
            w.write_bytes(ref_bytes)
          else
            w.write_int8(0)
          end
        end

        def read_create_action_result(r)
          result = {}
          txid_flag = r.read_int8
          result[:txid] = txid_flag == 1 ? r.read_bytes(32).unpack1('H*') : nil

          tx_flag = r.read_int8
          if tx_flag == 1
            tx_len = r.read_varint
            result[:tx] = r.read_bytes(tx_len).bytes
          else
            result[:tx] = nil
          end

          no_send_change_count = r.read_signed_varint
          result[:no_send_change] = if no_send_change_count == -1
                                      nil
                                    else
                                      no_send_change_count.times.map { read_outpoint_str(r) }
                                    end

          swr_count = r.read_signed_varint
          result[:send_with_results] = if swr_count == -1
                                         nil
                                       else
                                         swr_count.times.map do
                                           txid = r.read_bytes(32).unpack1('H*')
                                           status = { 1 => 'unproven', 2 => 'sending', 3 => 'failed' }[r.read_int8] || 'failed'
                                           { txid: txid, status: status }
                                         end
                                       end

          signable_flag = r.read_int8
          if signable_flag == 1
            tx_len = r.read_varint
            tx = r.read_bytes(tx_len).bytes
            ref_len = r.read_varint
            ref = encode_base64(r.read_bytes(ref_len))
            result[:signable_transaction] = { tx: tx, reference: ref }
          else
            result[:signable_transaction] = nil
          end

          result
        end

        # -----------------------------------------------------------------------
        # 2. signAction
        # -----------------------------------------------------------------------

        def write_sign_action_params(w, args)
          spends = args[:spends] || {}
          w.write_varint(spends.length)
          spends.each do |idx, spend|
            w.write_varint(idx.to_i)
            script_bytes = [spend[:unlocking_script].to_s].pack('H*')
            w.write_varint(script_bytes.bytesize)
            w.write_bytes(script_bytes)
            if spend[:sequence_number]
              w.write_varint(spend[:sequence_number])
            else
              w.write_signed_varint(-1)
            end
          end

          require 'base64'
          ref_bytes = Base64.strict_decode64(args[:reference].to_s)
          w.write_varint(ref_bytes.bytesize)
          w.write_bytes(ref_bytes)

          opts = args[:options]
          if opts.nil?
            w.write_int8(0)
          else
            w.write_int8(1)
            w.write_optional_bool(opts[:accept_delayed_broadcast])
            w.write_optional_bool(opts[:return_txid_only])
            w.write_optional_bool(opts[:no_send])
            send_with = opts[:send_with]
            if send_with.nil?
              w.write_signed_varint(-1)
            else
              w.write_varint(send_with.length)
              send_with.each { |txid| w.write_bytes([txid].pack('H*')) }
            end
          end
        end

        def read_sign_action_params(r)
          spends = {}
          spend_count = r.read_varint
          spend_count.times do
            idx = r.read_varint
            us_len = r.read_varint
            us = r.read_bytes(us_len).unpack1('H*')
            seq = r.read_signed_varint
            spends[idx] = { unlocking_script: us, sequence_number: seq == -1 ? nil : seq }
          end

          ref_len = r.read_varint
          reference = encode_base64(r.read_bytes(ref_len))

          opts_flag = r.read_int8
          options = if opts_flag == 1
                      opts = {}
                      opts[:accept_delayed_broadcast] = r.read_optional_bool
                      opts[:return_txid_only] = r.read_optional_bool
                      opts[:no_send] = r.read_optional_bool
                      sw_count = r.read_signed_varint
                      opts[:send_with] = if sw_count == -1
                                           nil
                                         else
                                           sw_count.times.map { r.read_bytes(32).unpack1('H*') }
                                         end
                      opts
                    end

          { spends: spends, reference: reference, options: options }
        end

        def write_sign_action_result(w, result)
          txid = result[:txid]
          if txid && !txid.empty?
            w.write_int8(1)
            w.write_bytes([txid].pack('H*'))
          else
            w.write_int8(0)
          end

          tx = result[:tx]
          if tx
            w.write_int8(1)
            tx_bytes = tx.is_a?(Array) ? tx.pack('C*') : tx
            w.write_varint(tx_bytes.bytesize)
            w.write_bytes(tx_bytes)
          else
            w.write_int8(0)
          end

          swr = result[:send_with_results]
          if swr
            w.write_varint(swr.length)
            swr.each do |item|
              w.write_bytes([item[:txid]].pack('H*'))
              status_code = { 'unproven' => 1, 'sending' => 2, 'failed' => 3 }[item[:status]] || 1
              w.write_int8(status_code)
            end
          else
            w.write_signed_varint(-1)
          end
        end

        def read_sign_action_result(r)
          result = {}
          txid_flag = r.read_int8
          result[:txid] = txid_flag == 1 ? r.read_bytes(32).unpack1('H*') : nil

          tx_flag = r.read_int8
          if tx_flag == 1
            tx_len = r.read_varint
            result[:tx] = r.read_bytes(tx_len).bytes
          else
            result[:tx] = nil
          end

          swr_count = r.read_signed_varint
          result[:send_with_results] = if swr_count == -1
                                         nil
                                       else
                                         swr_count.times.map do
                                           txid = r.read_bytes(32).unpack1('H*')
                                           status = { 1 => 'unproven', 2 => 'sending', 3 => 'failed' }[r.read_int8] || 'failed'
                                           { txid: txid, status: status }
                                         end
                                       end

          result
        end

        # -----------------------------------------------------------------------
        # 3. abortAction — reference is the entire params payload (no length prefix)
        # -----------------------------------------------------------------------

        def write_abort_action_params(w, args)
          require 'base64'
          ref_bytes = Base64.strict_decode64(args[:reference].to_s)
          w.write_bytes(ref_bytes)
        end

        def read_abort_action_params(r)
          ref_bytes = r.read_remaining
          { reference: encode_base64(ref_bytes) }
        end

        def write_abort_action_result(w, _result)
          # No payload — response is just the zero error byte written by serialize_response
        end

        def read_abort_action_result(_r)
          { aborted: true }
        end

        # -----------------------------------------------------------------------
        # 4. listActions
        # -----------------------------------------------------------------------

        LIST_ACTIONS_INCLUDE_FLAGS = %i[
          include_labels include_inputs include_input_source_locking_scripts
          include_input_unlocking_scripts include_outputs include_output_locking_scripts
        ].freeze

        def write_list_actions_params(w, args)
          labels = args[:labels] || []
          w.write_varint(labels.length)
          labels.each { |l| w.write_utf8_string(l) }

          lqm = args[:label_query_mode]
          if lqm.nil?
            w.write_int8(-1)
          elsif lqm == 'any'
            w.write_int8(1)
          else
            w.write_int8(2)
          end

          LIST_ACTIONS_INCLUDE_FLAGS.each do |flag|
            w.write_optional_bool(args[flag])
          end

          w.write_signed_varint(args[:limit].nil? ? -1 : args[:limit])
          w.write_signed_varint(args[:offset].nil? ? -1 : args[:offset])
          w.write_optional_bool(args[:seek_permission])
        end

        def read_list_actions_params(r)
          args = {}
          label_count = r.read_varint
          args[:labels] = label_count.times.map { r.read_utf8_string }

          lqm_flag = r.read_int8
          args[:label_query_mode] = case lqm_flag
                                    when 1 then 'any'
                                    when 2 then 'all'
                                    end

          LIST_ACTIONS_INCLUDE_FLAGS.each do |flag|
            args[flag] = r.read_optional_bool
          end

          limit = r.read_signed_varint
          args[:limit] = limit == -1 ? nil : limit
          offset = r.read_signed_varint
          args[:offset] = offset == -1 ? nil : offset
          args[:seek_permission] = r.read_optional_bool
          args
        end

        def write_list_actions_result(w, result)
          actions = result[:actions] || []
          w.write_varint(result[:total_actions] || actions.length)
          actions.each do |action|
            w.write_bytes([action[:txid]].pack('H*'))
            w.write_varint(action[:satoshis].to_i)
            status_code = {
              'completed' => 1, 'unprocessed' => 2, 'sending' => 3,
              'unproven' => 4, 'unsigned' => 5, 'nosend' => 6,
              'nonfinal' => 7, 'failed' => 8
            }[action[:status]] || -1
            w.write_int8(status_code)
            w.write_int8(action[:is_outgoing] ? 1 : 0)
            w.write_utf8_string(action[:description].to_s)
            w.write_string_array(action[:labels])
            w.write_varint(action[:version].to_i)
            w.write_varint(action[:lock_time].to_i)

            inputs = action[:inputs]
            if inputs.nil?
              w.write_signed_varint(-1)
            else
              w.write_varint(inputs.length)
              inputs.each do |inp|
                write_outpoint_str(w, inp[:source_outpoint])
                w.write_varint(inp[:source_satoshis].to_i)
                w.write_optional_byte_array(inp[:source_locking_script] ? [inp[:source_locking_script]].pack('H*') : nil)
                w.write_optional_byte_array(inp[:unlocking_script] ? [inp[:unlocking_script]].pack('H*') : nil)
                w.write_utf8_string(inp[:input_description].to_s)
                w.write_varint(inp[:sequence_number].to_i)
              end
            end

            outputs = action[:outputs]
            if outputs.nil?
              w.write_signed_varint(-1)
            else
              w.write_varint(outputs.length)
              outputs.each do |out|
                w.write_varint(out[:output_index].to_i)
                w.write_varint(out[:satoshis].to_i)
                w.write_optional_byte_array(out[:locking_script] ? [out[:locking_script]].pack('H*') : nil)
                w.write_int8(out[:spendable] ? 1 : 0)
                w.write_utf8_string(out[:output_description].to_s)
                w.write_optional_utf8_string(out[:basket])
                w.write_string_array(out[:tags])
                w.write_optional_utf8_string(out[:custom_instructions])
              end
            end
          end
        end

        def read_list_actions_result(r)
          total = r.read_varint
          actions = total.times.map do
            action = {}
            action[:txid] = r.read_bytes(32).unpack1('H*')
            action[:satoshis] = r.read_varint
            action[:status] = {
              1 => 'completed', 2 => 'unprocessed', 3 => 'sending',
              4 => 'unproven', 5 => 'unsigned', 6 => 'nosend',
              7 => 'nonfinal', 8 => 'failed'
            }[r.read_int8]
            action[:is_outgoing] = r.read_int8 == 1
            action[:description] = r.read_utf8_string
            action[:labels] = r.read_string_array
            action[:version] = r.read_varint
            action[:lock_time] = r.read_varint

            inputs_count = r.read_signed_varint
            action[:inputs] = if inputs_count == -1
                                nil
                              else
                                inputs_count.times.map do
                                  inp = {}
                                  inp[:source_outpoint] = read_outpoint_str(r)
                                  inp[:source_satoshis] = r.read_varint
                                  sls = r.read_optional_byte_array
                                  inp[:source_locking_script] = sls&.unpack1('H*')
                                  us = r.read_optional_byte_array
                                  inp[:unlocking_script] = us&.unpack1('H*')
                                  inp[:input_description] = r.read_utf8_string
                                  inp[:sequence_number] = r.read_varint
                                  inp
                                end
                              end

            outputs_count = r.read_signed_varint
            action[:outputs] = if outputs_count == -1
                                 nil
                               else
                                 outputs_count.times.map do
                                   out = {}
                                   out[:output_index] = r.read_varint
                                   out[:satoshis] = r.read_varint
                                   ls = r.read_optional_byte_array
                                   out[:locking_script] = ls&.unpack1('H*')
                                   out[:spendable] = r.read_int8 == 1
                                   out[:output_description] = r.read_utf8_string
                                   out[:basket] = r.read_optional_utf8_string
                                   out[:tags] = r.read_string_array
                                   out[:custom_instructions] = r.read_optional_utf8_string
                                   out
                                 end
                               end

            action
          end

          { total_actions: total, actions: actions }
        end

        # -----------------------------------------------------------------------
        # 5. internalizeAction
        # -----------------------------------------------------------------------

        def write_internalize_action_params(w, args)
          tx = args[:tx]
          tx_bytes = tx.is_a?(Array) ? tx.pack('C*') : tx.to_s.b
          w.write_varint(tx_bytes.bytesize)
          w.write_bytes(tx_bytes)

          outputs = args[:outputs] || []
          w.write_varint(outputs.length)
          outputs.each do |out|
            w.write_varint(out[:output_index].to_i)
            if out[:protocol] == 'wallet payment'
              w.write_byte(1)
              rem = out[:payment_remittance] || {}
              w.write_bytes([rem[:sender_identity_key].to_s].pack('H*'))
              require 'base64'
              pref = Base64.strict_decode64(rem[:derivation_prefix].to_s)
              w.write_varint(pref.bytesize)
              w.write_bytes(pref)
              suf = Base64.strict_decode64(rem[:derivation_suffix].to_s)
              w.write_varint(suf.bytesize)
              w.write_bytes(suf)
            else
              w.write_byte(2)
              rem = out[:insertion_remittance] || {}
              w.write_utf8_string(rem[:basket].to_s)
              w.write_optional_utf8_string(rem[:custom_instructions])
              tags = rem[:tags] || []
              w.write_varint(tags.length)
              tags.each { |t| w.write_utf8_string(t) }
            end
          end

          w.write_string_array(args[:labels])
          w.write_utf8_string(args[:description].to_s)
          w.write_optional_bool(args[:seek_permission])
        end

        def read_internalize_action_params(r)
          args = {}
          tx_len = r.read_varint
          args[:tx] = r.read_bytes(tx_len).bytes

          outputs_count = r.read_varint
          args[:outputs] = outputs_count.times.map do
            out = {}
            out[:output_index] = r.read_varint
            proto_flag = r.read_byte
            if proto_flag == 1
              out[:protocol] = 'wallet payment'
              rem = {}
              rem[:sender_identity_key] = r.read_bytes(33).unpack1('H*')
              pref_len = r.read_varint
              rem[:derivation_prefix] = encode_base64(r.read_bytes(pref_len))
              suf_len = r.read_varint
              rem[:derivation_suffix] = encode_base64(r.read_bytes(suf_len))
              out[:payment_remittance] = rem
            else
              out[:protocol] = 'basket insertion'
              rem = {}
              rem[:basket] = r.read_utf8_string
              rem[:custom_instructions] = r.read_optional_utf8_string
              tags_count = r.read_varint
              rem[:tags] = tags_count.times.map { r.read_utf8_string }
              out[:insertion_remittance] = rem
            end
            out
          end

          args[:labels] = r.read_string_array
          args[:description] = r.read_utf8_string
          args[:seek_permission] = r.read_optional_bool
          args
        end

        def write_internalize_action_result(w, _result)
          # No payload
        end

        def read_internalize_action_result(_r)
          { accepted: true }
        end

        # -----------------------------------------------------------------------
        # 6. listOutputs
        # -----------------------------------------------------------------------

        def write_list_outputs_params(w, args)
          w.write_utf8_string(args[:basket].to_s)

          tags = args[:tags]
          if tags.nil? || tags.empty?
            w.write_varint(0)
          else
            w.write_varint(tags.length)
            tags.each { |t| w.write_utf8_string(t) }
          end

          tqm = args[:tag_query_mode]
          if tqm == 'all'
            w.write_int8(1)
          elsif tqm == 'any'
            w.write_int8(2)
          else
            w.write_int8(-1)
          end

          inc = args[:include]
          if inc == 'locking scripts'
            w.write_int8(1)
          elsif inc == 'entire transactions'
            w.write_int8(2)
          else
            w.write_int8(-1)
          end

          w.write_optional_bool(args[:include_custom_instructions])
          w.write_optional_bool(args[:include_tags])
          w.write_optional_bool(args[:include_labels])
          w.write_signed_varint(args[:limit].nil? ? -1 : args[:limit])
          w.write_signed_varint(args[:offset].nil? ? -1 : args[:offset])
          w.write_optional_bool(args[:seek_permission])
        end

        def read_list_outputs_params(r)
          args = {}
          args[:basket] = r.read_utf8_string

          tags_count = r.read_varint
          args[:tags] = tags_count.zero? ? nil : tags_count.times.map { r.read_utf8_string }

          tqm_flag = r.read_int8
          args[:tag_query_mode] = case tqm_flag
                                  when 1 then 'all'
                                  when 2 then 'any'
                                  end

          inc_flag = r.read_int8
          args[:include] = case inc_flag
                           when 1 then 'locking scripts'
                           when 2 then 'entire transactions'
                           end

          args[:include_custom_instructions] = r.read_optional_bool
          args[:include_tags] = r.read_optional_bool
          args[:include_labels] = r.read_optional_bool

          limit = r.read_signed_varint
          args[:limit] = limit == -1 ? nil : limit
          offset = r.read_signed_varint
          args[:offset] = offset == -1 ? nil : offset
          args[:seek_permission] = r.read_optional_bool
          args
        end

        def write_list_outputs_result(w, result)
          outputs = result[:outputs] || []
          w.write_varint(result[:total_outputs] || outputs.length)

          beef = result[:beef]
          if beef
            beef_bytes = beef.is_a?(Array) ? beef.pack('C*') : beef
            w.write_varint(beef_bytes.bytesize)
            w.write_bytes(beef_bytes)
          else
            w.write_signed_varint(-1)
          end

          outputs.each do |out|
            write_outpoint_str(w, out[:outpoint])
            w.write_varint(out[:satoshis].to_i)
            w.write_optional_byte_array(out[:locking_script] ? [out[:locking_script]].pack('H*') : nil)
            w.write_optional_utf8_string(out[:custom_instructions])
            w.write_string_array(out[:tags])
            w.write_string_array(out[:labels])
          end
        end

        def read_list_outputs_result(r)
          total = r.read_varint
          beef_raw = r.read_optional_byte_array
          beef = beef_raw&.bytes

          outputs = total.times.map do
            out = {}
            out[:outpoint] = read_outpoint_str(r)
            out[:satoshis] = r.read_varint
            ls = r.read_optional_byte_array
            out[:locking_script] = ls&.unpack1('H*')
            out[:custom_instructions] = r.read_optional_utf8_string
            out[:tags] = r.read_string_array
            out[:labels] = r.read_string_array
            out
          end

          { total_outputs: total, beef: beef, outputs: outputs }
        end

        # -----------------------------------------------------------------------
        # 7. relinquishOutput
        # -----------------------------------------------------------------------

        def write_relinquish_output_params(w, args)
          w.write_utf8_string(args[:basket].to_s)
          write_outpoint_str(w, args[:output].to_s)
        end

        def read_relinquish_output_params(r)
          { basket: r.read_utf8_string, output: read_outpoint_str(r) }
        end

        def write_relinquish_output_result(w, _result); end

        def read_relinquish_output_result(_r)
          { relinquished: true }
        end

        # -----------------------------------------------------------------------
        # 8. getPublicKey
        # -----------------------------------------------------------------------

        def write_get_public_key_params(w, args)
          identity = args[:identity_key] ? 1 : 0
          w.write_byte(identity)

          if identity == 1
            w.write_privileged(args[:privileged], args[:privileged_reason])
          else
            w.write_protocol_id(args[:protocol_id])
            w.write_utf8_string(args[:key_id].to_s)
            w.write_counterparty(args[:counterparty])
            w.write_privileged(args[:privileged], args[:privileged_reason])
            w.write_optional_bool(args[:for_self])
          end

          w.write_optional_bool(args[:seek_permission])
        end

        def read_get_public_key_params(r)
          args = {}
          identity_flag = r.read_byte
          args[:identity_key] = identity_flag == 1

          if args[:identity_key]
            args[:privileged], args[:privileged_reason] = r.read_privileged
          else
            args[:protocol_id] = r.read_protocol_id
            args[:key_id] = r.read_utf8_string
            args[:counterparty] = r.read_counterparty
            args[:privileged], args[:privileged_reason] = r.read_privileged
            args[:for_self] = r.read_optional_bool
          end

          args[:seek_permission] = r.read_optional_bool
          args
        end

        def write_get_public_key_result(w, result)
          w.write_bytes([result[:public_key].to_s].pack('H*'))
        end

        def read_get_public_key_result(r)
          { public_key: r.read_remaining.unpack1('H*') }
        end

        # -----------------------------------------------------------------------
        # 9. revealCounterpartyKeyLinkage
        # -----------------------------------------------------------------------

        def write_reveal_counterparty_key_linkage_params(w, args)
          w.write_privileged(args[:privileged], args[:privileged_reason])
          w.write_bytes([args[:counterparty].to_s].pack('H*'))
          w.write_bytes([args[:verifier].to_s].pack('H*'))
        end

        def read_reveal_counterparty_key_linkage_params(r)
          privileged, privileged_reason = r.read_privileged
          counterparty = r.read_bytes(33).unpack1('H*')
          verifier = r.read_bytes(33).unpack1('H*')
          { privileged: privileged, privileged_reason: privileged_reason,
            counterparty: counterparty, verifier: verifier }
        end

        def write_reveal_counterparty_key_linkage_result(w, result)
          w.write_bytes([result[:prover].to_s].pack('H*'))
          w.write_bytes([result[:verifier].to_s].pack('H*'))
          w.write_bytes([result[:counterparty].to_s].pack('H*'))
          w.write_utf8_string(result[:revelation_time].to_s)
          enc_link = result[:encrypted_linkage]
          enc_link = enc_link.is_a?(Array) ? enc_link.pack('C*') : enc_link.to_s.b
          w.write_varint(enc_link.bytesize)
          w.write_bytes(enc_link)
          enc_proof = result[:encrypted_linkage_proof]
          enc_proof = enc_proof.is_a?(Array) ? enc_proof.pack('C*') : enc_proof.to_s.b
          w.write_varint(enc_proof.bytesize)
          w.write_bytes(enc_proof)
        end

        def read_reveal_counterparty_key_linkage_result(r)
          prover = r.read_bytes(33).unpack1('H*')
          verifier = r.read_bytes(33).unpack1('H*')
          counterparty = r.read_bytes(33).unpack1('H*')
          revelation_time = r.read_utf8_string
          el_len = r.read_varint
          encrypted_linkage = r.read_bytes(el_len).bytes
          ep_len = r.read_varint
          encrypted_linkage_proof = r.read_bytes(ep_len).bytes
          { prover: prover, verifier: verifier, counterparty: counterparty,
            revelation_time: revelation_time, encrypted_linkage: encrypted_linkage,
            encrypted_linkage_proof: encrypted_linkage_proof }
        end

        # -----------------------------------------------------------------------
        # 10. revealSpecificKeyLinkage
        # -----------------------------------------------------------------------

        def write_reveal_specific_key_linkage_params(w, args)
          write_key_related_params(w, args)
          w.write_bytes([args[:verifier].to_s].pack('H*'))
        end

        def read_reveal_specific_key_linkage_params(r)
          args = read_key_related_from_reader(r)
          args[:verifier] = r.read_bytes(33).unpack1('H*')
          args
        end

        def write_reveal_specific_key_linkage_result(w, result)
          w.write_bytes([result[:prover].to_s].pack('H*'))
          w.write_bytes([result[:verifier].to_s].pack('H*'))
          w.write_bytes([result[:counterparty].to_s].pack('H*'))
          w.write_byte(result[:protocol_id][0].to_i)
          w.write_utf8_string(result[:protocol_id][1].to_s)
          w.write_utf8_string(result[:key_id].to_s)
          el = result[:encrypted_linkage]
          el = el.is_a?(Array) ? el.pack('C*') : el.to_s.b
          w.write_varint(el.bytesize)
          w.write_bytes(el)
          ep = result[:encrypted_linkage_proof]
          ep = ep.is_a?(Array) ? ep.pack('C*') : ep.to_s.b
          w.write_varint(ep.bytesize)
          w.write_bytes(ep)
          w.write_byte(result[:proof_type].to_i)
        end

        def read_reveal_specific_key_linkage_result(r)
          prover = r.read_bytes(33).unpack1('H*')
          verifier = r.read_bytes(33).unpack1('H*')
          counterparty = r.read_bytes(33).unpack1('H*')
          level = r.read_byte
          protocol = r.read_utf8_string
          key_id = r.read_utf8_string
          el_len = r.read_varint
          encrypted_linkage = r.read_bytes(el_len).bytes
          ep_len = r.read_varint
          encrypted_linkage_proof = r.read_bytes(ep_len).bytes
          proof_type = r.read_byte
          { prover: prover, verifier: verifier, counterparty: counterparty,
            protocol_id: [level, protocol], key_id: key_id,
            encrypted_linkage: encrypted_linkage,
            encrypted_linkage_proof: encrypted_linkage_proof,
            proof_type: proof_type }
        end

        # -----------------------------------------------------------------------
        # 11. encrypt
        # -----------------------------------------------------------------------

        def write_encrypt_params(w, args)
          write_key_related_params(w, args)
          pt = args[:plaintext]
          pt_bytes = pt.is_a?(Array) ? pt.pack('C*') : pt.to_s.b
          w.write_varint(pt_bytes.bytesize)
          w.write_bytes(pt_bytes)
          w.write_optional_bool(args[:seek_permission])
        end

        def read_encrypt_params(r)
          args = read_key_related_from_reader(r)
          pt_len = r.read_varint
          args[:plaintext] = r.read_bytes(pt_len).bytes
          args[:seek_permission] = r.read_optional_bool
          args
        end

        def write_encrypt_result(w, result)
          ct = result[:ciphertext]
          ct_bytes = ct.is_a?(Array) ? ct.pack('C*') : ct.to_s.b
          w.write_bytes(ct_bytes)
        end

        def read_encrypt_result(r)
          { ciphertext: r.read_remaining.bytes }
        end

        # -----------------------------------------------------------------------
        # 12. decrypt
        # -----------------------------------------------------------------------

        def write_decrypt_params(w, args)
          write_key_related_params(w, args)
          ct = args[:ciphertext]
          ct_bytes = ct.is_a?(Array) ? ct.pack('C*') : ct.to_s.b
          w.write_varint(ct_bytes.bytesize)
          w.write_bytes(ct_bytes)
          w.write_optional_bool(args[:seek_permission])
        end

        def read_decrypt_params(r)
          args = read_key_related_from_reader(r)
          ct_len = r.read_varint
          args[:ciphertext] = r.read_bytes(ct_len).bytes
          args[:seek_permission] = r.read_optional_bool
          args
        end

        def write_decrypt_result(w, result)
          pt = result[:plaintext]
          pt_bytes = pt.is_a?(Array) ? pt.pack('C*') : pt.to_s.b
          w.write_bytes(pt_bytes)
        end

        def read_decrypt_result(r)
          { plaintext: r.read_remaining.bytes }
        end

        # -----------------------------------------------------------------------
        # 13. createHmac
        # -----------------------------------------------------------------------

        def write_create_hmac_params(w, args)
          write_key_related_params(w, args)
          data = args[:data]
          data_bytes = data.is_a?(Array) ? data.pack('C*') : data.to_s.b
          w.write_varint(data_bytes.bytesize)
          w.write_bytes(data_bytes)
          w.write_optional_bool(args[:seek_permission])
        end

        def read_create_hmac_params(r)
          args = read_key_related_from_reader(r)
          data_len = r.read_varint
          args[:data] = r.read_bytes(data_len).bytes
          args[:seek_permission] = r.read_optional_bool
          args
        end

        def write_create_hmac_result(w, result)
          hmac = result[:hmac]
          hmac_bytes = hmac.is_a?(Array) ? hmac.pack('C*') : hmac.to_s.b
          w.write_bytes(hmac_bytes)
        end

        def read_create_hmac_result(r)
          { hmac: r.read_remaining.bytes }
        end

        # -----------------------------------------------------------------------
        # 14. verifyHmac
        # -----------------------------------------------------------------------

        def write_verify_hmac_params(w, args)
          write_key_related_params(w, args)
          hmac = args[:hmac]
          hmac_bytes = hmac.is_a?(Array) ? hmac.pack('C*') : hmac.to_s.b
          w.write_bytes(hmac_bytes) # fixed 32 bytes, no length prefix
          data = args[:data]
          data_bytes = data.is_a?(Array) ? data.pack('C*') : data.to_s.b
          w.write_varint(data_bytes.bytesize)
          w.write_bytes(data_bytes)
          w.write_optional_bool(args[:seek_permission])
        end

        def read_verify_hmac_params(r)
          args = read_key_related_from_reader(r)
          args[:hmac] = r.read_bytes(32).bytes
          data_len = r.read_varint
          args[:data] = r.read_bytes(data_len).bytes
          args[:seek_permission] = r.read_optional_bool
          args
        end

        def write_verify_hmac_result(w, _result); end

        def read_verify_hmac_result(_r)
          { valid: true }
        end

        # -----------------------------------------------------------------------
        # 15. createSignature
        # -----------------------------------------------------------------------

        def write_create_signature_params(w, args)
          write_key_related_params(w, args)
          if args[:data]
            w.write_byte(1)
            data = args[:data]
            data_bytes = data.is_a?(Array) ? data.pack('C*') : data.to_s.b
            w.write_varint(data_bytes.bytesize)
            w.write_bytes(data_bytes)
          elsif args[:hash_to_directly_sign]
            w.write_byte(2)
            hash = args[:hash_to_directly_sign]
            hash_bytes = hash.is_a?(Array) ? hash.pack('C*') : hash.to_s.b
            w.write_bytes(hash_bytes)
          else
            w.write_byte(0)
          end
          w.write_optional_bool(args[:seek_permission])
        end

        def read_create_signature_params(r)
          args = read_key_related_from_reader(r)
          data_type = r.read_byte
          if data_type == 1
            data_len = r.read_varint
            args[:data] = r.read_bytes(data_len).bytes
          elsif data_type == 2
            args[:hash_to_directly_sign] = r.read_bytes(32).bytes
          end
          args[:seek_permission] = r.read_optional_bool
          args
        end

        def write_create_signature_result(w, result)
          sig = result[:signature]
          sig_bytes = sig.is_a?(Array) ? sig.pack('C*') : sig.to_s.b
          w.write_bytes(sig_bytes)
        end

        def read_create_signature_result(r)
          { signature: r.read_remaining.bytes }
        end

        # -----------------------------------------------------------------------
        # 16. verifySignature
        # -----------------------------------------------------------------------

        def write_verify_signature_params(w, args)
          write_key_related_params(w, args)
          w.write_optional_bool(args[:for_self])
          sig = args[:signature]
          sig_bytes = sig.is_a?(Array) ? sig.pack('C*') : sig.to_s.b
          w.write_varint(sig_bytes.bytesize)
          w.write_bytes(sig_bytes)
          if args[:data]
            w.write_byte(1)
            data = args[:data]
            data_bytes = data.is_a?(Array) ? data.pack('C*') : data.to_s.b
            w.write_varint(data_bytes.bytesize)
            w.write_bytes(data_bytes)
          elsif args[:hash_to_directly_verify]
            w.write_byte(2)
            hash = args[:hash_to_directly_verify]
            hash_bytes = hash.is_a?(Array) ? hash.pack('C*') : hash.to_s.b
            w.write_bytes(hash_bytes)
          else
            w.write_byte(0)
          end
          w.write_optional_bool(args[:seek_permission])
        end

        def read_verify_signature_params(r)
          args = read_key_related_from_reader(r)
          args[:for_self] = r.read_optional_bool
          sig_len = r.read_varint
          args[:signature] = r.read_bytes(sig_len).bytes
          data_type = r.read_byte
          if data_type == 1
            data_len = r.read_varint
            args[:data] = r.read_bytes(data_len).bytes
          elsif data_type == 2
            args[:hash_to_directly_verify] = r.read_bytes(32).bytes
          end
          args[:seek_permission] = r.read_optional_bool
          args
        end

        def write_verify_signature_result(w, _result); end

        def read_verify_signature_result(_r)
          { valid: true }
        end

        # -----------------------------------------------------------------------
        # 17. acquireCertificate
        # -----------------------------------------------------------------------

        def write_acquire_certificate_params(w, args)
          w.write_bytes(decode_base64_32(args[:type].to_s))
          w.write_bytes([args[:certifier].to_s].pack('H*'))

          fields = args[:fields] || {}
          w.write_varint(fields.length)
          fields.each do |k, v|
            w.write_utf8_string(k.to_s)
            w.write_utf8_string(v.to_s)
          end

          w.write_privileged(args[:privileged], args[:privileged_reason])

          if args[:acquisition_protocol] == 'direct'
            w.write_byte(1)
            w.write_bytes(decode_base64_32(args[:serial_number].to_s))
            write_outpoint_str(w, args[:revocation_outpoint].to_s)
            sig_bytes = [args[:signature].to_s].pack('H*')
            w.write_varint(sig_bytes.bytesize)
            w.write_bytes(sig_bytes)

            keyring_revealer = args[:keyring_revealer]
            if keyring_revealer == 'certifier'
              w.write_byte(11)
            else
              kr_bytes = [keyring_revealer.to_s].pack('H*')
              w.write_bytes(kr_bytes)
            end

            keyring = args[:keyring_for_subject] || {}
            w.write_varint(keyring.length)
            keyring.each do |k, v|
              w.write_utf8_string(k.to_s)
              v_bytes = decode_base64_32_safe(v.to_s)
              w.write_varint(v_bytes.bytesize)
              w.write_bytes(v_bytes)
            end
          else
            w.write_byte(2)
            w.write_utf8_string(args[:certifier_url].to_s)
          end
        end

        def read_acquire_certificate_params(r)
          args = {}
          args[:type] = encode_base64(r.read_bytes(32))
          args[:certifier] = r.read_bytes(33).unpack1('H*')

          fields_count = r.read_varint
          args[:fields] = {}
          fields_count.times do
            k = r.read_utf8_string
            args[:fields][k] = r.read_utf8_string
          end

          args[:privileged], args[:privileged_reason] = r.read_privileged

          protocol_flag = r.read_byte
          if protocol_flag == 1
            args[:acquisition_protocol] = 'direct'
            args[:serial_number] = encode_base64(r.read_bytes(32))
            args[:revocation_outpoint] = read_outpoint_str(r)
            sig_len = r.read_varint
            args[:signature] = r.read_bytes(sig_len).unpack1('H*')
            kr_flag = r.read_byte
            if kr_flag == 11
              args[:keyring_revealer] = 'certifier'
            else
              remaining = r.read_bytes(32)
              args[:keyring_revealer] = ([kr_flag].pack('C') + remaining).unpack1('H*')
            end
            kr_count = r.read_varint
            args[:keyring_for_subject] = {}
            kr_count.times do
              k = r.read_utf8_string
              v_len = r.read_varint
              args[:keyring_for_subject][k] = encode_base64(r.read_bytes(v_len))
            end
          else
            args[:acquisition_protocol] = 'issuance'
            args[:certifier_url] = r.read_utf8_string
          end

          args
        end

        def write_acquire_certificate_result(w, result)
          write_certificate_fields(w, result)
        end

        def read_acquire_certificate_result(r)
          read_cert_from_reader(r)
        end

        # -----------------------------------------------------------------------
        # 18. listCertificates
        # -----------------------------------------------------------------------

        def write_list_certificates_params(w, args)
          certifiers = args[:certifiers] || []
          w.write_varint(certifiers.length)
          certifiers.each { |c| w.write_bytes([c].pack('H*')) }

          types = args[:types] || []
          w.write_varint(types.length)
          types.each { |t| w.write_bytes(decode_base64_32(t)) }

          w.write_signed_varint(args[:limit].nil? ? -1 : args[:limit])
          w.write_signed_varint(args[:offset].nil? ? -1 : args[:offset])
          w.write_privileged(args[:privileged], args[:privileged_reason])
        end

        def read_list_certificates_params(r)
          args = {}
          cert_count = r.read_varint
          args[:certifiers] = cert_count.times.map { r.read_bytes(33).unpack1('H*') }

          types_count = r.read_varint
          args[:types] = types_count.times.map { encode_base64(r.read_bytes(32)) }

          limit = r.read_signed_varint
          args[:limit] = limit == -1 ? nil : limit
          offset = r.read_signed_varint
          args[:offset] = offset == -1 ? nil : offset
          args[:privileged], args[:privileged_reason] = r.read_privileged
          args
        end

        def write_list_certificates_result(w, result)
          certs = result[:certificates] || []
          w.write_varint(result[:total_certificates] || certs.length)
          certs.each do |cert|
            cert_w = Writer.new
            write_certificate_fields(cert_w, cert)
            cert_bin = cert_w.to_binary
            w.write_varint(cert_bin.bytesize)
            w.write_bytes(cert_bin)

            keyring = cert[:keyring]
            if keyring && !keyring.empty?
              w.write_int8(1)
              w.write_varint(keyring.length)
              keyring.each do |k, v|
                w.write_utf8_string(k.to_s)
                v_bytes = decode_base64_32_safe(v.to_s)
                w.write_varint(v_bytes.bytesize)
                w.write_bytes(v_bytes)
              end
            else
              w.write_int8(0)
            end

            verifier_hex = cert[:verifier].to_s
            verifier_bytes = verifier_hex.empty? ? ''.b : [verifier_hex].pack('H*')
            w.write_varint(verifier_bytes.bytesize)
            w.write_bytes(verifier_bytes)
          end
        end

        def read_list_certificates_result(r)
          total = r.read_varint
          certs = total.times.map do
            cert_len = r.read_varint
            cert_r = Reader.new(r.read_bytes(cert_len))
            cert = read_cert_from_reader(cert_r)

            keyring_flag = r.read_int8
            if keyring_flag == 1
              kr_count = r.read_varint
              keyring = {}
              kr_count.times do
                k = r.read_utf8_string
                v_len = r.read_varint
                keyring[k] = encode_base64(r.read_bytes(v_len))
              end
              cert[:keyring] = keyring
            else
              cert[:keyring] = {}
            end

            ver_len = r.read_varint
            cert[:verifier] = ver_len.zero? ? nil : r.read_bytes(ver_len).unpack1('H*')
            cert
          end
          { total_certificates: total, certificates: certs }
        end

        # -----------------------------------------------------------------------
        # 19. proveCertificate
        # -----------------------------------------------------------------------

        def write_prove_certificate_params(w, args)
          cert = args[:certificate] || {}
          write_certificate_fields(w, cert)

          fields_to_reveal = args[:fields_to_reveal] || []
          w.write_varint(fields_to_reveal.length)
          fields_to_reveal.each { |f| w.write_utf8_string(f) }

          w.write_bytes([args[:verifier].to_s].pack('H*'))
          w.write_privileged(args[:privileged], args[:privileged_reason])
        end

        def read_prove_certificate_params(r)
          cert = read_cert_from_reader(r)

          ftr_count = r.read_varint
          fields_to_reveal = ftr_count.times.map { r.read_utf8_string }

          verifier = r.read_bytes(33).unpack1('H*')
          privileged, privileged_reason = r.read_privileged

          { certificate: cert, fields_to_reveal: fields_to_reveal,
            verifier: verifier, privileged: privileged, privileged_reason: privileged_reason }
        end

        def write_prove_certificate_result(w, result)
          keyring = result[:keyring_for_verifier] || {}
          w.write_varint(keyring.length)
          keyring.each do |k, v|
            w.write_utf8_string(k.to_s)
            v_bytes = decode_base64_32_safe(v.to_s)
            w.write_varint(v_bytes.bytesize)
            w.write_bytes(v_bytes)
          end
        end

        def read_prove_certificate_result(r)
          kr_count = r.read_varint
          keyring = {}
          kr_count.times do
            k = r.read_utf8_string
            v_len = r.read_varint
            keyring[k] = encode_base64(r.read_bytes(v_len))
          end
          { keyring_for_verifier: keyring }
        end

        # -----------------------------------------------------------------------
        # 20. relinquishCertificate
        # -----------------------------------------------------------------------

        def write_relinquish_certificate_params(w, args)
          w.write_bytes(decode_base64_32(args[:type].to_s))
          w.write_bytes(decode_base64_32(args[:serial_number].to_s))
          w.write_bytes([args[:certifier].to_s].pack('H*'))
        end

        def read_relinquish_certificate_params(r)
          type = encode_base64(r.read_bytes(32))
          serial_number = encode_base64(r.read_bytes(32))
          certifier = r.read_bytes(33).unpack1('H*')
          { type: type, serial_number: serial_number, certifier: certifier }
        end

        def write_relinquish_certificate_result(w, _result); end

        def read_relinquish_certificate_result(_r)
          { relinquished: true }
        end

        # -----------------------------------------------------------------------
        # 21. discoverByIdentityKey
        # -----------------------------------------------------------------------

        def write_discover_by_identity_key_params(w, args)
          w.write_bytes([args[:identity_key].to_s].pack('H*'))
          w.write_signed_varint(args[:limit].nil? ? -1 : args[:limit])
          w.write_signed_varint(args[:offset].nil? ? -1 : args[:offset])
          w.write_optional_bool(args[:seek_permission])
        end

        def read_discover_by_identity_key_params(r)
          identity_key = r.read_bytes(33).unpack1('H*')
          limit = r.read_signed_varint
          offset = r.read_signed_varint
          seek_permission = r.read_optional_bool
          { identity_key: identity_key,
            limit: limit == -1 ? nil : limit,
            offset: offset == -1 ? nil : offset,
            seek_permission: seek_permission }
        end

        def write_discover_by_identity_key_result(w, result)
          write_discovery_result(w, result)
        end

        def read_discover_by_identity_key_result(r)
          read_discovery_result(r)
        end

        # -----------------------------------------------------------------------
        # 22. discoverByAttributes
        # -----------------------------------------------------------------------

        def write_discover_by_attributes_params(w, args)
          attributes = args[:attributes] || {}
          w.write_varint(attributes.length)
          attributes.each do |k, v|
            w.write_utf8_string(k.to_s)
            w.write_utf8_string(v.to_s)
          end
          w.write_signed_varint(args[:limit].nil? ? -1 : args[:limit])
          w.write_signed_varint(args[:offset].nil? ? -1 : args[:offset])
          w.write_optional_bool(args[:seek_permission])
        end

        def read_discover_by_attributes_params(r)
          attr_count = r.read_varint
          attributes = {}
          attr_count.times do
            k = r.read_utf8_string
            attributes[k] = r.read_utf8_string
          end
          limit = r.read_signed_varint
          offset = r.read_signed_varint
          seek_permission = r.read_optional_bool
          { attributes: attributes,
            limit: limit == -1 ? nil : limit,
            offset: offset == -1 ? nil : offset,
            seek_permission: seek_permission }
        end

        def write_discover_by_attributes_result(w, result)
          write_discovery_result(w, result)
        end

        def read_discover_by_attributes_result(r)
          read_discovery_result(r)
        end

        # -----------------------------------------------------------------------
        # 23. isAuthenticated  (no params)
        # -----------------------------------------------------------------------

        def write_is_authenticated_params(w, _args); end

        def read_is_authenticated_params(_r)
          {}
        end

        def write_is_authenticated_result(w, result)
          w.write_byte(result[:authenticated] ? 1 : 0)
        end

        def read_is_authenticated_result(r)
          { authenticated: r.read_byte == 1 }
        end

        # -----------------------------------------------------------------------
        # 24. waitForAuthentication  (no params)
        # -----------------------------------------------------------------------

        def write_wait_for_authentication_params(w, _args); end

        def read_wait_for_authentication_params(_r)
          {}
        end

        def write_wait_for_authentication_result(w, _result); end

        def read_wait_for_authentication_result(_r)
          { authenticated: true }
        end

        # -----------------------------------------------------------------------
        # 25. getHeight  (no params)
        # -----------------------------------------------------------------------

        def write_get_height_params(w, _args); end

        def read_get_height_params(_r)
          {}
        end

        def write_get_height_result(w, result)
          w.write_varint(result[:height].to_i)
        end

        def read_get_height_result(r)
          { height: r.read_varint }
        end

        # -----------------------------------------------------------------------
        # 26. getHeaderForHeight
        # -----------------------------------------------------------------------

        def write_get_header_for_height_params(w, args)
          w.write_varint(args[:height].to_i)
        end

        def read_get_header_for_height_params(r)
          { height: r.read_varint }
        end

        def write_get_header_for_height_result(w, result)
          header_bytes = [result[:header].to_s].pack('H*')
          w.write_bytes(header_bytes)
        end

        def read_get_header_for_height_result(r)
          { header: r.read_remaining.unpack1('H*') }
        end

        # -----------------------------------------------------------------------
        # 27. getNetwork  (no params)
        # -----------------------------------------------------------------------

        def write_get_network_params(w, _args); end

        def read_get_network_params(_r)
          {}
        end

        def write_get_network_result(w, result)
          w.write_byte(result[:network] == 'mainnet' ? 0 : 1)
        end

        def read_get_network_result(r)
          { network: r.read_byte.zero? ? 'mainnet' : 'testnet' }
        end

        # -----------------------------------------------------------------------
        # 28. getVersion  (no params)
        # -----------------------------------------------------------------------

        def write_get_version_params(w, _args); end

        def read_get_version_params(_r)
          {}
        end

        def write_get_version_result(w, result)
          version_bytes = result[:version].to_s.encode('UTF-8').b
          w.write_bytes(version_bytes)
        end

        def read_get_version_result(r)
          { version: r.read_remaining.force_encoding('UTF-8') }
        end
      end
    end
  end
end
