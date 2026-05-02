# frozen_string_literal: true

module BSV
  module Registry
    # Enum-like module for the three supported registry definition types.
    module DefinitionType
      BASKET      = 'basket'
      PROTOCOL    = 'protocol'
      CERTIFICATE = 'certificate'

      ALL = [BASKET, PROTOCOL, CERTIFICATE].freeze
    end

    # Describes the structure and metadata for a single certificate field.
    #
    # Used within {CertificateDefinitionData} to document the shape of
    # each field in a certificate schema.
    class CertificateFieldDescriptor
      # @return [String] human-readable field name
      attr_reader :friendly_name

      # @return [String] description of the field's purpose
      attr_reader :description

      # @return [String] field type: 'text', 'imageURL', or 'other'
      attr_reader :type

      # @return [String] icon identifier for the field
      attr_reader :field_icon

      # @param friendly_name [String]
      # @param description [String]
      # @param type [String] 'text', 'imageURL', or 'other'
      # @param field_icon [String]
      def initialize(friendly_name:, description:, type:, field_icon:)
        @friendly_name = friendly_name
        @description   = description
        @type          = type
        @field_icon    = field_icon
      end

      # Serialise to a plain Hash for JSON encoding.
      #
      # @return [Hash]
      def to_h
        {
          'friendlyName' => @friendly_name,
          'description' => @description,
          'type' => @type,
          'fieldIcon' => @field_icon
        }
      end
    end

    # Registry data for a basket definition.
    class BasketDefinitionData
      # @return [String] always DefinitionType::BASKET
      attr_reader :definition_type

      # @return [String] unique basket identifier
      attr_reader :basket_id

      # @return [String] human-readable name
      attr_reader :name

      # @return [String] URL or opaque string for the basket icon
      attr_reader :icon_url

      # @return [String] description of the basket's purpose
      attr_reader :description

      # @return [String] URL to the basket documentation
      attr_reader :documentation_url

      # @return [String, nil] public key hex of the registry operator
      attr_reader :registry_operator

      # @param basket_id [String]
      # @param name [String]
      # @param icon_url [String]
      # @param description [String]
      # @param documentation_url [String]
      # @param registry_operator [String, nil]
      def initialize(basket_id:, name:, icon_url:, description:, documentation_url:,
                     registry_operator: nil)
        @definition_type   = DefinitionType::BASKET
        @basket_id         = basket_id
        @name              = name
        @icon_url          = icon_url
        @description       = description
        @documentation_url = documentation_url
        @registry_operator = registry_operator
      end
    end

    # Registry data for a protocol definition.
    class ProtocolDefinitionData
      # @return [String] always DefinitionType::PROTOCOL
      attr_reader :definition_type

      # @return [Array] two-element BRC-43 protocol ID, e.g. [1, 'protomap']
      attr_reader :protocol_id

      # @return [String] human-readable name
      attr_reader :name

      # @return [String] URL or opaque string for the protocol icon
      attr_reader :icon_url

      # @return [String] description of the protocol's purpose
      attr_reader :description

      # @return [String] URL to the protocol documentation
      attr_reader :documentation_url

      # @return [String, nil] public key hex of the registry operator
      attr_reader :registry_operator

      # @param protocol_id [Array] two-element [security_level, protocol_name]
      # @param name [String]
      # @param icon_url [String]
      # @param description [String]
      # @param documentation_url [String]
      # @param registry_operator [String, nil]
      def initialize(protocol_id:, name:, icon_url:, description:, documentation_url:,
                     registry_operator: nil)
        @definition_type   = DefinitionType::PROTOCOL
        @protocol_id       = protocol_id
        @name              = name
        @icon_url          = icon_url
        @description       = description
        @documentation_url = documentation_url
        @registry_operator = registry_operator
      end
    end

    # Registry data for a certificate type definition.
    class CertificateDefinitionData
      # @return [String] always DefinitionType::CERTIFICATE
      attr_reader :definition_type

      # @return [String] Base64-encoded certificate type identifier
      attr_reader :type

      # @return [String] human-readable name
      attr_reader :name

      # @return [String] URL or opaque string for the certificate type icon
      attr_reader :icon_url

      # @return [String] description of the certificate type's purpose
      attr_reader :description

      # @return [String] URL to the certificate type documentation
      attr_reader :documentation_url

      # @return [Hash<String, CertificateFieldDescriptor>] field schema descriptors
      attr_reader :fields

      # @return [String, nil] public key hex of the registry operator
      attr_reader :registry_operator

      # @param type [String]
      # @param name [String]
      # @param icon_url [String]
      # @param description [String]
      # @param documentation_url [String]
      # @param fields [Hash<String, CertificateFieldDescriptor>]
      # @param registry_operator [String, nil]
      def initialize(type:, name:, icon_url:, description:, documentation_url:,
                     fields: {}, registry_operator: nil)
        @definition_type   = DefinitionType::CERTIFICATE
        @type              = type
        @name              = name
        @icon_url          = icon_url
        @description       = description
        @documentation_url = documentation_url
        @fields            = fields
        @registry_operator = registry_operator
      end
    end

    # A parsed registry entry combining definition data with on-chain token data.
    #
    # Returned by {Client#resolve}, {Client#list_own_registry_entries}, and
    # similar methods that reconstruct registry records from locking scripts.
    class RegisteredDefinition
      # @return [String] the definition type (see {DefinitionType})
      attr_reader :definition_type

      # Registry API boundary: display-order hex txid from the outpoint string held in the registry token.
      # @return [String] transaction ID of the containing UTXO
      attr_reader :txid

      # @return [Integer] output index within the transaction
      attr_reader :output_index

      # @return [String] hex-encoded locking script of the UTXO
      attr_reader :locking_script

      # @return [String] raw BEEF bytes for the containing transaction
      attr_reader :beef

      # @return [Integer] satoshi value of the UTXO
      attr_reader :satoshis

      # @return [BasketDefinitionData, ProtocolDefinitionData, CertificateDefinitionData]
      #   the parsed definition data
      attr_reader :definition_data

      # @param definition_data [BasketDefinitionData, ProtocolDefinitionData, CertificateDefinitionData]
      # @param txid [String]
      # @param output_index [Integer]
      # @param locking_script [String]
      # @param beef [String]
      # @param satoshis [Integer]
      def initialize(definition_data:, txid:, output_index:, locking_script:, beef:, satoshis: 1)
        @definition_data = definition_data
        @definition_type = definition_data.definition_type
        BSV::Primitives::Hex.validate_dtxid_hex!(txid, name: 'registry definition txid')
        @txid            = txid
        @output_index    = output_index
        @locking_script  = locking_script
        @beef            = beef
        @satoshis        = satoshis
      end
    end
  end
end
