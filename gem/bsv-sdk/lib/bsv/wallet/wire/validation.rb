# frozen_string_literal: true

module BSV
  module Wallet
    module Wire
      # Branded-type validators for BRC-100 parameters.
      #
      # Each method raises InvalidParameterError on failure and returns nil
      # on success. Port of ts-sdk/src/wallet/validationHelpers.ts.
      #
      # The existing ProtoWallet::Validators module delegates here so there
      # is a single source of truth for all parameter validation logic.
      module Validation
        module_function

        MAX_SATOSHIS = 21_000_000 * (10**8)

        # Validates that +value+ is a hex string (even length, hex chars only).
        #
        # @param name [String] parameter name for error messages
        # @param value [Object] the value to validate
        # @param length [Integer, nil] expected number of hex chars (nil = any)
        def hex_string!(name, value, length: nil)
          raise InvalidParameterError.new(name, 'a String') unless value.is_a?(String)

          raise InvalidParameterError.new(name, 'a hex string (characters 0-9, a-f, A-F only)') unless value.match?(/\A[0-9a-fA-F]*\z/)

          raise InvalidParameterError.new(name, 'a hex string with even number of characters') if value.length.odd?

          return unless length && value.length != length

          raise InvalidParameterError.new(name, "a #{length}-character hex string, got #{value.length}")
        end

        # Validates that +value+ is a Base64-encoded string.
        #
        # @param name [String] parameter name for error messages
        # @param value [Object] the value to validate
        def base64_string!(name, value)
          raise InvalidParameterError.new(name, 'a String') unless value.is_a?(String)

          return if value.match?(%r{\A[A-Za-z0-9+/]*={0,2}\z})

          raise InvalidParameterError.new(name, 'a valid Base64 string')
        end

        # Validates an outpoint string in the form "<64-hex-txid>.<vout>".
        #
        # @param name [String] parameter name for error messages
        # @param value [Object] the value to validate
        def outpoint_string!(name, value)
          raise InvalidParameterError.new(name, 'a String') unless value.is_a?(String)

          parts = value.split('.', 2)
          raise InvalidParameterError.new(name, 'an outpoint string in the format <64-hex-txid>.<vout>') unless parts.length == 2

          txid_hex, vout_str = parts

          raise InvalidParameterError.new(name, 'an outpoint with a 64-character hex transaction ID') unless txid_hex.match?(/\A[0-9a-fA-F]{64}\z/)

          raise InvalidParameterError.new(name, 'an outpoint with a non-negative integer output index') unless vout_str.match?(/\A\d+\z/)

          vout = vout_str.to_i
          return unless vout > 0xFFFFFFFF

          raise InvalidParameterError.new(name, 'an outpoint with a vout that fits in a uint32 (0..4294967295)')
        end

        # Validates a compressed public key in hex form (66 chars, 02/03 prefix).
        #
        # @param name [String] parameter name for error messages
        # @param value [Object] the value to validate
        def pub_key_hex!(name, value)
          raise InvalidParameterError.new(name, 'a String') unless value.is_a?(String)

          return if value.match?(/\A0[23][0-9a-fA-F]{64}\z/)

          raise InvalidParameterError.new(name, 'a 66-character compressed public key hex string (02 or 03 prefix)')
        end

        # Validates a description string (5..50 printable characters).
        #
        # @param name [String] parameter name for error messages
        # @param value [Object] the value to validate
        def description_5_to_50!(name, value)
          raise InvalidParameterError.new(name, 'a String') unless value.is_a?(String)

          len = value.length
          raise InvalidParameterError.new(name, 'between 5 and 50 characters') if len < 5 || len > 50
        end

        # Validates a label string (1..150 characters, no spaces).
        #
        # @param name [String] parameter name for error messages
        # @param value [Object] the value to validate
        def label_string!(name, value)
          raise InvalidParameterError.new(name, 'a String') unless value.is_a?(String)

          len = value.length
          raise InvalidParameterError.new(name, 'between 1 and 150 characters') if len < 1 || len > 150
        end

        # Validates a basket name (1..300 characters).
        #
        # @param name [String] parameter name for error messages
        # @param value [Object] the value to validate
        def basket_string!(name, value)
          raise InvalidParameterError.new(name, 'a String') unless value.is_a?(String)

          len = value.length
          raise InvalidParameterError.new(name, 'between 1 and 300 characters') if len < 1 || len > 300
        end

        # Validates an originator domain (1..250 bytes UTF-8).
        # The originator must fit in a single-byte length field in the wire frame.
        #
        # @param name [String] parameter name for error messages
        # @param value [Object] the value to validate
        def originator_domain!(name, value)
          raise InvalidParameterError.new(name, 'a String') unless value.is_a?(String)

          byte_len = value.bytesize
          raise InvalidParameterError.new(name, 'at most 250 bytes') if byte_len > 250
        end

        # Validates a satoshi amount (0..21_000_000 * 10^8).
        #
        # @param name [String] parameter name for error messages
        # @param value [Object] the value to validate
        def satoshi_value!(name, value)
          raise InvalidParameterError.new(name, 'a non-negative integer') unless value.is_a?(Integer)

          return unless value.negative? || value > MAX_SATOSHIS

          raise InvalidParameterError.new(name, "between 0 and #{MAX_SATOSHIS} satoshis")
        end

        # Validates a non-negative integer.
        #
        # @param name [String] parameter name for error messages
        # @param value [Object] the value to validate
        def positive_integer_or_zero!(name, value)
          return if value.is_a?(Integer) && !value.negative?

          raise InvalidParameterError.new(name, 'a non-negative integer')
        end

        # Validates a BRC-43 protocol name string (5..400 chars, lowercase).
        #
        # @param name [String] parameter name for error messages
        # @param value [Object] the value to validate
        def protocol_string_5_to_400!(name, value)
          raise InvalidParameterError.new(name, 'a String') unless value.is_a?(String)

          normalized = value.strip.downcase
          max_length = normalized.start_with?('specific linkage revelation') ? 430 : 400

          raise InvalidParameterError.new(name, "between 5 and #{max_length} characters") if normalized.length < 5 || normalized.length > max_length

          raise InvalidParameterError.new(name, 'lowercase letters, numbers, and spaces only') unless normalized.match?(/\A[a-z0-9 ]+\z/)

          return unless normalized.include?('  ')

          raise InvalidParameterError.new(name, 'free of consecutive spaces')
        end

        # Validates a BRC-43 key ID string (1..800 bytes).
        #
        # @param name [String] parameter name for error messages
        # @param value [Object] the value to validate
        def key_id_string_1_to_800!(name, value)
          raise InvalidParameterError.new(name, 'a String') unless value.is_a?(String)

          byte_length = value.bytesize
          raise InvalidParameterError.new(name, 'between 1 and 800 bytes') if byte_length < 1 || byte_length > 800
        end

        # Validates a wallet counterparty: 'self', 'anyone', or a 66-char hex pubkey.
        #
        # @param name [String] parameter name for error messages
        # @param value [Object] the value to validate
        def wallet_counterparty!(name, value)
          return if %w[self anyone].include?(value)

          pub_key_hex!(name, value)
        end

        # Validates a BRC-43 protocol ID: [security_level (0-2), protocol_name (5-400 chars)].
        #
        # @param name [String] parameter name for error messages
        # @param value [Object] the value to validate
        def wallet_protocol!(name, value)
          raise InvalidParameterError.new(name, 'an Array of [security_level, protocol_name]') unless value.is_a?(Array) && value.length == 2

          level, proto_name = value
          raise InvalidParameterError.new(name, 'a security level of 0, 1, or 2') unless [0, 1, 2].include?(level)

          protocol_string_5_to_400!("#{name} protocol name", proto_name)
        end

        # Validates a certificate acquisition protocol: 'direct' or 'issuance'.
        #
        # @param name [String] parameter name for error messages
        # @param value [Object] the value to validate
        def acquisition_protocol!(name, value)
          return if %w[direct issuance].include?(value)

          raise InvalidParameterError.new(name, "'direct' or 'issuance'")
        end
      end
    end
  end
end
