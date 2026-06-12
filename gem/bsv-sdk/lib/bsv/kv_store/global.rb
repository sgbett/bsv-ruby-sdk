# frozen_string_literal: true

require 'json'

module BSV
  module KVStore
    # Read-only client for the global KVStore overlay service.
    #
    # Queries the +ls_kvstore+ lookup service via a {BSV::Overlay::LookupResolver},
    # decodes PushDrop tokens (5-field legacy and 6-field current formats), verifies
    # the token signature, and returns typed {Entry} objects.
    #
    # Set/remove operations require wallet writes and are out of scope — those live
    # in the +bsv-wallet+ gem.
    #
    # == Selector requirement
    #
    # {#get} raises +ArgumentError+ unless at least one of +key+, +controller+,
    # +protocol_id+, or a non-empty +tags+ array is supplied in the query.
    #
    # == Always returns Array
    #
    # {#get} always returns +Array<Entry>+, even for single-result selectors such
    # as +key + controller+. Callers that expect at most one result should use
    # +.first+.
    #
    # == Silent skipping
    #
    # Outputs that fail BEEF parsing, PushDrop decoding, field-count validation, or
    # signature verification are silently skipped (matching the TS SDK contract).
    class Global
      # @param network_preset [Symbol] :mainnet, :testnet, or :local
      # @param lookup_resolver [BSV::Overlay::LookupResolver, nil] injectable resolver
      # @param service_name [String] lookup service identifier
      # @param proto_wallet [BSV::Wallet::ProtoWallet, nil] injectable wallet used for
      #   signature verification; defaults to +ProtoWallet.new('anyone')+. Tests can
      #   substitute a double to avoid +allow_any_instance_of+.
      def initialize(network_preset: :mainnet, lookup_resolver: nil, service_name: 'ls_kvstore', proto_wallet: nil)
        @lookup_resolver = lookup_resolver || BSV::Overlay::LookupResolver.new(network_preset: network_preset)
        @service_name = service_name
        @proto_wallet = proto_wallet || BSV::Wallet::ProtoWallet.new('anyone')
      end

      # Query the overlay for KVStore entries.
      #
      # @param query [Hash] selector: +:key+, +:controller+, +:protocol_id+, +:tags+,
      #   +:tag_query_mode+. At least one of the first four must be present.
      # @param include_token [Boolean] populate {Token} on each entry when true
      # @param history [Boolean] populate history via {BSV::Overlay::Historian} when true
      # @return [Array<Entry>] matching entries (empty array when nothing matches)
      # @raise [ArgumentError] if no selector is provided
      def get(query, include_token: false, history: false)
        validate_selector!(query)

        question = BSV::Overlay::LookupQuestion.new(
          service: @service_name,
          query: camelise(query)
        )

        answer = @lookup_resolver.query(question)
        return [] unless answer.type == 'output-list'

        answer.outputs.filter_map do |output|
          build_entry(output, include_token: include_token, history: history)
        rescue StandardError
          nil
        end
      end

      private

      # ---- Selector validation ----

      def validate_selector!(query)
        raise ArgumentError, 'query must be a Hash' unless query.is_a?(Hash)

        has_key        = query[:key].is_a?(String)        && !query[:key].empty?
        has_controller = query[:controller].is_a?(String) && !query[:controller].empty?
        has_protocol   = query[:protocol_id].is_a?(Array) && query[:protocol_id].length == 2
        has_tags       = query[:tags].is_a?(Array)        && !query[:tags].empty?

        return if has_key || has_controller || has_protocol || has_tags

        raise ArgumentError,
              'At least one selector required (key, controller, protocol_id, or non-empty tags)'
      end

      # ---- Entry construction ----

      def build_entry(output, include_token:, history:)
        beef_data    = output['beef'] || output[:beef]
        output_index = (output['outputIndex'] || output[:output_index] || 0).to_i
        raise 'Negative outputIndex' if output_index.negative?

        beef = parse_beef!(beef_data)
        beef_tx = beef.transactions.last
        raise 'No transaction in BEEF' if beef_tx.nil? || beef_tx.is_a?(BSV::Transaction::Beef::TxidOnlyEntry)

        tx     = beef_tx.transaction
        txout  = tx.outputs[output_index]
        raise 'outputIndex out of range' if txout.nil?

        locking_script = txout.locking_script
        raise 'No locking script' unless locking_script&.pushdrop?

        raw_fields = locking_script.pushdrop_fields
        raise 'Not a PushDrop script' unless raw_fields

        field_count = raw_fields.length
        raise "Unexpected field count: #{field_count}" unless [5, 6].include?(field_count)

        # Separate data fields from trailing signature field
        data_fields = raw_fields[0...-1]
        sig_bytes   = raw_fields.last

        # Decode common fields (indices match kvProtocol in TS SDK)
        protocol_id = decode_protocol_id!(data_fields[0])
        key         = decode_utf8!(data_fields[1])
        value       = decode_utf8!(data_fields[2])
        controller  = data_fields[3].unpack1('H*')

        # New format (6 fields) has tags at index 4; old format (5 fields) has no tags field
        tags = if field_count == 6
                 begin
                   JSON.parse(decode_utf8!(data_fields[4]))
                 rescue StandardError
                   nil
                 end
               end

        verify_signature!(data_fields, sig_bytes, protocol_id, key, controller)

        token = if include_token
                  Token.new(
                    dtxid: tx.dtxid_hex,
                    output_index: output_index,
                    beef: beef,
                    satoshis: txout.satoshis || 0
                  )
                end

        entry_history = if history
                          BSV::Overlay::Historian
                            .new(BSV::KVStore::Interpreter)
                            .build_history(tx, { key: key, protocol_id: protocol_id })
                        end

        Entry.new(
          key: key,
          value: value,
          controller: controller,
          protocol_id: protocol_id,
          tags: tags,
          token: token,
          history: entry_history
        )
      end

      # ---- Field decoding helpers ----

      def parse_beef!(beef_data)
        case beef_data
        when String
          BSV::Transaction::Beef.from_binary(beef_data)
        when Array
          BSV::Transaction::Beef.from_binary(beef_data.pack('C*'))
        else
          raise 'Missing or unsupported BEEF data'
        end
      end

      def decode_utf8!(bytes)
        raise 'Nil field' if bytes.nil?

        str = bytes.force_encoding(Encoding::UTF_8)
        raise 'Invalid UTF-8' unless str.valid_encoding?

        str
      end

      def decode_protocol_id!(bytes)
        JSON.parse(decode_utf8!(bytes))
      end

      # ---- Signature verification ----

      def verify_signature!(data_fields, sig_bytes, protocol_id, key, controller)
        @proto_wallet.verify_signature(
          data: data_fields.join.bytes,
          signature: sig_bytes.bytes,
          protocol_id: protocol_id,
          key_id: key,
          counterparty: controller
        )
      end

      # ---- Query key camelisation ----

      def camelise(query)
        query.transform_keys do |k|
          case k
          when :protocol_id    then :protocolID
          when :tag_query_mode then :tagQueryMode
          else k
          end
        end
      end
    end
  end
end
