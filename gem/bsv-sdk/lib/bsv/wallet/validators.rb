# frozen_string_literal: true

module BSV
  module Wallet
    # Validation helpers for BRC-100 wallet method parameters.
    #
    # Provides the subset of validators required by KeyDeriver and ProtoWallet.
    # Raises +InvalidParameterError+ for any invalid input.
    module Validators
      module_function

      # Validates a BRC-43 protocol ID.
      #
      # Must be an Array of [Integer(0-2), String(5-400 chars)]. The name is
      # normalised (stripped and downcased) before length/content checks.
      #
      # @param protocol_id [Object] the value to validate
      # @raise [InvalidParameterError]
      def validate_protocol_id!(protocol_id)
        unless protocol_id.is_a?(Array) && protocol_id.length == 2
          raise InvalidParameterError.new('protocol_id', 'an Array of [security_level, protocol_name]')
        end

        level, name = protocol_id
        raise InvalidParameterError.new('protocol_id security level', '0, 1, or 2') unless [0, 1, 2].include?(level)
        raise InvalidParameterError.new('protocol_id name', 'a String') unless name.is_a?(String)

        name = name.strip.downcase
        max_length = name.start_with?('specific linkage revelation') ? 430 : 400
        raise InvalidParameterError.new('protocol_id name', "between 5 and #{max_length} characters") if name.length < 5 || name.length > max_length

        raise InvalidParameterError.new('protocol_id name', 'lowercase letters, numbers, and spaces only') unless name.match?(/\A[a-z0-9 ]+\z/)

        raise InvalidParameterError.new('protocol_id name', 'free of consecutive spaces') if name.include?('  ')
      end

      # Validates a BRC-43 key ID.
      #
      # Must be a non-empty String of at most 800 bytes.
      #
      # @param key_id [Object] the value to validate
      # @raise [InvalidParameterError]
      def validate_key_id!(key_id)
        raise InvalidParameterError.new('key_id', 'a String') unless key_id.is_a?(String)

        byte_length = key_id.bytesize
        raise InvalidParameterError.new('key_id', 'between 1 and 800 bytes') if byte_length < 1 || byte_length > 800
      end

      # Validates a counterparty: 'self', 'anyone', or a 66-char hex pubkey.
      #
      # @param counterparty [Object] the value to validate
      # @raise [InvalidParameterError]
      def validate_counterparty!(counterparty)
        return if %w[self anyone].include?(counterparty)

        validate_pub_key_hex!(counterparty, 'counterparty')
      end

      # Validates a compressed public key in hex form (66 chars, 02/03/04 prefix).
      #
      # @param value [Object] the value to validate
      # @param name [String] parameter name for error messages
      # @raise [InvalidParameterError]
      def validate_pub_key_hex!(value, name = 'public_key')
        raise InvalidParameterError.new(name, 'a String') unless value.is_a?(String)

        raise InvalidParameterError.new(name, 'a 66-character hex string (compressed public key)') unless value.match?(/\A[0-9a-f]{66}\z/)
      end
    end
  end
end
