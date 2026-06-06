# frozen_string_literal: true

module BSV
  module Overlay
    # Script template for creating, unlocking, and decoding SHIP and SLAP advertisements.
    #
    # SHIP (Service Host Interconnect) and SLAP (Service Lookup Availability)
    # tokens are PushDrop scripts containing four data fields:
    #
    #   Field 0: protocol string — 'SHIP' or 'SLAP'
    #   Field 1: identity key — 33-byte compressed public key (binary)
    #   Field 2: domain — UTF-8 string
    #   Field 3: topic or service name — UTF-8 string
    #
    # The locking script includes a fifth field containing a wallet signature
    # over the concatenation of fields 0–3, which authenticates the token at
    # creation time. The lock is secured with a P2PK condition derived from the
    # wallet using BRC-42/43 key derivation at security level 2.
    #
    # Script layout (lock-after PushDrop format):
    #
    #   <protocol> <identity_key> <domain> <topic> <wallet_sig>
    #   OP_2DROP OP_2DROP OP_DROP
    #   <derived_pubkey> OP_CHECKSIG
    #
    # @example Lock a SHIP advertisement
    #   wallet = BSV::Wallet::Client.new(private_key, storage: BSV::Wallet::Store::Memory.new)
    #   template = BSV::Overlay::AdminTokenTemplate.new(wallet)
    #   locking_script = template.lock('SHIP', 'myhost.example.com', 'tm_payments')
    #   decoded = BSV::Overlay::AdminTokenTemplate.decode(locking_script)
    #   decoded.identity_key  # => hex public key of the wallet
    class AdminTokenTemplate
      # Decoded representation of a SHIP or SLAP advertisement.
      class Advertisement
        # @return [String] protocol identifier — 'SHIP' or 'SLAP'
        attr_reader :protocol

        # @return [String] hex-encoded compressed public key (33 bytes)
        attr_reader :identity_key

        # @return [String] domain where the topic or service is available
        attr_reader :domain

        # @return [String] topic or service name being advertised
        attr_reader :topic_or_service

        # @param protocol [String]
        # @param identity_key [String]
        # @param domain [String]
        # @param topic_or_service [String]
        def initialize(protocol:, identity_key:, domain:, topic_or_service:)
          @protocol = protocol
          @identity_key = identity_key
          @domain = domain
          @topic_or_service = topic_or_service
        end
      end

      # Unlocker returned by {#unlock}.
      #
      # Satisfies the P2PK condition in a PushDrop locking script by signing
      # the BIP-143 sighash of the spending transaction using the wallet's
      # derived key for the appropriate protocol.
      class Unlocker
        # Estimated length of a P2PK unlocking script: 1 push opcode + up to
        # 72 DER-encoded signature bytes + 1 sighash byte = 73 bytes total.
        ESTIMATED_LENGTH = 73

        # @param wallet [#create_signature] BRC-100 wallet interface
        # @param protocol_id [Array] two-element array [security_level, protocol_name]
        # @param originator [String, nil] optional originator domain
        def initialize(wallet, protocol_id, originator)
          @wallet = wallet
          @protocol_id = protocol_id
          @originator = originator
        end

        # Generate the unlocking script for the given input.
        #
        # Computes the BIP-143 sighash (SIGHASH_ALL|FORK_ID) and signs it
        # using the wallet's derived key for the protocol.
        #
        # @param tx [BSV::Transaction::Tx] the spending transaction
        # @param input_index [Integer] which input to sign
        # @return [BSV::Script::Script] the unlocking script
        def sign(tx, input_index)
          sighash_type = BSV::Transaction::Sighash::ALL_FORK_ID
          hash = tx.sighash(input_index, sighash_type)
          hash_bytes = hash.unpack('C*')

          sig_args = { hash_to_directly_sign: hash_bytes, protocol_id: @protocol_id, key_id: '1', counterparty: 'self' }
          sig_args[:originator] = @originator if @originator
          result = @wallet.create_signature(**sig_args)

          sig_bytes = result[:signature].pack('C*')
          sig_with_hashtype = sig_bytes + [sighash_type].pack('C')
          BSV::Script::Script.pushdrop_unlock(
            BSV::Script::Script.p2pk_unlock(sig_with_hashtype)
          )
        end

        # Estimated byte length of the unlocking script.
        #
        # @param _tx [BSV::Transaction::Tx] unused
        # @param _input_index [Integer] unused
        # @return [Integer]
        def estimated_length(_tx, _input_index)
          ESTIMATED_LENGTH
        end
      end

      VALID_PROTOCOLS = [Constants::PROTOCOL_SHIP, Constants::PROTOCOL_SLAP].freeze
      private_constant :VALID_PROTOCOLS

      # Decode a SHIP or SLAP advertisement from a PushDrop locking script.
      #
      # @param script [BSV::Script::Script, nil] the locking script to decode
      # @return [Advertisement, nil] the decoded advertisement, or +nil+ if the
      #   script is nil, empty, or not a PushDrop script
      # @raise [BSV::Overlay::OverlayError] if the script is PushDrop but has
      #   fewer than 4 fields, or if the protocol field is not 'SHIP' or 'SLAP'
      def self.decode(script)
        return nil if script.nil? || script.bytes.empty?
        return nil unless script.pushdrop?

        fields = script.pushdrop_fields
        raise OverlayError, 'Invalid SHIP/SLAP advertisement: expected at least 4 fields' if fields.length < 4

        protocol = fields[0].force_encoding('UTF-8')
        raise OverlayError, "Invalid SHIP/SLAP protocol: #{protocol.inspect}" unless VALID_PROTOCOLS.include?(protocol)

        identity_key = fields[1].unpack1('H*')
        domain = normalise_field(fields[2])
        topic_or_service = normalise_field(fields[3])

        Advertisement.new(
          protocol: protocol,
          identity_key: identity_key,
          domain: domain,
          topic_or_service: topic_or_service
        )
      end

      # Construct a new AdminTokenTemplate instance.
      #
      # @param wallet [#get_public_key, #create_signature] any object implementing
      #   the BRC-100 wallet interface (e.g. {BSV::Wallet::Client})
      # @param originator [String, nil] optional FQDN of the originating application
      def initialize(wallet, originator: nil)
        @wallet = wallet
        @originator = originator
      end

      # Create a SHIP or SLAP advertisement locking script.
      #
      # Derives the wallet's identity key, builds the four advertisement fields,
      # signs them with the protocol-derived key, and constructs a PushDrop
      # locking script with a P2PK spending condition.
      #
      # @param protocol [String] 'SHIP' or 'SLAP'
      # @param domain [String] domain where the service or topic is available
      # @param topic_or_service [String] topic or service name to advertise
      # @return [BSV::Script::Script] the locking script
      # @raise [BSV::Overlay::OverlayError] if protocol is not 'SHIP' or 'SLAP'
      def lock(protocol, domain, topic_or_service)
        raise OverlayError, "Invalid protocol: #{protocol.inspect}. Must be 'SHIP' or 'SLAP'" \
          unless VALID_PROTOCOLS.include?(protocol)

        protocol_id = protocol_id_for(protocol)

        # Fetch the wallet's identity key (compressed public key hex)
        id_args = { identity_key: true }
        id_args[:originator] = @originator if @originator
        identity_result = @wallet.get_public_key(**id_args)
        identity_key_hex = identity_result[:public_key]
        identity_key_bytes = [identity_key_hex].pack('H*')

        # Derive the locking public key for this protocol
        lock_args = { protocol_id: protocol_id, key_id: '1', counterparty: 'self' }
        lock_args[:originator] = @originator if @originator
        locking_result = @wallet.get_public_key(**lock_args)
        locking_pubkey_hex = locking_result[:public_key]
        locking_pubkey_bytes = [locking_pubkey_hex].pack('H*')

        # Build the four advertisement fields
        field_protocol = protocol.b
        field_identity = identity_key_bytes
        field_domain = domain.encode('binary')
        field_topic = topic_or_service.encode('binary')

        # Sign the concatenation of all four fields as authentication
        data_to_sign = (field_protocol + field_identity + field_domain + field_topic).unpack('C*')
        sig_args = { data: data_to_sign, protocol_id: protocol_id, key_id: '1', counterparty: 'self' }
        sig_args[:originator] = @originator if @originator
        sig_result = @wallet.create_signature(**sig_args)
        field_sig = sig_result[:signature].pack('C*')

        fields = [field_protocol, field_identity, field_domain, field_topic, field_sig]
        lock_script = BSV::Script::Script.p2pk_lock(locking_pubkey_bytes)
        BSV::Script::Script.pushdrop_lock(fields, lock_script)
      end

      # Return an unlocker for spending an advertisement token.
      #
      # The returned object follows the {BSV::Transaction::UnlockingScriptTemplate}
      # interface and can be assigned to an input's +unlocking_script_template+.
      #
      # @param protocol [String] 'SHIP' or 'SLAP' — must match the locked token
      # @return [Unlocker] an object with +#sign+ and +#estimated_length+
      # @raise [BSV::Overlay::OverlayError] if protocol is not 'SHIP' or 'SLAP'
      def unlock(protocol)
        raise OverlayError, "Invalid protocol: #{protocol.inspect}. Must be 'SHIP' or 'SLAP'" \
          unless VALID_PROTOCOLS.include?(protocol)

        Unlocker.new(@wallet, protocol_id_for(protocol), @originator)
      end

      class << self
        private

        # Normalise a field value: decode as UTF-8 and treat a single null byte
        # as an empty string. This matches the encoding used when an empty string
        # is represented as a raw +\x00+ byte push rather than OP_0.
        def normalise_field(raw)
          return '' if raw.bytesize == 1 && raw.getbyte(0).zero?

          raw.force_encoding('UTF-8')
        end
      end

      private

      # Map a protocol string to its BRC-42/43 protocol ID array for key derivation.
      #
      # Uses the lowercase derivation names required by the wallet key-derivation
      # validator, matching the Go SDK convention (not the titlecase TS SDK variant).
      #
      # @param protocol [String] 'SHIP' or 'SLAP'
      # @return [Array] [security_level, protocol_name]
      def protocol_id_for(protocol)
        if protocol == Constants::PROTOCOL_SHIP
          [2, Constants::DERIVE_PROTOCOL_SHIP]
        else
          [2, Constants::DERIVE_PROTOCOL_SLAP]
        end
      end
    end
  end
end
