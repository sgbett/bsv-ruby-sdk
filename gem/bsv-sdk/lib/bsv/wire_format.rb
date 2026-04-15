# frozen_string_literal: true

module BSV
  # Provides deep camelCase <-> snake_case key conversion for JSON wire boundaries.
  #
  # Used wherever the SDK serialises or deserialises JSON payloads that follow
  # the BRC-100/BRC-103 naming conventions (camelCase on the wire, snake_case in Ruby).
  #
  # @example Convert a hash to wire format
  #   BSV::WireFormat.to_wire({ identity_key: '02abc', protocol_id: [2, 'test'] })
  #   # => { 'identityKey' => '02abc', 'protocolID' => [2, 'test'] }
  #
  # @example Convert a wire format hash to Ruby
  #   BSV::WireFormat.from_wire({ 'identityKey' => '02abc' })
  #   # => { identity_key: '02abc' }
  #
  # @example Deep conversion with nested hashes and arrays
  #   BSV::WireFormat.to_wire({ outputs: [{ locking_script: 'abc' }] })
  #   # => { 'outputs' => [{ 'lockingScript' => 'abc' }] }
  module WireFormat
    # Well-known snake_case -> camelCase pairs for BRC-100/BRC-103 protocol keys.
    #
    # Acronyms like protocolID, keyID are canonical per the TS SDK (Wallet.interfaces.ts).
    # Generic regex fallback handles all other keys.
    SNAKE_TO_CAMEL = {
      # BRC-103 / Auth handshake keys
      'message_type' => 'messageType',
      'identity_key' => 'identityKey',
      'initial_nonce' => 'initialNonce',
      'your_nonce' => 'yourNonce',
      'requested_certificates' => 'requestedCertificates',
      'serial_number' => 'serialNumber',
      'revocation_outpoint' => 'revocationOutpoint',

      # BRC-100 parameter names (acronym forms from TS SDK Wallet.interfaces.ts)
      'protocol_id' => 'protocolID',
      'key_id' => 'keyID',
      'input_beef' => 'inputBEEF',
      'locking_script' => 'lockingScript',
      'unlocking_script' => 'unlockingScript',
      'label_query_mode' => 'labelQueryMode',
      'tag_query_mode' => 'tagQueryMode',
      'include_labels' => 'includeLabels',
      'include_inputs' => 'includeInputs',
      'include_outputs' => 'includeOutputs',
      'include_custom_instructions' => 'includeCustomInstructions',
      'include_tags' => 'includeTags',
      'counterparty_can_see_reveal' => 'counterpartyCanSeeReveal',
      'is_authenticated' => 'isAuthenticated',
      'wait_for_authentication' => 'waitForAuthentication',
      'get_public_key' => 'getPublicKey',
      'create_action' => 'createAction',
      'sign_action' => 'signAction',
      'abort_action' => 'abortAction',
      'list_actions' => 'listActions',
      'internalize_action' => 'internalizeAction',
      'list_outputs' => 'listOutputs',
      'relinquish_output' => 'relinquishOutput',
      'reveal_counterparty_key_linkage' => 'revealCounterpartyKeyLinkage',
      'reveal_specific_key_linkage' => 'revealSpecificKeyLinkage',
      'create_hmac' => 'createHMAC',
      'verify_hmac' => 'verifyHMAC',
      'create_signature' => 'createSignature',
      'verify_signature' => 'verifySignature',
      'acquire_certificate' => 'acquireCertificate',
      'list_certificates' => 'listCertificates',
      'prove_certificate' => 'proveCertificate',
      'relinquish_certificate' => 'relinquishCertificate',
      'discover_by_identity_key' => 'discoverByIdentityKey',
      'discover_by_attributes' => 'discoverByAttributes',
      'get_height' => 'getHeight',
      'get_header_for_height' => 'getHeaderForHeight',
      'get_network' => 'getNetwork',
      'get_version' => 'getVersion'
    }.freeze

    # Inverse lookup table: camelCase -> snake_case.
    CAMEL_TO_SNAKE = SNAKE_TO_CAMEL.invert.freeze

    module_function

    # Deeply converts all Hash keys from snake_case symbols/strings to camelCase strings.
    #
    # Recurses into nested Hash values and Array elements. Non-Hash, non-Array values
    # are passed through unchanged (only keys are converted, not values).
    #
    # @param hash [Hash] the hash to convert
    # @return [Hash] a new hash with camelCase string keys
    # @raise [ArgumentError] if the argument is nil
    def to_wire(hash)
      raise ArgumentError, 'argument must not be nil' if hash.nil?

      hash.each_with_object({}) do |(k, v), out|
        camel_key = snake_to_camel(k.to_s)
        out[camel_key] = deep_convert_value_to_wire(v)
      end
    end

    # Deeply converts all Hash keys from camelCase strings to snake_case symbols.
    #
    # Recurses into nested Hash values and Array elements. Non-Hash, non-Array values
    # are passed through unchanged (only keys are converted, not values).
    #
    # @param hash [Hash] the hash to convert
    # @return [Hash] a new hash with snake_case symbol keys
    # @raise [ArgumentError] if the argument is nil
    def from_wire(hash)
      raise ArgumentError, 'argument must not be nil' if hash.nil?

      hash.each_with_object({}) do |(k, v), out|
        snake_key = camel_to_snake(k.to_s).to_sym
        out[snake_key] = deep_convert_value_from_wire(v)
      end
    end

    # Converts top-level Hash keys only from snake_case to camelCase strings.
    #
    # Unlike {.to_wire}, this does NOT recurse into nested hashes. Use this
    # for auth handshake messages where nested values may contain user-data
    # keys (e.g. base64 certificate type identifiers) that must not be mangled.
    #
    # @param hash [Hash] the hash to convert
    # @return [Hash] a new hash with camelCase string keys (values unchanged)
    def shallow_to_wire(hash)
      raise ArgumentError, 'argument must not be nil' if hash.nil?

      hash.each_with_object({}) do |(k, v), out|
        out[snake_to_camel(k.to_s)] = v
      end
    end

    # Converts top-level Hash keys only from camelCase to snake_case symbols.
    #
    # Unlike {.from_wire}, this does NOT recurse into nested hashes. Use this
    # for auth handshake messages where nested values may contain user-data
    # keys (e.g. base64 certificate type identifiers) that must not be mangled.
    #
    # @param hash [Hash] the hash to convert
    # @return [Hash] a new hash with snake_case symbol keys (values unchanged)
    def shallow_from_wire(hash)
      raise ArgumentError, 'argument must not be nil' if hash.nil?

      hash.each_with_object({}) do |(k, v), out|
        out[camel_to_snake(k.to_s).to_sym] = v
      end
    end

    # Converts a single snake_case string to camelCase.
    #
    # Uses the lookup table for known protocol keys (preserving acronyms like protocolID).
    # Falls back to generic capitalisation for unknown keys.
    #
    # @param str [String] a snake_case string
    # @return [String] the camelCase equivalent
    def snake_to_camel(str)
      SNAKE_TO_CAMEL.fetch(str) { generic_snake_to_camel(str) }
    end

    # Converts a single camelCase string to snake_case.
    #
    # Uses the lookup table for known protocol keys. Falls back to generic
    # regex substitution for unknown keys.
    #
    # @param str [String] a camelCase string
    # @return [String] the snake_case equivalent
    def camel_to_snake(str)
      CAMEL_TO_SNAKE.fetch(str) { generic_camel_to_snake(str) }
    end

    # Generic snake_case -> camelCase conversion for unknown keys.
    def generic_snake_to_camel(str)
      parts = str.split('_')
      return str if parts.length <= 1

      parts[0] + parts[1..].map(&:capitalize).join
    end
    private_class_method :generic_snake_to_camel

    # Generic camelCase -> snake_case conversion for unknown keys.
    def generic_camel_to_snake(str)
      str.gsub(/([A-Z])/) { "_#{::Regexp.last_match(1).downcase}" }.sub(/^_/, '')
    end
    private_class_method :generic_camel_to_snake

    # Recursively converts a value destined for the wire (to_wire direction).
    def deep_convert_value_to_wire(value)
      if value.is_a?(Hash)
        to_wire(value)
      elsif value.is_a?(Array)
        value.map { |elem| deep_convert_value_to_wire(elem) }
      else
        value
      end
    end
    private_class_method :deep_convert_value_to_wire

    # Recursively converts a value coming from the wire (from_wire direction).
    def deep_convert_value_from_wire(value)
      if value.is_a?(Hash)
        from_wire(value)
      elsif value.is_a?(Array)
        value.map { |elem| deep_convert_value_from_wire(elem) }
      else
        value
      end
    end
    private_class_method :deep_convert_value_from_wire
  end
end
