# frozen_string_literal: true

require 'base64'

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +prove_certificate+ call (call byte 19).
      #
      # Args wire layout (matches go-sdk SerializeProveCertificateArgs):
      #   [32 bytes: cert.type]
      #   [33 bytes: cert.subject pubkey]
      #   [32 bytes: cert.serial_number]
      #   [33 bytes: cert.certifier pubkey]
      #   [36 bytes: cert.revocation_outpoint]
      #   [varint-int: cert.signature bytes] (0-length if nil)
      #   [varint: field_count] per field: [varint-int name_bytes][varint-int value_bytes]
      #   [varint: fields_to_reveal_count] per field: [varint-int name_bytes]
      #   [33 bytes: verifier pubkey]
      #   [privileged params]
      #
      # Result wire layout:
      #   [varint: keyring_count] per entry: [varint-int key_bytes][varint-int base64 bytes]
      module ProveCertificate
        CERT_TYPE_SIZE = 32
        SERIAL_SIZE    = 32
        PUBKEY_SIZE    = 33

        module_function

        def serialize_args(args)
          w = Wire::Writer.new
          cert = args[:certificate] || {}

          type_bytes = Base64.strict_decode64(cert[:type].to_s)
          w.write_bytes(type_bytes.ljust(CERT_TYPE_SIZE, "\x00").byteslice(0, CERT_TYPE_SIZE))
          w.write_bytes([cert[:subject].to_s].pack('H*'))

          serial_bytes = Base64.strict_decode64(cert[:serial_number].to_s)
          w.write_bytes(serial_bytes.ljust(SERIAL_SIZE, "\x00").byteslice(0, SERIAL_SIZE))
          w.write_bytes([cert[:certifier].to_s].pack('H*'))

          outpoint_str = cert[:revocation_outpoint].to_s
          if outpoint_str.empty? || outpoint_str == '.'
            w.write_outpoint(Certificate::NULL_TXID_HEX, 0)
          else
            txid_hex, vout = outpoint_str.split('.', 2)
            w.write_outpoint(txid_hex.to_s, vout.to_i)
          end

          sig = cert[:signature]
          if sig && !sig.to_s.empty?
            w.write_int_bytes([sig.to_s].pack('H*'))
          else
            w.write_int_bytes(''.b)
          end

          fields = cert[:fields] || {}
          w.write_varint(fields.length)
          fields.keys.sort.each do |k|
            w.write_int_bytes(k.b)
            w.write_int_bytes(fields[k].to_s.b)
          end

          fields_to_reveal = args[:fields_to_reveal] || []
          w.write_varint(fields_to_reveal.length)
          fields_to_reveal.each { |f| w.write_int_bytes(f.to_s.b) }

          w.write_bytes([args[:verifier].to_s].pack('H*'))

          Common.write_privileged_params(w, args[:privileged], args[:privileged_reason])
          w.buf
        end

        def deserialize_args(bytes)
          r = Wire::Reader.new(bytes)

          type_raw   = r.read_bytes(CERT_TYPE_SIZE)
          subject    = r.read_bytes(PUBKEY_SIZE).unpack1('H*')
          serial_raw = r.read_bytes(SERIAL_SIZE)
          certifier  = r.read_bytes(PUBKEY_SIZE).unpack1('H*')

          outpoint_data = r.read_outpoint
          revocation_outpoint = "#{outpoint_data[:txid_hex]}.#{outpoint_data[:vout]}"

          sig_bytes = r.read_int_bytes
          signature = sig_bytes.empty? ? nil : sig_bytes.unpack1('H*')

          field_count = r.read_varint
          fields = {}
          field_count.times do
            k = r.read_int_bytes.force_encoding('UTF-8')
            v = r.read_int_bytes.force_encoding('UTF-8')
            fields[k] = v
          end

          fields_to_reveal_count = r.read_varint
          fields_to_reveal = fields_to_reveal_count.times.map do
            r.read_int_bytes.force_encoding('UTF-8')
          end

          verifier = r.read_bytes(PUBKEY_SIZE).unpack1('H*')
          privileged, privileged_reason = Common.read_privileged_params(r)

          {
            certificate: {
              type: Base64.strict_encode64(type_raw),
              subject: subject,
              serial_number: Base64.strict_encode64(serial_raw),
              certifier: certifier,
              revocation_outpoint: revocation_outpoint,
              signature: signature,
              fields: fields
            },
            fields_to_reveal: fields_to_reveal,
            verifier: verifier,
            privileged: privileged,
            privileged_reason: privileged_reason
          }
        end

        def serialize_result(result)
          w = Wire::Writer.new
          keyring = result[:keyring_for_verifier] || {}
          w.write_varint(keyring.length)
          keyring.keys.sort.each do |k|
            w.write_int_bytes(k.to_s.b)
            w.write_int_from_base64(keyring[k].to_s)
          end
          w.buf
        end

        def deserialize_result(bytes)
          r = Wire::Reader.new(bytes)
          count = r.read_varint
          keyring = {}
          count.times do
            k = r.read_int_bytes.force_encoding('UTF-8')
            keyring[k] = r.read_base64_int
          end
          { keyring_for_verifier: keyring }
        end
      end
    end
  end
end
