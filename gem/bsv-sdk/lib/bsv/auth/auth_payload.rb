# frozen_string_literal: true

require 'bsv/transaction/var_int'

module BSV
  module Auth
    # BRC-104 binary serialisation and deserialisation of HTTP requests and
    # responses for signing/verification.
    #
    # The wire format is byte-compatible with the TS and Go SDKs, enabling
    # cross-SDK signature verification.
    #
    # Absent optional fields (nil path, nil query, nil body) are encoded as
    # +ABSENT+ (VarInt MAX_UINT64 = 9 bytes of 0xFF). Zero-length fields are
    # encoded as varint(0) followed by zero bytes — a distinct encoding from absent.
    #
    # All varint operations delegate to {BSV::Transaction::VarInt}.
    module AuthPayload
      module_function

      # Sentinel value for absent optional fields (Bitcoin VarInt MAX_UINT64).
      ABSENT = BSV::Transaction::VarInt::MAX_UINT64

      # HTTP methods that typically carry a request body.
      METHODS_WITH_BODY = %w[POST PUT PATCH DELETE].freeze

      # Serialises an HTTP request into a binary payload for signing.
      #
      # @param request_nonce [String] raw 32-byte binary string (the request nonce)
      # @param method [String] HTTP method (e.g. 'GET', 'POST')
      # @param path [String, nil] URL path (e.g. '/api/v1/resource'); nil encodes as ABSENT
      # @param query [String, nil] query string including leading '?' (e.g. '?q=hello'); nil encodes as ABSENT
      # @param headers [Array<Array(String, String)>] pre-sorted, lowercased [key, value] pairs
      # @param body [String, nil] request body bytes; nil encodes as ABSENT
      # @return [String] binary payload (ASCII-8BIT encoding)
      def serialize_request(request_nonce:, method:, path:, query:, headers:, body:)
        unless request_nonce.is_a?(String) && request_nonce.bytesize == 32
          got = request_nonce.respond_to?(:bytesize) ? "#{request_nonce.class}/#{request_nonce.bytesize}" : request_nonce.class
          raise ArgumentError, "request_nonce must be a 32-byte binary string, got #{got}"
        end

        buf = ''.b

        # 32-byte request nonce — written raw, no length prefix
        buf << request_nonce.b

        # Method — always present; varint(length) + UTF-8 bytes
        effective_method = method.nil? || method.empty? ? 'GET' : method
        method_bytes = effective_method.encode('UTF-8').b
        buf << BSV::Transaction::VarInt.encode(method_bytes.bytesize)
        buf << method_bytes

        # Path — optional
        buf << encode_optional_string(path)

        # Query — optional
        buf << encode_optional_string(query)

        # Headers — varint count + key/value pairs
        pairs = headers || []
        buf << BSV::Transaction::VarInt.encode(pairs.length)
        pairs.each do |k, v|
          key_bytes = k.to_s.encode('UTF-8').b
          val_bytes = v.to_s.encode('UTF-8').b
          buf << BSV::Transaction::VarInt.encode(key_bytes.bytesize)
          buf << key_bytes
          buf << BSV::Transaction::VarInt.encode(val_bytes.bytesize)
          buf << val_bytes
        end

        # Body — apply defaults for body-carrying methods, then encode optionally
        effective_body = resolve_body(method: effective_method, headers: pairs, body: body)
        buf << encode_optional_bytes(effective_body)

        buf
      end

      # Deserialises a binary request payload into a Hash.
      #
      # @param data [String] binary payload (as returned by {.serialize_request})
      # @return [Hash] with keys +:request_nonce+, +:method+, +:path+, +:query+,
      #   +:headers+, +:body+ (all values may be nil for absent optional fields)
      def deserialize_request(data)
        bin = data.b
        pos = 0

        # 32-byte request nonce
        request_nonce = bin.byteslice(pos, 32)
        pos += 32

        # Method
        method_len, consumed = BSV::Transaction::VarInt.decode(bin, pos)
        pos += consumed
        method = bin.byteslice(pos, method_len).force_encoding('UTF-8')
        pos += method_len

        # Path (optional)
        path, pos = decode_optional_string(bin, pos)

        # Query (optional)
        query, pos = decode_optional_string(bin, pos)

        # Headers
        n_headers, consumed = BSV::Transaction::VarInt.decode(bin, pos)
        pos += consumed
        headers = []
        n_headers.times do
          k_len, consumed = BSV::Transaction::VarInt.decode(bin, pos)
          pos += consumed
          k = bin.byteslice(pos, k_len).force_encoding('UTF-8')
          pos += k_len

          v_len, consumed = BSV::Transaction::VarInt.decode(bin, pos)
          pos += consumed
          v = bin.byteslice(pos, v_len).force_encoding('UTF-8')
          pos += v_len

          headers << [k, v]
        end

        # Body (optional)
        body, _pos = decode_optional_bytes(bin, pos)

        { request_nonce: request_nonce, method: method, path: path, query: query,
          headers: headers, body: body }
      end

      # Serialises an HTTP response into a binary payload for signing.
      #
      # @param request_id [String] raw 32-byte binary string
      # @param status [Integer] HTTP status code (e.g. 200, 404)
      # @param headers [Array<Array(String, String)>] pre-sorted, lowercased [key, value] pairs
      # @param body [String, nil] response body bytes; nil or empty encodes as ABSENT
      # @return [String] binary payload (ASCII-8BIT encoding)
      def serialize_response(request_id:, status:, headers:, body:)
        buf = ''.b

        # 32-byte request ID — written raw
        buf << request_id.b

        # Status code as varint
        buf << BSV::Transaction::VarInt.encode(status)

        # Headers
        pairs = headers || []
        buf << BSV::Transaction::VarInt.encode(pairs.length)
        pairs.each do |k, v|
          key_bytes = k.to_s.encode('UTF-8').b
          val_bytes = v.to_s.encode('UTF-8').b
          buf << BSV::Transaction::VarInt.encode(key_bytes.bytesize)
          buf << key_bytes
          buf << BSV::Transaction::VarInt.encode(val_bytes.bytesize)
          buf << val_bytes
        end

        # Body — write length + bytes; ABSENT if nil
        buf << encode_optional_bytes(body)

        buf
      end

      # Deserialises a binary response payload into a Hash.
      #
      # @param data [String] binary payload (as returned by {.serialize_response})
      # @return [Hash] with keys +:request_id+, +:status+, +:headers+, +:body+
      def deserialize_response(data)
        bin = data.b
        pos = 0

        # 32-byte request ID
        request_id = bin.byteslice(pos, 32)
        pos += 32

        # Status code
        status, consumed = BSV::Transaction::VarInt.decode(bin, pos)
        pos += consumed

        # Headers
        n_headers, consumed = BSV::Transaction::VarInt.decode(bin, pos)
        pos += consumed
        headers = []
        n_headers.times do
          k_len, consumed = BSV::Transaction::VarInt.decode(bin, pos)
          pos += consumed
          k = bin.byteslice(pos, k_len).force_encoding('UTF-8')
          pos += k_len

          v_len, consumed = BSV::Transaction::VarInt.decode(bin, pos)
          pos += consumed
          v = bin.byteslice(pos, v_len).force_encoding('UTF-8')
          pos += v_len

          headers << [k, v]
        end

        # Body (optional)
        body, _pos = decode_optional_bytes(bin, pos)

        { request_id: request_id, status: status, headers: headers, body: body }
      end

      # -- Private helpers -------------------------------------------------

      # Encodes a string field optionally (absent = ABSENT varint, present = length + bytes).
      def encode_optional_string(value)
        return BSV::Transaction::VarInt.encode(ABSENT) if value.nil?

        bytes = value.encode('UTF-8').b
        BSV::Transaction::VarInt.encode(bytes.bytesize) + bytes
      end
      private_class_method :encode_optional_string

      # Encodes a byte field optionally (absent = ABSENT varint, present = length + bytes).
      # Both nil and empty string are treated as absent, matching Go and TS SDK behaviour
      # (Go: WriteIntBytesOptional writes ABSENT when len == 0; TS: +if (body)+ is falsy
      # for empty string).
      def encode_optional_bytes(value)
        return BSV::Transaction::VarInt.encode(ABSENT) if value.nil? || value.empty?

        bytes = value.b
        BSV::Transaction::VarInt.encode(bytes.bytesize) + bytes
      end
      private_class_method :encode_optional_bytes

      # Decodes an optional string from +data+ at +pos+.
      # Returns [value_or_nil, new_pos].
      def decode_optional_string(data, pos)
        len, consumed = BSV::Transaction::VarInt.decode(data, pos)
        pos += consumed
        return [nil, pos] if len == ABSENT

        value = data.byteslice(pos, len).force_encoding('UTF-8')
        [value, pos + len]
      end
      private_class_method :decode_optional_string

      # Decodes optional bytes from +data+ at +pos+.
      # Returns [bytes_or_nil, new_pos].
      def decode_optional_bytes(data, pos)
        len, consumed = BSV::Transaction::VarInt.decode(data, pos)
        pos += consumed
        return [nil, pos] if len == ABSENT

        bytes = data.byteslice(pos, len)
        [bytes, pos + len]
      end
      private_class_method :decode_optional_bytes

      # Resolves the effective request body, applying the default body rules for
      # methods that typically carry a body (POST, PUT, PATCH, DELETE):
      # - If body is nil and content-type includes 'application/json', default to '{}'
      # - If body is nil and method carries a body but content-type is not JSON, default to ''
      # - Otherwise keep body as-is (including explicit nil for GET etc.)
      def resolve_body(method:, headers:, body:)
        return body unless body.nil?
        return body unless METHODS_WITH_BODY.include?(method.upcase)

        content_type = headers.find { |k, _| k == 'content-type' }
        content_type_value = content_type ? content_type[1] : ''

        if content_type_value.include?('application/json')
          '{}'
        else
          ''
        end
      end
      private_class_method :resolve_body
    end
  end
end
