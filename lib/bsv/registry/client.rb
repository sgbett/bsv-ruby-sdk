# frozen_string_literal: true

require 'json'

module BSV
  module Registry
    # Client for managing on-chain registry definitions for protocols, baskets,
    # and certificate types on the BSV overlay network.
    #
    # Registry operators use this client to establish canonical references for
    # basket IDs, protocol specifications, and certificate schemas via
    # PushDrop-based UTXOs.
    #
    # All overlay dependencies (broadcaster, resolver) are injectable for testing.
    #
    # @example Register a new basket definition
    #   client = BSV::Registry::Client.new(wallet: my_wallet)
    #   data   = BSV::Registry::BasketDefinitionData.new(
    #     basket_id:         'my-basket',
    #     name:              'My Basket',
    #     icon_url:          'https://example.com/icon.png',
    #     description:       'Stores my tokens',
    #     documentation_url: 'https://example.com/docs'
    #   )
    #   result = client.register_definition(BSV::Registry::DefinitionType::BASKET, data)
    #
    # @example Resolve basket definitions
    #   records = client.resolve(BSV::Registry::DefinitionType::BASKET, { basket_id: 'my-basket' })
    class Client
      # @param wallet [#get_public_key, #get_network, #create_action, #sign_action,
      #   #list_outputs] BRC-100 wallet interface
      # @param originator [String, nil] optional FQDN of the originating application
      # @param broadcaster [BSV::Overlay::TopicBroadcaster, nil] injectable broadcaster;
      #   built from the wallet's network preset when nil
      # @param resolver [BSV::Overlay::LookupResolver, nil] injectable lookup resolver;
      #   built from the wallet's network preset when nil
      def initialize(wallet:, originator: nil, broadcaster: nil, resolver: nil)
        @wallet     = wallet
        @originator = originator
        @broadcaster = broadcaster
        @resolver    = resolver
      end

      # Publishes a new on-chain definition for baskets, protocols, or certificates.
      #
      # The definition data is encoded in a PushDrop-based UTXO and broadcast
      # to the appropriate overlay topic for the given definition type.
      #
      # @param definition_type [String] one of {DefinitionType} constants
      # @param data [BasketDefinitionData, ProtocolDefinitionData, CertificateDefinitionData]
      #   structured definition data
      # @return [BSV::Overlay::OverlayBroadcastResult]
      # @raise [RuntimeError] if the transaction cannot be created or broadcast
      def register_definition(definition_type, data)
        registry_operator = identity_key
        fields = build_pushdrop_fields(definition_type, data, registry_operator)

        protocol_id = protocol_for(definition_type)
        template = BSV::Script::PushDropTemplate.new(wallet: @wallet, originator: @originator)
        locking_script = template.lock(
          fields: fields,
          protocol_id: protocol_id,
          key_id: Constants::KEY_ID,
          counterparty: 'anyone'
        )

        basket_name = basket_name_for(definition_type)
        create_result = @wallet.create_action(
          {
            description: "Register a new #{definition_type} definition",
            outputs: [
              {
                satoshis: Constants::TOKEN_AMOUNT,
                locking_script: locking_script.to_hex,
                output_description: "New #{definition_type} registration token",
                basket: basket_name
              }
            ],
            options: { randomize_outputs: false }
          },
          originator: @originator
        )

        raise "Register failed: could not create #{definition_type} registration transaction" if create_result[:tx].nil?

        tx = BSV::Transaction::Transaction.from_beef(create_result[:tx])
        broadcaster_for(definition_type).broadcast(tx)
      end

      # Resolves registry definitions of a given type using the overlay lookup service.
      #
      # @param definition_type [String] one of {DefinitionType} constants
      # @param query [Hash] filter criteria; keys depend on definition type:
      #   - basket: basket_id, name, registry_operators
      #   - protocol: name, protocol_id, registry_operators
      #   - certificate: type, name, registry_operators
      # @return [Array<RegisteredDefinition>] matching registered definitions
      def resolve(definition_type, query)
        service = service_for(definition_type)
        question = BSV::Overlay::LookupQuestion.new(
          service: service,
          query: query
        )
        answer = resolver_for.query(question)

        return [] unless answer.type == 'output-list'

        answer.outputs.filter_map do |output|
          parse_output_to_registered_definition(definition_type, output)
        rescue StandardError
          nil
        end
      end

      # Lists the registry operator's own published definitions for the given type.
      #
      # Queries the wallet for spendable outputs in the appropriate basket,
      # then parses the PushDrop scripts back into structured definition data.
      #
      # @param definition_type [String] one of {DefinitionType} constants
      # @return [Array<RegisteredDefinition>] the operator's own registered definitions
      def list_own_registry_entries(definition_type)
        basket_name = basket_name_for(definition_type)
        list_result = @wallet.list_outputs(
          { basket: basket_name, include: 'entire transactions' },
          originator: @originator
        )

        outputs  = list_result[:outputs] || list_result['outputs'] || []
        beef_raw = list_result[:beef] || list_result['beef'] || list_result[:BEEF] || list_result['BEEF']

        return [] if beef_raw.nil? || outputs.empty?

        beef = BSV::Transaction::Beef.from_binary(beef_raw)

        outputs.filter_map do |output|
          next unless spendable?(output)

          begin
            parse_own_output_to_registered_definition(definition_type, output, beef, beef_raw)
          rescue StandardError
            nil
          end
        end
      end

      # Revokes an existing registry definition by spending its UTXO.
      #
      # Verifies that the definition belongs to the current wallet before spending.
      #
      # @param registered_definition [RegisteredDefinition] the definition to revoke
      # @return [BSV::Overlay::OverlayBroadcastResult]
      # @raise [RuntimeError] if the definition does not belong to this wallet or
      #   the transaction cannot be created
      def revoke_definition(registered_definition)
        verify_ownership(registered_definition)

        definition_type = registered_definition.definition_type
        outpoint = "#{registered_definition.txid}.#{registered_definition.output_index}"

        create_result = @wallet.create_action(
          {
            description: "Revoke #{definition_type} definition: #{item_identifier(registered_definition)}",
            input_beef: registered_definition.beef,
            inputs: [
              {
                outpoint: outpoint,
                unlocking_script_length: BSV::Script::PushDropTemplate::Unlocker::ESTIMATED_LENGTH,
                input_description: "Revoking #{definition_type} token"
              }
            ],
            options: { randomize_outputs: false, no_send: true }
          },
          originator: @originator
        )

        raise 'Revoke failed: could not create signable transaction' if create_result[:signable_transaction].nil?

        sign_and_broadcast(definition_type, registered_definition, create_result)
      end

      # Updates an existing registry definition by revoking it and registering new data.
      #
      # The update is performed as two sequential operations: revoke then register.
      # This is not atomic — if registration fails after revocation, the definition
      # will have been removed without replacement.
      #
      # @param registered_definition [RegisteredDefinition] the existing definition to replace
      # @param new_data [BasketDefinitionData, ProtocolDefinitionData, CertificateDefinitionData]
      #   new definition data (must be same type as the existing definition)
      # @return [BSV::Overlay::OverlayBroadcastResult] result of the registration broadcast
      # @raise [ArgumentError] if the definition types do not match
      # @raise [RuntimeError] if revocation or registration fails
      def update_definition(registered_definition, new_data)
        unless registered_definition.definition_type == new_data.definition_type
          raise ArgumentError,
                "Cannot change definition type from #{registered_definition.definition_type} to #{new_data.definition_type}"
        end

        revoke_definition(registered_definition)
        register_definition(registered_definition.definition_type, new_data)
      end

      private

      # Returns the cached identity public key, fetching it on first call.
      #
      # @return [String] compressed public key hex
      def identity_key
        return @identity_key if defined?(@identity_key)

        result = @wallet.get_public_key({ identity_key: true }, originator: @originator)
        @identity_key = result[:public_key] || result['public_key'] || result['publicKey'] || result[:publicKey]
      end

      # Returns the overlay topic name for a given definition type.
      #
      # @param definition_type [String]
      # @return [String]
      def topic_for(definition_type)
        case definition_type
        when DefinitionType::BASKET      then Constants::TOPIC_BASKET
        when DefinitionType::PROTOCOL    then Constants::TOPIC_PROTOCOL
        when DefinitionType::CERTIFICATE then Constants::TOPIC_CERTIFICATE
        else raise ArgumentError, "Unknown definition type: #{definition_type}"
        end
      end

      # Returns the lookup service name for a given definition type.
      #
      # @param definition_type [String]
      # @return [String]
      def service_for(definition_type)
        case definition_type
        when DefinitionType::BASKET      then Constants::SERVICE_BASKET
        when DefinitionType::PROTOCOL    then Constants::SERVICE_PROTOCOL
        when DefinitionType::CERTIFICATE then Constants::SERVICE_CERTIFICATE
        else raise ArgumentError, "Unknown definition type: #{definition_type}"
        end
      end

      # Returns the BRC-43 protocol ID for a given definition type.
      #
      # @param definition_type [String]
      # @return [Array]
      def protocol_for(definition_type)
        case definition_type
        when DefinitionType::BASKET      then Constants::PROTOCOL_BASKET
        when DefinitionType::PROTOCOL    then Constants::PROTOCOL_PROTOCOL
        when DefinitionType::CERTIFICATE then Constants::PROTOCOL_CERTIFICATE
        else raise ArgumentError, "Unknown definition type: #{definition_type}"
        end
      end

      # Returns the wallet basket name for a given definition type.
      #
      # @param definition_type [String]
      # @return [String]
      def basket_name_for(definition_type)
        case definition_type
        when DefinitionType::BASKET      then Constants::BASKET_NAME_BASKET
        when DefinitionType::PROTOCOL    then Constants::BASKET_NAME_PROTOCOL
        when DefinitionType::CERTIFICATE then Constants::BASKET_NAME_CERTIFICATE
        else raise ArgumentError, "Unknown definition type: #{definition_type}"
        end
      end

      # Builds an ordered array of binary fields for a PushDrop script.
      #
      # Field ordering per reference SDK:
      # - basket:      basket_id, name, icon_url, description, documentation_url, registry_operator
      # - protocol:    protocol_id (JSON), name, icon_url, description, documentation_url, registry_operator
      # - certificate: type, name, icon_url, description, documentation_url, fields (JSON), registry_operator
      #
      # @param definition_type [String]
      # @param data [BasketDefinitionData, ProtocolDefinitionData, CertificateDefinitionData]
      # @param registry_operator [String] public key hex
      # @return [Array<String>] binary field strings
      def build_pushdrop_fields(definition_type, data, registry_operator)
        string_fields = case definition_type
                        when DefinitionType::BASKET
                          [
                            data.basket_id,
                            data.name,
                            data.icon_url,
                            data.description,
                            data.documentation_url
                          ]
                        when DefinitionType::PROTOCOL
                          [
                            JSON.generate(data.protocol_id),
                            data.name,
                            data.icon_url,
                            data.description,
                            data.documentation_url
                          ]
                        when DefinitionType::CERTIFICATE
                          fields_hash = data.fields.transform_values do |v|
                            v.respond_to?(:to_h) ? v.to_h : v
                          end
                          [
                            data.type,
                            data.name,
                            data.icon_url,
                            data.description,
                            data.documentation_url,
                            JSON.generate(fields_hash)
                          ]
                        else
                          raise ArgumentError, "Unknown definition type: #{definition_type}"
                        end

        string_fields << registry_operator
        string_fields.map(&:b)
      end

      # Parses a PushDrop locking script into a definition data object.
      #
      # {Script#pushdrop_fields} returns ALL pushed fields before the DROP opcodes,
      # which includes the ECDSA signature appended by {PushDropTemplate#lock} when
      # +include_signature: true+ (the default). The signature is always the last
      # field, so we drop it before interpreting the data fields.
      #
      # Expected total field counts (data + operator + signature):
      # - basket:      5 + 1 + 1 = 7
      # - protocol:    5 + 1 + 1 = 7
      # - certificate: 6 + 1 + 1 = 8
      #
      # @param definition_type [String]
      # @param script [BSV::Script::Script]
      # @return [BasketDefinitionData, ProtocolDefinitionData, CertificateDefinitionData]
      # @raise [RuntimeError] if the script is not a valid registry PushDrop
      def parse_locking_script(definition_type, script)
        all_fields = script.pushdrop_fields
        raise 'Not a valid registry PushDrop script' if all_fields.nil? || all_fields.empty?

        # Drop the trailing signature field; the remaining fields are data + operator.
        fields = all_fields[0..-2].map { |f| f.force_encoding('UTF-8') }

        case definition_type
        when DefinitionType::BASKET
          raise "Unexpected field count for basket (got #{fields.length}, expected 6)" unless fields.length == 6

          BasketDefinitionData.new(
            basket_id: fields[0],
            name: fields[1],
            icon_url: fields[2],
            description: fields[3],
            documentation_url: fields[4],
            registry_operator: fields[5]
          )

        when DefinitionType::PROTOCOL
          raise "Unexpected field count for protocol (got #{fields.length}, expected 6)" unless fields.length == 6

          protocol_id = JSON.parse(fields[0])
          ProtocolDefinitionData.new(
            protocol_id: protocol_id,
            name: fields[1],
            icon_url: fields[2],
            description: fields[3],
            documentation_url: fields[4],
            registry_operator: fields[5]
          )

        when DefinitionType::CERTIFICATE
          raise "Unexpected field count for certificate (got #{fields.length}, expected 7)" unless fields.length == 7

          raw_cert_fields = begin
            JSON.parse(fields[5])
          rescue JSON::ParserError
            {}
          end
          cer_fields = raw_cert_fields.transform_values do |v|
            next v unless v.is_a?(Hash)

            CertificateFieldDescriptor.new(
              friendly_name: v['friendlyName'] || '',
              description: v['description'] || '',
              type: v['type'] || 'text',
              field_icon: v['fieldIcon'] || ''
            )
          end

          CertificateDefinitionData.new(
            type: fields[0],
            name: fields[1],
            icon_url: fields[2],
            description: fields[3],
            documentation_url: fields[4],
            fields: cer_fields,
            registry_operator: fields[6]
          )

        else
          raise ArgumentError, "Unknown definition type: #{definition_type}"
        end
      end

      # Parses a single overlay output into a RegisteredDefinition, or returns nil.
      #
      # @param definition_type [String]
      # @param output [Hash] overlay output with :beef and :outputIndex keys
      # @return [RegisteredDefinition, nil]
      def parse_output_to_registered_definition(definition_type, output)
        beef_raw   = output['beef'] || output[:beef]
        output_idx = (output['outputIndex'] || output[:output_index]).to_i

        beef = BSV::Transaction::Beef.from_binary(beef_raw)
        tx   = beef.transactions.last&.transaction
        return nil unless tx

        locking_script = tx.outputs[output_idx]&.locking_script
        return nil unless locking_script

        definition_data = parse_locking_script(definition_type, locking_script)

        RegisteredDefinition.new(
          definition_data: definition_data,
          txid: tx.txid_hex,
          output_index: output_idx,
          locking_script: locking_script.to_hex,
          beef: beef_raw,
          satoshis: tx.outputs[output_idx].satoshis
        )
      end

      # Parses a wallet list_outputs entry into a RegisteredDefinition.
      #
      # @param definition_type [String]
      # @param output [Hash] wallet output with :outpoint, :satoshis keys
      # @param beef [BSV::Transaction::Beef] parsed BEEF
      # @param beef_raw [String] raw BEEF bytes
      # @return [RegisteredDefinition, nil]
      def parse_own_output_to_registered_definition(definition_type, output, beef, beef_raw)
        outpoint_str = output[:outpoint] || output['outpoint']
        return nil unless outpoint_str

        txid, output_idx_str = outpoint_str.split('.')
        output_idx = output_idx_str.to_i

        tx = beef.transactions.last&.transaction
        return nil unless tx

        locking_script = tx.outputs[output_idx]&.locking_script
        return nil unless locking_script

        definition_data = parse_locking_script(definition_type, locking_script)
        satoshis = output[:satoshis] || output['satoshis'] || Constants::TOKEN_AMOUNT

        RegisteredDefinition.new(
          definition_data: definition_data,
          txid: txid,
          output_index: output_idx,
          locking_script: locking_script.to_hex,
          beef: beef_raw,
          satoshis: satoshis
        )
      end

      # Signs and broadcasts a signable transaction for a revocation or update.
      #
      # @param definition_type [String]
      # @param registered_definition [RegisteredDefinition]
      # @param create_result [Hash] result from wallet.create_action containing :signable_transaction
      # @return [BSV::Overlay::OverlayBroadcastResult]
      def sign_and_broadcast(definition_type, _registered_definition, create_result)
        signable   = create_result[:signable_transaction]
        partial_tx = BSV::Transaction::Transaction.from_beef(signable[:tx])

        template = BSV::Script::PushDropTemplate.new(wallet: @wallet, originator: @originator)
        unlocker = template.unlock(
          protocol_id: protocol_for(definition_type),
          key_id: Constants::KEY_ID,
          counterparty: 'anyone'
        )

        spending_input_idx = 0
        unlocking_script = unlocker.sign(partial_tx, spending_input_idx)

        sign_result = @wallet.sign_action(
          {
            reference: signable[:reference],
            spends: { spending_input_idx => { unlocking_script: unlocking_script.to_hex } },
            options: { no_send: true }
          },
          originator: @originator
        )

        raise 'Revoke failed: could not sign transaction' if sign_result[:tx].nil?

        signed_tx = BSV::Transaction::Transaction.from_beef(sign_result[:tx])
        broadcaster_for(definition_type).broadcast(signed_tx)
      end

      # Verifies that the registered definition belongs to the current wallet.
      #
      # @param registered_definition [RegisteredDefinition]
      # @raise [RuntimeError] if the definition does not belong to this wallet
      def verify_ownership(registered_definition)
        operator = registered_definition.definition_data.registry_operator
        current  = identity_key
        return if operator == current

        raise 'Registry token does not belong to the current wallet ' \
              "(operator: #{operator}, current: #{current})"
      end

      # Returns a human-readable identifier for a registered definition.
      #
      # @param registered_definition [RegisteredDefinition]
      # @return [String]
      def item_identifier(registered_definition)
        data = registered_definition.definition_data
        case data.definition_type
        when DefinitionType::BASKET      then data.basket_id
        when DefinitionType::PROTOCOL    then data.name
        when DefinitionType::CERTIFICATE then data.name.empty? ? data.type : data.name
        else 'unknown'
        end
      end

      # Returns whether an output from wallet.list_outputs is spendable.
      #
      # @param output [Hash]
      # @return [Boolean]
      def spendable?(output)
        # Use key? rather than || to avoid false || nil collapsing to nil.
        val = output.key?(:spendable) ? output[:spendable] : output['spendable']
        val.nil? || val
      end

      # Returns the broadcaster to use, building one from the wallet's network
      # when no injectable broadcaster was provided.
      #
      # @param definition_type [String]
      # @return [BSV::Overlay::TopicBroadcaster]
      def broadcaster_for(definition_type)
        return @broadcaster if @broadcaster

        network = wallet_network
        BSV::Overlay::TopicBroadcaster.new(
          [topic_for(definition_type)],
          network_preset: network
        )
      end

      # Returns the lookup resolver, building one from the wallet's network
      # when no injectable resolver was provided.
      #
      # @return [BSV::Overlay::LookupResolver]
      def resolver_for
        return @resolver if @resolver

        network = wallet_network
        BSV::Overlay::LookupResolver.new(network_preset: network)
      end

      # Queries the wallet for the current network and converts the string to a symbol.
      #
      # @return [Symbol] :mainnet or :testnet
      def wallet_network
        result  = @wallet.get_network({}, originator: @originator)
        net_str = result[:network] || result['network'] || 'mainnet'
        net_str.to_sym
      end
    end
  end
end
