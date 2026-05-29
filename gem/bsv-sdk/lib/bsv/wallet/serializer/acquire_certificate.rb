# frozen_string_literal: true

require 'base64'

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +acquire_certificate+ call (call byte 17).
      #
      # Args wire layout:
      #   [32 bytes: type]
      #   [33 bytes: certifier pubkey]
      #   [varint: field_count] per field: [varint-str key][varint-str value]
      #   [privileged params]
      #   [1 byte: acquisition_protocol]  1=direct, 2=issuance
      #   If direct:
      #     [32 bytes: serial_number]
      #     [36 bytes: revocation_outpoint]
      #     [varint: sig_len][sig bytes]
      #     [keyring_revealer: 0x0B or 33-byte pubkey]
      #     [varint: keyring_count] per entry: [varint-str key][varint-int base64_value]
      #   If issuance:
      #     [varint-str: certifier_url]
      #
      # Result wire layout:
      #   [inline Certificate bytes (type+serial+subject+certifier+outpoint+fields+sig)]
      module AcquireCertificate
        ACQUISITION_DIRECT   = 1
        ACQUISITION_ISSUANCE = 2
        KEYRING_REVEALER_CERTIFIER = 11 # 0x0B — matches Go keyRingRevealerCertifier

        CERT_TYPE_SIZE = 32
        SERIAL_SIZE    = 32
        PUBKEY_SIZE    = 33

        module_function

        def serialize_args(args)
          w = Wire::Writer.new

          type_bytes = Base64.strict_decode64(args[:type].to_s)
          w.write_bytes(type_bytes.ljust(CERT_TYPE_SIZE, "\x00").byteslice(0, CERT_TYPE_SIZE))
          w.write_bytes([args[:certifier].to_s].pack('H*'))

          fields = args[:fields] || {}
          w.write_varint(fields.length)
          fields.keys.sort.each do |k|
            w.write_str_with_varint_len(k)
            w.write_str_with_varint_len(fields[k].to_s)
          end

          Common.write_privileged_params(w, args[:privileged], args[:privileged_reason])

          case args[:acquisition_protocol]
          when :direct
            w.write_byte(ACQUISITION_DIRECT)
            serial_bytes = Base64.strict_decode64(args[:serial_number].to_s)
            w.write_bytes(serial_bytes.ljust(SERIAL_SIZE, "\x00").byteslice(0, SERIAL_SIZE))

            outpoint_str = args[:revocation_outpoint].to_s
            txid_hex, vout = outpoint_str.split('.', 2)
            w.write_outpoint(txid_hex.to_s, vout.to_i)

            sig = args[:signature]
            if sig && !sig.to_s.empty?
              sig_bytes = [sig.to_s].pack('H*')
              w.write_int_bytes(sig_bytes)
            else
              w.write_varint(0)
            end

            revealer = args[:keyring_revealer]
            if revealer == :certifier || (revealer.is_a?(Hash) && revealer[:certifier])
              w.write_byte(KEYRING_REVEALER_CERTIFIER)
            else
              pubkey_hex = revealer.is_a?(Hash) ? revealer[:pub_key].to_s : revealer.to_s
              w.write_bytes([pubkey_hex].pack('H*'))
            end

            keyring = args[:keyring_for_subject] || {}
            w.write_varint(keyring.length)
            keyring.keys.sort.each do |k|
              w.write_str_with_varint_len(k)
              w.write_int_from_base64(keyring[k].to_s)
            end
          when :issuance
            w.write_byte(ACQUISITION_ISSUANCE)
            w.write_str_with_varint_len(args[:certifier_url].to_s)
          else
            raise ArgumentError, "invalid acquisition_protocol: #{args[:acquisition_protocol].inspect}"
          end

          w.buf
        end

        def deserialize_args(bytes)
          r = Wire::Reader.new(bytes)

          type_raw  = r.read_bytes(CERT_TYPE_SIZE)
          certifier = r.read_bytes(PUBKEY_SIZE).unpack1('H*')

          field_count = r.read_varint
          fields = {}
          field_count.times do
            k = r.read_str_with_varint_len
            v = r.read_str_with_varint_len
            fields[k] = v
          end

          privileged, privileged_reason = Common.read_privileged_params(r)

          protocol_byte = r.read_byte
          acquisition_protocol = case protocol_byte
                                 when ACQUISITION_DIRECT   then :direct
                                 when ACQUISITION_ISSUANCE then :issuance
                                 else raise ArgumentError, "invalid acquisition protocol byte: #{protocol_byte}"
                                 end

          result = {
            type: Base64.strict_encode64(type_raw),
            certifier: certifier,
            fields: fields,
            privileged: privileged,
            privileged_reason: privileged_reason,
            acquisition_protocol: acquisition_protocol
          }

          if acquisition_protocol == :direct
            serial_raw = r.read_bytes(SERIAL_SIZE)
            result[:serial_number] = Base64.strict_encode64(serial_raw)

            outpoint_data = r.read_outpoint
            result[:revocation_outpoint] = "#{outpoint_data[:txid_hex]}.#{outpoint_data[:vout]}"

            sig_len = r.read_varint
            result[:signature] = sig_len.positive? ? r.read_bytes(sig_len).unpack1('H*') : nil

            revealer_byte = r.read_byte
            if revealer_byte == KEYRING_REVEALER_CERTIFIER
              result[:keyring_revealer] = { certifier: true }
            else
              rest = r.read_bytes(PUBKEY_SIZE - 1)
              result[:keyring_revealer] = { pub_key: ([revealer_byte].pack('C') + rest).unpack1('H*') }
            end

            keyring_count = r.read_varint
            keyring = {}
            keyring_count.times do
              k = r.read_str_with_varint_len
              keyring[k] = r.read_base64_int
            end
            result[:keyring_for_subject] = keyring
          else
            result[:certifier_url] = r.read_str_with_varint_len
          end

          result
        end

        def serialize_result(result)
          Certificate.serialize_certificate(result[:certificate] || result, include_signature: true)
        end

        def deserialize_result(bytes)
          cert = Certificate.deserialize_certificate(bytes)
          { certificate: cert }
        end
      end
    end
  end
end
