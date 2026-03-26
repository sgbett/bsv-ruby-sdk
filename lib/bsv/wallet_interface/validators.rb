# frozen_string_literal: true

module BSV
  module Wallet
    module Validators
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
      def validate_protocol_id!(protocol_id)
        unless protocol_id.is_a?(Array) && protocol_id.length == 2
          raise InvalidParameterError.new('protocol_id',
                                          'an Array of [security_level, protocol_name]')
        end

        level, name = protocol_id
        raise InvalidParameterError.new('protocol_id security level', '0, 1, or 2') unless [0, 1, 2].include?(level)
        raise InvalidParameterError.new('protocol_id name', 'a String') unless name.is_a?(String)

        max_length = name.start_with?('specific linkage revelation') ? 430 : 400
        raise InvalidParameterError.new('protocol_id name', "between 5 and #{max_length} characters") if name.length < 5 || name.length > max_length
        raise InvalidParameterError.new('protocol_id name', 'lowercase letters, numbers, and spaces only') unless name.match?(/\A[a-z0-9 ]+\z/)
        raise InvalidParameterError.new('protocol_id name', 'free of consecutive spaces') if name.include?('  ')
        raise InvalidParameterError.new('protocol_id name', 'not ending with " protocol"') if name.end_with?(' protocol')
        raise InvalidParameterError.new('protocol_id name', 'not starting with "admin"') if name.start_with?('admin')
        raise InvalidParameterError.new('protocol_id name', 'not starting with "p "') if name.start_with?('p ')
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

      # Basket name rules (BRC-99):
      # - 5-300 chars
      # - lowercase letters, numbers, and spaces only
      # - no consecutive spaces
      # - must not end with ' basket'
      # - must not start with 'admin'
      # - must not be 'default'
      # - must not start with 'p ' (BRC-99 reserved)
      def validate_basket!(basket)
        raise InvalidParameterError.new('basket', 'a String') unless basket.is_a?(String)
        raise InvalidParameterError.new('basket', 'between 5 and 300 characters') if basket.length < 5 || basket.length > 300
        raise InvalidParameterError.new('basket', 'lowercase letters, numbers, and spaces only') unless basket.match?(/\A[a-z0-9 ]+\z/)
        raise InvalidParameterError.new('basket', 'free of consecutive spaces') if basket.include?('  ')
        raise InvalidParameterError.new('basket', 'not ending with " basket"') if basket.end_with?(' basket')
        raise InvalidParameterError.new('basket', 'not starting with "admin"') if basket.start_with?('admin')
        raise InvalidParameterError.new('basket', 'not equal to "default"') if basket == 'default'
        raise InvalidParameterError.new('basket', 'not starting with "p "') if basket.start_with?('p ')
      end

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
