# frozen_string_literal: true

require 'json'

module BSV
  module KVStore
    # Historian interpreter for KVStore PushDrop tokens.
    #
    # Decodes a PushDrop locking script from the specified output, validates it
    # has the expected field count (5 old format / 6 new format), and filters by
    # +ctx[:key]+ and +ctx[:protocol_id]+.
    #
    # Returns the value as a UTF-8 string, or +nil+ for any non-match or error.
    # Never raises.
    #
    # Field layout (old format — 5 fields):
    #   [0] protocolID (JSON-encoded array)
    #   [1] key
    #   [2] value
    #   [3] controller
    #   [4] signature
    #
    # Field layout (new format — 6 fields):
    #   [0] protocolID (JSON-encoded array)
    #   [1] key
    #   [2] value
    #   [3] controller
    #   [4] tags
    #   [5] signature
    module Interpreter
      PROTOCOL_ID    = 0
      KEY            = 1
      VALUE          = 2
      CONTROLLER     = 3
      TAGS_NEW       = 4
      SIGNATURE_OLD  = 4
      SIGNATURE_NEW  = 5

      KV_PROTOCOL_FIELDS_OLD = 5
      KV_PROTOCOL_FIELDS_NEW = 6

      # Decode the KVStore token at +output_index+ in +tx+.
      #
      # Implements the Historian interpreter contract:
      # +interpreter.call(tx, output_index, ctx)+ → String or nil.
      #
      # @param tx [Transaction::Tx, nil] the transaction to inspect
      # @param output_index [Integer] index into +tx.outputs+
      # @param ctx [Hash, nil] must contain +:key+ (String) and +:protocol_id+ (Array)
      # @return [String, nil] the decoded UTF-8 value, or nil on any mismatch/error
      def self.call(tx, output_index, ctx)
        return nil if tx.nil?
        return nil if ctx.nil? || ctx[:key].nil?

        output = tx.outputs[output_index]
        return nil if output.nil?

        locking_script = output.locking_script
        return nil if locking_script.nil?

        return nil unless locking_script.pushdrop?

        fields = locking_script.pushdrop_fields
        return nil unless fields

        field_count = fields.length
        return nil unless [KV_PROTOCOL_FIELDS_OLD, KV_PROTOCOL_FIELDS_NEW].include?(field_count)

        protocol_id_bytes = fields[PROTOCOL_ID]
        return nil if protocol_id_bytes.nil?

        begin
          protocol_id_str = protocol_id_bytes.force_encoding(Encoding::UTF_8)
          return nil unless protocol_id_str.valid_encoding?

          parsed_protocol_id = JSON.parse(protocol_id_str)
          return nil unless parsed_protocol_id == ctx[:protocol_id]
        rescue JSON::ParserError
          return nil
        end

        key_bytes = fields[KEY]
        return nil if key_bytes.nil?

        begin
          key_str = key_bytes.force_encoding(Encoding::UTF_8)
          return nil unless key_str.valid_encoding?
          return nil unless key_str == ctx[:key]
        rescue StandardError
          return nil
        end

        begin
          value_bytes = fields[VALUE]
          return nil if value_bytes.nil?

          value_str = value_bytes.force_encoding(Encoding::UTF_8)
          return nil unless value_str.valid_encoding?

          value_str
        rescue StandardError
          nil
        end
      rescue StandardError
        nil
      end
    end
  end
end
