# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # Shared BRC-103 result codec for discover_by_identity_key and
      # discover_by_attributes (both return the same shape).
      #
      # Result wire layout:
      #   [varint: total_certificates]
      #   per certificate: [IdentityCertificate inline bytes (int-prefixed base cert + meta)]
      module DiscoverCertificatesResult
        module_function

        # @param result [Hash] { total_certificates:, certificates: [IdentityCert Hash, ...] }
        # @return [String] binary
        def serialize(result)
          certs = result[:certificates] || []
          w = Wire::Writer.new
          w.write_varint(certs.length)
          certs.each do |cert|
            cert_bytes = Certificate.serialize_identity_certificate(cert)
            w.write_bytes(cert_bytes)
          end
          w.buf
        end

        # @param bytes [String] binary
        # @return [Hash] { total_certificates:, certificates: [...] }
        def deserialize(bytes)
          r = Wire::Reader.new(bytes)
          total = r.read_varint
          certs = total.times.map { Certificate.deserialize_identity_certificate(r) }
          { total_certificates: total, certificates: certs }
        end
      end
    end
  end
end
