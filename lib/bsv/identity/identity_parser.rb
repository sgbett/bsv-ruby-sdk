# frozen_string_literal: true

module BSV
  module Identity
    # Parses an {IdentityCertificate} into a {DisplayableIdentity} suitable for
    # presentation in a user interface.
    #
    # Handles all 9 well-known certificate types (xCert, discordCert, phoneCert,
    # emailCert, identiCert, registrant, coolCert, anyone, self) with type-specific
    # field extraction that matches the TS SDK implementation exactly. Unknown
    # certificate types fall through to a generic field-name heuristic.
    module IdentityParser
      # Well-known avatar opaque strings used by specific certificate types.
      EMAIL_AVATAR  = 'XUTZxep7BBghAJbSBwTjNfmcsDdRFs5EaGEgkESGSgjJVYgMEizu'
      PHONE_AVATAR  = 'XUTLxtX3ELNUwRhLwL7kWNGbdnFM8WG2eSLv84J7654oH8HaJWrU'
      ANYONE_AVATAR = 'XUT4bpQ6cpBaXi1oMzZsXfpkWGbtp2JTUYAoN7PzhStFJ6wLfoeR'
      SELF_AVATAR   = 'XUT9jHGk2qace148jeCX5rDsMftkSGYKmigLwU2PLLBc7Hm63VYR'
      BADGE_ICON    = 'XUUV39HVPkpmMzYNTx7rpKzJvXfeiVyQWg2vfSpjBAuhunTCA9uG'

      # Parses an {IdentityCertificate} and returns a {DisplayableIdentity}.
      #
      # @param identity_certificate [IdentityCertificate]
      # @return [DisplayableIdentity]
      def self.parse(identity_certificate)
        fields       = identity_certificate.decrypted_fields
        certifier    = identity_certificate.certifier_info
        type_b64     = identity_certificate.certificate[:type]

        name, avatar_url, badge_label, badge_icon_url, badge_click_url =
          extract_fields(type_b64, fields, certifier)

        subject       = identity_certificate.certificate[:subject].to_s
        identity_key  = subject
        abbreviated   = abbreviated_key(subject)

        DisplayableIdentity.new(
          name: name,
          avatar_url: avatar_url,
          abbreviated_key: abbreviated,
          identity_key: identity_key,
          badge_icon_url: badge_icon_url,
          badge_label: badge_label,
          badge_click_url: badge_click_url
        )
      end

      # -----------------------------------------------------------------------
      # Private helpers
      # -----------------------------------------------------------------------

      # Returns true when +val+ is a non-nil, non-empty string.
      def self.present?(val)
        val.is_a?(String) && !val.empty?
      end
      private_class_method :present?

      # Returns the first 10 characters of the subject followed by '...',
      # or the subject itself when it is shorter than 10 characters.
      def self.abbreviated_key(subject)
        return '' unless present?(subject)
        return subject if subject.length < 10

        "#{subject[0, 10]}..."
      end
      private_class_method :abbreviated_key

      # Dispatches to per-type extraction logic and returns a 5-element array:
      # [name, avatar_url, badge_label, badge_icon_url, badge_click_url]
      def self.extract_fields(type_b64, fields, certifier)
        types = Constants::KNOWN_IDENTITY_TYPES

        case type_b64
        when types[:x_cert]       then parse_x_cert(fields, certifier)
        when types[:discord_cert] then parse_discord_cert(fields, certifier)
        when types[:email_cert]   then parse_email_cert(fields, certifier)
        when types[:phone_cert]   then parse_phone_cert(fields, certifier)
        when types[:identi_cert]  then parse_identi_cert(fields, certifier)
        when types[:registrant]   then parse_registrant(fields, certifier)
        when types[:cool_cert]    then parse_cool_cert(fields)
        when types[:anyone]       then parse_anyone
        when types[:self]         then parse_self
        else                           parse_generic(type_b64, fields, certifier)
        end
      end
      private_class_method :extract_fields

      # -- Known-type parsers --------------------------------------------------

      def self.parse_x_cert(fields, certifier)
        name          = fields['userName']
        avatar_url    = fields['profilePhoto']
        badge_label   = "X account certified by #{certifier&.name}"
        badge_icon    = certifier&.icon_url
        badge_click   = 'https://socialcert.net'
        [name, avatar_url, badge_label, badge_icon, badge_click]
      end
      private_class_method :parse_x_cert

      def self.parse_discord_cert(fields, certifier)
        name          = fields['userName']
        avatar_url    = fields['profilePhoto']
        badge_label   = "Discord account certified by #{certifier&.name}"
        badge_icon    = certifier&.icon_url
        badge_click   = 'https://socialcert.net'
        [name, avatar_url, badge_label, badge_icon, badge_click]
      end
      private_class_method :parse_discord_cert

      def self.parse_email_cert(fields, certifier)
        name        = fields['email']
        avatar_url  = EMAIL_AVATAR
        badge_label = "Email certified by #{certifier&.name}"
        badge_icon  = certifier&.icon_url
        badge_click = 'https://socialcert.net'
        [name, avatar_url, badge_label, badge_icon, badge_click]
      end
      private_class_method :parse_email_cert

      def self.parse_phone_cert(fields, certifier)
        name        = fields['phoneNumber']
        avatar_url  = PHONE_AVATAR
        badge_label = "Phone certified by #{certifier&.name}"
        badge_icon  = certifier&.icon_url
        badge_click = 'https://socialcert.net'
        [name, avatar_url, badge_label, badge_icon, badge_click]
      end
      private_class_method :parse_phone_cert

      def self.parse_identi_cert(fields, certifier)
        name        = "#{fields['firstName']} #{fields['lastName']}"
        avatar_url  = fields['profilePhoto']
        badge_label = "Government ID certified by #{certifier&.name}"
        badge_icon  = certifier&.icon_url
        badge_click = 'https://identicert.me'
        [name, avatar_url, badge_label, badge_icon, badge_click]
      end
      private_class_method :parse_identi_cert

      def self.parse_registrant(fields, certifier)
        name        = fields['name']
        avatar_url  = fields['icon']
        badge_label = "Entity certified by #{certifier&.name}"
        badge_icon  = certifier&.icon_url
        badge_click = 'https://projectbabbage.com/docs/registrant'
        [name, avatar_url, badge_label, badge_icon, badge_click]
      end
      private_class_method :parse_registrant

      def self.parse_cool_cert(fields)
        name = fields['cool'] == 'true' ? 'Cool Person!' : 'Not cool!'
        [name, nil, nil, nil, nil]
      end
      private_class_method :parse_cool_cert

      def self.parse_anyone
        [
          'Anyone',
          ANYONE_AVATAR,
          'Represents the ability for anyone to access this information.',
          BADGE_ICON,
          'https://projectbabbage.com/docs/anyone-identity'
        ]
      end
      private_class_method :parse_anyone

      def self.parse_self
        [
          'You',
          SELF_AVATAR,
          'Represents your ability to access this information.',
          BADGE_ICON,
          'https://projectbabbage.com/docs/self-identity'
        ]
      end
      private_class_method :parse_self

      # -- Generic fallback ---------------------------------------------------

      # Attempts to extract identity fields from an unknown certificate type by
      # checking commonly used field names in order of preference.
      def self.parse_generic(type_b64, fields, certifier)
        default = Constants::DEFAULT_IDENTITY

        name      = resolve_generic_name(fields, default)
        avatar    = resolve_generic_avatar(fields, default)
        b_label   = resolve_generic_badge_label(type_b64, certifier, default)
        b_icon    = present?(certifier&.icon_url) ? certifier.icon_url : default.badge_icon_url
        b_click   = default.badge_click_url

        [name, avatar, b_label, b_icon, b_click]
      end
      private_class_method :parse_generic

      def self.resolve_generic_name(fields, default)
        return fields['name']     if present?(fields['name'])
        return fields['userName'] if present?(fields['userName'])

        full_name = compose_full_name(fields)
        return full_name if present?(full_name)

        return fields['email'] if present?(fields['email'])

        default.name
      end
      private_class_method :resolve_generic_name

      def self.compose_full_name(fields)
        first = fields['firstName']
        last  = fields['lastName']

        if present?(first) && present?(last)
          "#{first} #{last}"
        elsif present?(first)
          first
        elsif present?(last)
          last
        end
      end
      private_class_method :compose_full_name

      def self.resolve_generic_avatar(fields, default)
        return fields['profilePhoto'] if present?(fields['profilePhoto'])
        return fields['avatar']       if present?(fields['avatar'])
        return fields['icon']         if present?(fields['icon'])
        return fields['photo']        if present?(fields['photo'])

        default.avatar_url
      end
      private_class_method :resolve_generic_avatar

      def self.resolve_generic_badge_label(type_b64, certifier, default)
        return "#{type_b64} certified by #{certifier.name}" if present?(certifier&.name)

        default.badge_label
      end
      private_class_method :resolve_generic_badge_label
    end
  end
end
