# frozen_string_literal: true

module BSV
  module Wallet
    module Serializer
      # BRC-103 wire codec for the +discover_by_attributes+ call (call byte 22).
      #
      # Args wire layout:
      #   [varint: attribute_count] per entry: [varint-int key_bytes][varint-int value_bytes]
      #   [optional_uint32: limit]
      #   [optional_uint32: offset]
      #   [optional_bool: seek_permission]
      #
      # Result wire layout: see DiscoverCertificatesResult.
      #
      # Keys are written in sorted order (matching Go sort.Strings) to ensure
      # deterministic encoding across SDK implementations.
      module DiscoverByAttributes
        module_function

        def serialize_args(args)
          w = Wire::Writer.new
          attributes = args[:attributes] || {}
          w.write_varint(attributes.length)
          attributes.keys.sort.each do |k|
            w.write_int_bytes(k.to_s.b)
            w.write_int_bytes(attributes[k].to_s.b)
          end
          w.write_optional_uint32(args[:limit])
          w.write_optional_uint32(args[:offset])
          w.write_optional_bool(args[:seek_permission])
          w.buf
        end

        def deserialize_args(bytes)
          r = Wire::Reader.new(bytes)
          count = r.read_varint
          attributes = {}
          count.times do
            k = r.read_int_bytes.force_encoding('UTF-8')
            v = r.read_int_bytes.force_encoding('UTF-8')
            attributes[k] = v
          end
          limit           = r.read_optional_uint32
          offset          = r.read_optional_uint32
          seek_permission = r.read_optional_bool
          { attributes: attributes, limit: limit, offset: offset,
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
