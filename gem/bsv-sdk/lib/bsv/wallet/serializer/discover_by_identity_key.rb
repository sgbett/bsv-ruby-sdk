# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +discover_by_identity_key+ call (call byte 21).
      #
      # Args wire layout:
      #   [33 bytes: identity_key compressed pubkey]
      #   [optional_uint32: limit]
      #   [optional_uint32: offset]
      #   [optional_bool: seek_permission]
      #
      # Result wire layout: see DiscoverCertificatesResult.
      module DiscoverByIdentityKey
        PUBKEY_SIZE = 33

        module_function

        def serialize_args(args)
          w = Wire::Writer.new
          w.write_bytes([args[:identity_key].to_s].pack('H*'))
          w.write_optional_uint32(args[:limit])
          w.write_optional_uint32(args[:offset])
          w.write_optional_bool(args[:seek_permission])
          w.buf
        end

        def deserialize_args(bytes)
          r = Wire::Reader.new(bytes)
          identity_key = r.read_bytes(PUBKEY_SIZE).unpack1('H*')
          limit           = r.read_optional_uint32
          offset          = r.read_optional_uint32
          seek_permission = r.read_optional_bool
          { identity_key: identity_key, limit: limit, offset: offset,
            seek_permission: seek_permission }
        end

        def serialize_result(result)
          DiscoverCertificatesResult.serialize(result)
        end

        def deserialize_result(bytes)
          DiscoverCertificatesResult.deserialize(bytes)
        end
      end
    end
  end
end
