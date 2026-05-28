# frozen_string_literal: true

require 'base64'

module BSV
  module Wallet
    module Serializer
      # Shared BRC-103 wire codec for Certificate and IdentityCertificate.
      #
      # Certificate wire layout (matches go-sdk serializeCertificate):
      #   [32 bytes: type (raw bytes decoded from Base64)]
      #   [32 bytes: serial_number (raw bytes decoded from Base64)]
      #   [33 bytes: subject compressed pubkey]
      #   [33 bytes: certifier compressed pubkey]
      #   [32 bytes + varint: revocation_outpoint (display-order txid + varint vout)]
      #   [varint: field_count]
      #   per field: [varint-len name][varint-len value]
      #   [remaining: DER signature bytes (absent if no signature)]
      #
      # IdentityCertificate additionally appends:
      #   [varint-int: serialised Certificate bytes (int-prefixed)]
      #   [varint-str: certifier_info.name]
      #   [varint-str: certifier_info.icon_url]
      #   [varint-str: certifier_info.description]
      #   [1 byte: certifier_info.trust]
      #   [varint: keyring_count] per entry: [varint-str key][varint-int raw_bytes]
      #   [varint: decrypted_fields_count] per entry: [varint-str key][varint-str value]
      module Certificate
        CERT_TYPE_SIZE   = 32
        SERIAL_SIZE      = 32
        PUBKEY_SIZE      = 33

        # NULL outpoint used when revocation_outpoint is nil.
        NULL_TXID_HEX = '00' * 32

        module_function

        # Serialise a certificate Hash to binary.
        #
        # @param cert [Hash] with keys: :type (Base64), :serial_number (Base64),
        #   :subject (hex pubkey), :certifier (hex pubkey),
        #   :revocation_outpoint (String "txid.vout" or nil),
        #   :fields (Hash<String,String>), :signature (hex bytes or nil)
        # @param include_signature [Boolean] whether to append signature bytes
        # @return [String] binary
        def serialize_certificate(cert, include_signature: true)
          w = Wire::Writer.new

          type_bytes   = Base64.strict_decode64(cert[:type].to_s)
          serial_bytes = Base64.strict_decode64(cert[:serial_number].to_s)

          w.write_bytes(type_bytes.ljust(CERT_TYPE_SIZE, "\x00").byteslice(0, CERT_TYPE_SIZE))
          w.write_bytes(serial_bytes.ljust(SERIAL_SIZE, "\x00").byteslice(0, SERIAL_SIZE))
          w.write_bytes([cert[:subject].to_s].pack('H*'))
          w.write_bytes([cert[:certifier].to_s].pack('H*'))

          outpoint_str = cert[:revocation_outpoint].to_s
          if outpoint_str.empty? || outpoint_str == '.'
            w.write_outpoint(NULL_TXID_HEX, 0)
          else
            txid_hex, vout = outpoint_str.split('.', 2)
            w.write_outpoint(txid_hex.to_s, vout.to_i)
          end

          fields = cert[:fields] || {}
          w.write_varint(fields.length)
          fields.keys.sort.each do |name|
            w.write_str_with_varint_len(name)
            w.write_str_with_varint_len(fields[name].to_s)
          end

          w.write_bytes([cert[:signature].to_s].pack('H*')) if include_signature && cert[:signature] && !cert[:signature].empty?

          w.buf
        end

        # Deserialise a certificate from binary.
        #
        # @param bytes [String] binary
        # @return [Hash]
        def deserialize_certificate(bytes)
          r = Wire::Reader.new(bytes)
          type_raw   = r.read_bytes(CERT_TYPE_SIZE)
          serial_raw = r.read_bytes(SERIAL_SIZE)
          subject    = r.read_bytes(PUBKEY_SIZE).unpack1('H*')
          certifier  = r.read_bytes(PUBKEY_SIZE).unpack1('H*')

          outpoint_data       = r.read_outpoint
          revocation_outpoint = "#{outpoint_data[:txid_hex]}.#{outpoint_data[:vout]}"

          field_count = r.read_varint
          fields = {}
          field_count.times do
            name  = r.read_str_with_varint_len
            value = r.read_str_with_varint_len
            fields[name] = value
          end

          sig_bytes = r.read_remaining
          signature = sig_bytes.empty? ? nil : sig_bytes.unpack1('H*')

          {
            type: Base64.strict_encode64(type_raw),
            serial_number: Base64.strict_encode64(serial_raw),
            subject: subject,
            certifier: certifier,
            revocation_outpoint: revocation_outpoint,
            fields: fields,
            signature: signature
          }
        end

        # Serialise an IdentityCertificate (used by discover_* result).
        #
        # @param cert [Hash] all Certificate fields plus:
        #   :certifier_info ({ name:, icon_url:, description:, trust: })
        #   :publicly_revealed_keyring (Hash<String,Base64>)
        #   :decrypted_fields (Hash<String,String>)
        def serialize_identity_certificate(cert)
          w = Wire::Writer.new

          cert_bytes = serialize_certificate(cert, include_signature: true)
          w.write_int_bytes(cert_bytes)

          info = cert[:certifier_info] || {}
          w.write_str_with_varint_len(info[:name].to_s)
          w.write_str_with_varint_len(info[:icon_url].to_s)
          w.write_str_with_varint_len(info[:description].to_s)
          w.write_byte((info[:trust] || 0).to_i & 0xFF)

          keyring = cert[:publicly_revealed_keyring] || {}
          w.write_varint(keyring.length)
          keyring.keys.sort.each do |k|
            w.write_str_with_varint_len(k)
            w.write_int_from_base64(keyring[k].to_s)
          end

          dec_fields = cert[:decrypted_fields] || {}
          w.write_varint(dec_fields.length)
          dec_fields.keys.sort.each do |k|
            w.write_str_with_varint_len(k)
            w.write_str_with_varint_len(dec_fields[k].to_s)
          end

          w.buf
        end

        # Deserialise an IdentityCertificate from a Reader (reads inline, not length-prefixed).
        #
        # @param reader [Wire::Reader]
        # @return [Hash]
        def deserialize_identity_certificate(reader)
          cert_bytes = reader.read_int_bytes
          cert = deserialize_certificate(cert_bytes)

          cert[:certifier_info] = {
            name: reader.read_str_with_varint_len,
            icon_url: reader.read_str_with_varint_len,
            description: reader.read_str_with_varint_len,
            trust: reader.read_byte
          }

          keyring_len = reader.read_varint
          keyring = {}
          keyring_len.times do
            k = reader.read_str_with_varint_len
            keyring[k] = reader.read_base64_int
          end
          cert[:publicly_revealed_keyring] = keyring

          dec_len = reader.read_varint
          dec_fields = {}
          dec_len.times do
            k = reader.read_str_with_varint_len
            dec_fields[k] = reader.read_str_with_varint_len
          end
          cert[:decrypted_fields] = dec_fields

          cert
        end
      end
    end
  end
end
