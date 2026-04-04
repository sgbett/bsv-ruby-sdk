# frozen_string_literal: true

module BSV
  module Identity
    # Formatted identity information for display in user interfaces.
    class DisplayableIdentity
      # @return [String] human-readable display name
      attr_reader :name

      # @return [String] URL or opaque string for the identity avatar image
      attr_reader :avatar_url

      # @return [String] shortened version of the identity key for compact display
      attr_reader :abbreviated_key

      # @return [String] full identity public key
      attr_reader :identity_key

      # @return [String, nil] URL or opaque string for a trust badge icon
      attr_reader :badge_icon_url

      # @return [String, nil] human-readable badge label (e.g. certifier name)
      attr_reader :badge_label

      # @return [String, nil] URL to open when the badge is clicked
      attr_reader :badge_click_url

      # @param name [String]
      # @param avatar_url [String]
      # @param abbreviated_key [String]
      # @param identity_key [String]
      # @param badge_icon_url [String, nil]
      # @param badge_label [String, nil]
      # @param badge_click_url [String, nil]
      def initialize(name:, avatar_url:, abbreviated_key:, identity_key:,
                     badge_icon_url: nil, badge_label: nil, badge_click_url: nil)
        @name            = name
        @avatar_url      = avatar_url
        @abbreviated_key = abbreviated_key
        @identity_key    = identity_key
        @badge_icon_url  = badge_icon_url
        @badge_label     = badge_label
        @badge_click_url = badge_click_url
      end
    end

    # Certifier metadata attached to a certificate for display purposes.
    class CertifierInfo
      # @return [String] certifier's display name
      attr_reader :name

      # @return [String, nil] URL or opaque string for the certifier's icon
      attr_reader :icon_url

      # @param name [String]
      # @param icon_url [String, nil]
      def initialize(name:, icon_url: nil)
        @name     = name
        @icon_url = icon_url
      end
    end

    # A certificate together with its decrypted field values and optional certifier info.
    class IdentityCertificate
      # @return [Hash] raw certificate data (type, subject, fields, etc.)
      attr_reader :certificate

      # @return [Hash] certificate field values after decryption
      attr_reader :decrypted_fields

      # @return [CertifierInfo, nil] display information about the certifier
      attr_reader :certifier_info

      # @param certificate [Hash]
      # @param decrypted_fields [Hash]
      # @param certifier_info [CertifierInfo, nil]
      def initialize(certificate:, decrypted_fields:, certifier_info: nil)
        @certificate      = certificate
        @decrypted_fields = decrypted_fields
        @certifier_info   = certifier_info
      end
    end

    # Configuration options for an IdentityClient instance.
    class ClientOptions
      # @return [Array] BRC-42/43 wallet protocol identifier, e.g. [1, 'identity']
      attr_reader :protocol_id

      # @return [String] key identifier within the protocol
      attr_reader :key_id

      # @return [Integer] token amount in satoshis for identity operations
      attr_reader :token_amount

      # @return [Integer] output index within the token transaction
      attr_reader :output_index

      # @param protocol_id [Array]
      # @param key_id [String]
      # @param token_amount [Integer]
      # @param output_index [Integer]
      def initialize(protocol_id:, key_id:, token_amount:, output_index:)
        @protocol_id  = protocol_id
        @key_id       = key_id
        @token_amount = token_amount
        @output_index = output_index
      end
    end
  end
end
