# frozen_string_literal: true

module BSV
  module Wallet
    module Validators
      # Reserved protocol name prefixes (BRC-44 and BRC-98).
      # Names beginning with any of these strings are disallowed.
      RESERVED_PROTOCOL_PREFIXES = ['admin', 'p '].freeze

      # Suffix that is disallowed on protocol names.
      RESERVED_PROTOCOL_SUFFIX = ' protocol'

      # Reserved basket name prefixes.
      # Basket names beginning with any of these strings are disallowed.
      RESERVED_BASKET_PREFIXES = ['admin', 'p '].freeze

      # Suffix that is disallowed on basket names.
      RESERVED_BASKET_SUFFIX = ' basket'

      # Basket name that is globally reserved and cannot be used.
      RESERVED_BASKET_NAME = 'default'

      module_function

      # BRC-100 protocol ID rules:
      # - Array of [security_level, protocol_name]
      # - security_level: Integer 0, 1, or 2
      # - protocol_name: 5-400 chars (up to 430 for 'specific linkage revelation' protocol)
      # - lowercase letters, numbers, and spaces only
      # - no consecutive spaces
      # - must not end with ' protocol'
      # - must not start with 'admin' (BRC-44)
      # - must not start with 'p ' (BRC-98 reserved)
      #
      # The name is normalised (stripped and downcased) before validation so
      # that ' MyProtocol ' and 'myprotocol' are treated identically and do not
      # silently fork to different key-derivation paths (F8.7).
      def validate_protocol_id!(protocol_id)
        unless protocol_id.is_a?(Array) && protocol_id.length == 2
          raise InvalidParameterError.new('protocol_id',
                                          'an Array of [security_level, protocol_name]')
        end

        level, name = protocol_id
        raise InvalidParameterError.new('protocol_id security level', '0, 1, or 2') unless [0, 1, 2].include?(level)
        raise InvalidParameterError.new('protocol_id name', 'a String') unless name.is_a?(String)

        name = name.strip.downcase

        max_length = name.start_with?('specific linkage revelation') ? 430 : 400
        raise InvalidParameterError.new('protocol_id name', "between 5 and #{max_length} characters") if name.length < 5 || name.length > max_length
        raise InvalidParameterError.new('protocol_id name', 'lowercase letters, numbers, and spaces only') unless name.match?(/\A[a-z0-9 ]+\z/)
        raise InvalidParameterError.new('protocol_id name', 'free of consecutive spaces') if name.include?('  ')
        if name.end_with?(RESERVED_PROTOCOL_SUFFIX)
          raise InvalidParameterError.new('protocol_id name', "not ending with \"#{RESERVED_PROTOCOL_SUFFIX}\"")
        end

        RESERVED_PROTOCOL_PREFIXES.each do |prefix|
          raise InvalidParameterError.new('protocol_id name', "not starting with \"#{prefix}\"") if name.start_with?(prefix)
        end
      end

      # Key ID: 1-800 bytes
      def validate_key_id!(key_id)
        raise InvalidParameterError.new('key_id', 'a String') unless key_id.is_a?(String)

        byte_length = key_id.bytesize
        raise InvalidParameterError.new('key_id', 'between 1 and 800 bytes') if byte_length < 1 || byte_length > 800
      end

      # Counterparty: 'self', 'anyone', or 66-char hex (compressed pubkey)
      def validate_counterparty!(counterparty)
        return if %w[self anyone].include?(counterparty)

        validate_pub_key_hex!(counterparty, 'counterparty')
      end

      # Description: 5-50 characters
      def validate_description!(description, name = 'description')
        raise InvalidParameterError.new(name, 'a String') unless description.is_a?(String)
        raise InvalidParameterError.new(name, 'between 5 and 50 characters') if description.length < 5 || description.length > 50
      end

      # Basket name rules — two-zone model (BRC-99 flat zone, BRC-122 structured zone):
      #
      # Flat zone (no colon):
      # - 5-300 chars, lowercase letters, numbers, and spaces only
      # - no consecutive spaces
      # - must not end with ' basket'
      # - must not start with 'admin' or 'p ' (reserved prefixes)
      # - must not be 'default'
      #
      # Structured zone (contains a colon):
      # - normalised (stripped and downcased) before validation
      # - 1-300 bytes after normalisation
      # - valid characters: lowercase letters, digits, spaces, colons, dots, hyphens, underscores
      # - no consecutive spaces or consecutive colons
      # - prefix before the first colon must match [a-z][a-z0-9]*
      # - content after the first colon must be non-empty after strip
      # - reserved prefixes apply: must not start with 'admin' or 'p '
      def validate_basket!(basket)
        raise InvalidParameterError.new('basket', 'a String') unless basket.is_a?(String)

        if basket.include?(':')
          validate_structured_basket!(basket)
        else
          validate_flat_basket!(basket)
        end
      end

      def validate_flat_basket!(basket)
        raise InvalidParameterError.new('basket', 'between 5 and 300 characters') if basket.length < 5 || basket.length > 300
        raise InvalidParameterError.new('basket', 'lowercase letters, numbers, and spaces only') unless basket.match?(/\A[a-z0-9 ]+\z/)
        raise InvalidParameterError.new('basket', 'free of consecutive spaces') if basket.include?('  ')
        raise InvalidParameterError.new('basket', "not ending with \"#{RESERVED_BASKET_SUFFIX}\"") if basket.end_with?(RESERVED_BASKET_SUFFIX)

        RESERVED_BASKET_PREFIXES.each do |prefix|
          raise InvalidParameterError.new('basket', "not starting with \"#{prefix}\"") if basket.start_with?(prefix)
        end
        raise InvalidParameterError.new('basket', "not equal to \"#{RESERVED_BASKET_NAME}\"") if basket == RESERVED_BASKET_NAME
      end

      def validate_structured_basket!(basket)
        normalised = basket.strip.downcase

        unless basket == normalised
          raise InvalidParameterError.new('basket',
                                          'already normalised (lowercase, trimmed) — received mixed-case or padded input')
        end

        raise InvalidParameterError.new('basket', 'between 1 and 300 bytes') if normalised.bytesize < 1 || normalised.bytesize > 300
        unless normalised.match?(/\A[a-z0-9 :.\-_]+\z/)
          raise InvalidParameterError.new('basket',
                                          'lowercase letters, digits, spaces, colons, dots, hyphens, and underscores only')
        end
        raise InvalidParameterError.new('basket', 'free of consecutive spaces') if normalised.include?('  ')
        raise InvalidParameterError.new('basket', 'free of consecutive colons') if normalised.include?('::')

        colon_pos = normalised.index(':')
        prefix = normalised[0, colon_pos]
        content = normalised[(colon_pos + 1)..].strip

        unless prefix.match?(/\A[a-z][a-z0-9]*\z/)
          raise InvalidParameterError.new('basket',
                                          'a valid namespace prefix before the colon ([a-z][a-z0-9]*)')
        end
        raise InvalidParameterError.new('basket', 'non-empty content after the colon') if content.empty?

        RESERVED_BASKET_PREFIXES.each do |rp|
          raise InvalidParameterError.new('basket', "not starting with \"#{rp}\"") if normalised.start_with?(rp)
        end
      end

      private_class_method :validate_flat_basket!, :validate_structured_basket!

      # Label: 1-300 characters
      def validate_label!(label)
        raise InvalidParameterError.new('label', 'a String') unless label.is_a?(String)
        raise InvalidParameterError.new('label', 'between 1 and 300 characters') if label.empty? || label.length > 300
      end

      # Tag: 1-300 characters
      def validate_tag!(tag)
        raise InvalidParameterError.new('tag', 'a String') unless tag.is_a?(String)
        raise InvalidParameterError.new('tag', 'between 1 and 300 characters') if tag.empty? || tag.length > 300
      end

      # Outpoint: "<64-hex-txid>.<non-negative-integer>"
      def validate_outpoint!(outpoint)
        raise InvalidParameterError.new('outpoint', 'a String') unless outpoint.is_a?(String)

        parts = outpoint.split('.')
        raise InvalidParameterError.new('outpoint', 'in format "<txid>.<index>"') unless parts.length == 2

        txid, index = parts
        raise InvalidParameterError.new('outpoint txid', 'a 64-character hex string') unless txid.match?(/\A[0-9a-f]{64}\z/)
        raise InvalidParameterError.new('outpoint index', 'a non-negative integer') unless index.match?(/\A\d+\z/)
      end

      # Satoshis: 1 to 2_100_000_000_000_000
      def validate_satoshis!(value, name = 'satoshis')
        raise InvalidParameterError.new(name, 'an Integer') unless value.is_a?(Integer)
        raise InvalidParameterError.new(name, 'between 1 and 2100000000000000') if value < 1 || value > 2_100_000_000_000_000
      end

      # Compressed public key hex: exactly 66 hex characters
      def validate_pub_key_hex!(value, name = 'public_key')
        raise InvalidParameterError.new(name, 'a String') unless value.is_a?(String)
        raise InvalidParameterError.new(name, 'a 66-character hex string (compressed public key)') unless value.match?(/\A[0-9a-f]{66}\z/)
      end

      # Hex string: even-length hex characters only
      def validate_hex_string!(value, name = 'hex_string')
        raise InvalidParameterError.new(name, 'a String') unless value.is_a?(String)
        raise InvalidParameterError.new(name, 'a valid hex string') unless value.match?(/\A[0-9a-f]*\z/) && value.length.even?
      end

      # Integer within bounds
      def validate_integer!(value, name, min: nil, max: nil)
        raise InvalidParameterError.new(name, 'an Integer') unless value.is_a?(Integer)
        raise InvalidParameterError.new(name, "at least #{min}") if min && value < min
        raise InvalidParameterError.new(name, "at most #{max}") if max && value > max
      end
    end
  end
end
