# frozen_string_literal: true

require 'base64'

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +relinquish_certificate+ call (call byte 20).
      #
      # Args wire layout:
      #   [32 bytes: type]
      #   [32 bytes: serial_number]
      #   [33 bytes: certifier pubkey]
      #
      # Result wire layout:
      #   [empty — relinquished is implicit from the frame error byte]
      module RelinquishCertificate
        CERT_TYPE_SIZE = 32
        SERIAL_SIZE    = 32
        PUBKEY_SIZE    = 33

        module_function

        def serialize_args(args)
          w = Wire::Writer.new
          type_bytes = Base64.strict_decode64(args[:type].to_s)
          w.write_bytes(type_bytes.ljust(CERT_TYPE_SIZE, "\x00").byteslice(0, CERT_TYPE_SIZE))
          serial_bytes = Base64.strict_decode64(args[:serial_number].to_s)
          w.write_bytes(serial_bytes.ljust(SERIAL_SIZE, "\x00").byteslice(0, SERIAL_SIZE))
          w.write_bytes([args[:certifier].to_s].pack('H*'))
          w.buf
        end

        def deserialize_args(bytes)
          r = Wire::Reader.new(bytes)
          type_raw   = r.read_bytes(CERT_TYPE_SIZE)
          serial_raw = r.read_bytes(SERIAL_SIZE)
          certifier  = r.read_bytes(PUBKEY_SIZE).unpack1('H*')
          {
            type: Base64.strict_encode64(type_raw),
            serial_number: Base64.strict_encode64(serial_raw),
            certifier: certifier
          }
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
