# frozen_string_literal: true

require 'json'

module BSV
  module X402
    # Minimal RFC 8785 (JSON Canonicalisation Scheme) encoder.
    #
    # x402 challenge and proof objects contain only integers, booleans, strings,
    # and nested hashes — no floats, no arrays at the top level. This
    # implementation covers precisely those types. If a future spec version
    # introduces floats, this must be revisited.
    #
    # Produces byte-for-byte identical output to any compliant RFC 8785
    # implementation for the same input, provided the input contains only the
    # supported types.
    module CanonicalJSON
      # Encodes +value+ to a canonical JSON string per RFC 8785.
      #
      # Keys of all hashes are sorted in ascending byte order at every nesting
      # level. Integers are emitted without decimal points. Strings are UTF-8
      # with minimal JSON escaping. Booleans and nil are emitted as their JSON
      # literals.
      #
      # @param value [Hash, Integer, String, TrueClass, FalseClass, NilClass]
      # @return [String] canonical JSON string (UTF-8, no trailing newline)
      def self.encode(value)
        case value
        when Hash       then encode_hash(value)
        when Integer    then value.to_s
        when String     then encode_string(value)
        when TrueClass  then 'true'
        when FalseClass then 'false'
        when NilClass   then 'null'
        else
          raise EncodingError, "unsupported type for canonical JSON: #{value.class}"
        end
      end

      # ------------------------------------------------------------------
      # Private helpers
      # ------------------------------------------------------------------

      def self.encode_hash(hash)
        # Normalise keys to strings so string and symbol keys sort identically.
        normalised = hash.each_with_object({}) do |(k, v), acc|
          acc[k.to_s] = v
        end

        pairs = normalised.keys
                          .sort
                          .map { |k| "#{encode_string(k)}:#{encode(normalised[k])}" }
        "{#{pairs.join(',')}}"
      end
      private_class_method :encode_hash

      # Produces a JSON-safe quoted string. Ruby's JSON library handles all
      # required escape sequences (control characters, \", \\) correctly.
      def self.encode_string(str)
        JSON.generate(str)
      end
      private_class_method :encode_string
    end
  end
end
