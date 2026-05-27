# frozen_string_literal: true

require 'base64'

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +list_certificates+ call (call byte 18).
      #
      # Args wire layout:
      #   [varint: certifier_count] per certifier: [33-byte pubkey]
      #   [varint: type_count] per type: [32-byte raw type]
      #   [optional_uint32: limit]
      #   [optional_uint32: offset]
      #   [privileged params]
      #
      # Result wire layout:
      #   [varint: total_certificates]
      #   per certificate:
      #     [varint-int: serialised Certificate bytes]
      #     [1 byte: keyring present flag (0/1)]
      #     If keyring present:
      #       [varint: keyring_count] per entry: [varint-str key][varint-int base64 bytes]
      #     [varint-int: verifier bytes]
      module ListCertificates
        CERT_TYPE_SIZE = 32
        PUBKEY_SIZE    = 33

        module_function

        def serialize_args(args)
          w = Wire::Writer.new

          certifiers = args[:certifiers] || []
          w.write_varint(certifiers.length)
          certifiers.each { |c| w.write_bytes([c.to_s].pack('H*')) }

          types = args[:types] || []
          w.write_varint(types.length)
          types.each do |t|
            type_bytes = Base64.strict_decode64(t.to_s)
            w.write_bytes(type_bytes.ljust(CERT_TYPE_SIZE, "\x00").byteslice(0, CERT_TYPE_SIZE))
          end

          w.write_optional_uint32(args[:limit])
          w.write_optional_uint32(args[:offset])
          Common.write_privileged_params(w, args[:privileged], args[:privileged_reason])
          w.buf
        end

        def deserialize_args(bytes)
          r = Wire::Reader.new(bytes)

          certifier_count = r.read_varint
          certifiers = certifier_count.times.map { r.read_bytes(PUBKEY_SIZE).unpack1('H*') }

          type_count = r.read_varint
          types = type_count.times.map { Base64.strict_encode64(r.read_bytes(CERT_TYPE_SIZE)) }

          limit  = r.read_optional_uint32
          offset = r.read_optional_uint32
          privileged, privileged_reason = Common.read_privileged_params(r)

          { certifiers: certifiers, types: types, limit: limit, offset: offset,
            privileged: privileged, privileged_reason: privileged_reason }
        end

        def serialize_result(result)
          w = Wire::Writer.new
          certs = result[:certificates] || []
          w.write_varint(certs.length)

          certs.each do |cert_result|
            cert        = cert_result[:certificate] || cert_result
            cert_bytes  = Certificate.serialize_certificate(cert, include_signature: true)
            w.write_int_bytes(cert_bytes)

            keyring = cert_result[:keyring]
            if keyring
              w.write_byte(1)
              w.write_varint(keyring.length)
              keyring.keys.sort.each do |k|
                w.write_str_with_varint_len(k)
                w.write_int_from_base64(keyring[k].to_s)
              end
            else
              w.write_byte(0)
            end

            verifier = cert_result[:verifier]
            w.write_int_bytes(verifier ? verifier.b : ''.b)
          end

          w.buf
        end

        def deserialize_result(bytes)
          r = Wire::Reader.new(bytes)
          total = r.read_varint

          certificates = total.times.map do
            cert_bytes = r.read_int_bytes
            cert = Certificate.deserialize_certificate(cert_bytes)

            keyring = nil
            if r.read_byte == 1
              keyring_len = r.read_varint
              keyring = {}
              keyring_len.times do
                k = r.read_str_with_varint_len
                keyring[k] = r.read_base64_int
              end
            end

            verifier = r.read_int_bytes
            { certificate: cert, keyring: keyring, verifier: verifier.empty? ? nil : verifier }
          end

          { total_certificates: total, certificates: certificates }
        end
      end
    end
  end
end
