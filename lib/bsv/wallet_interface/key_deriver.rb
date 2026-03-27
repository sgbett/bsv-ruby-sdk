# frozen_string_literal: true

module BSV
  module Wallet
    # BRC-42/43 key derivation for the wallet interface.
    #
    # Derives child keys from a root private key using BKDS (BSV Key Derivation
    # Scheme). Supports protocol IDs, key IDs, counterparties, and security
    # levels as defined in BRC-43.
    class KeyDeriver
      ANYONE_BN = OpenSSL::BN.new(1)

      attr_reader :root_key

      # @param root_key [BSV::Primitives::PrivateKey, String] a private key or 'anyone'
      def initialize(root_key)
        @root_key = if root_key == 'anyone'
                      BSV::Primitives::PrivateKey.new(ANYONE_BN)
                    elsif root_key.is_a?(BSV::Primitives::PrivateKey)
                      root_key
                    else
                      raise ArgumentError, "expected a BSV::Primitives::PrivateKey or 'anyone', got #{root_key.class}"
                    end
      end

      # Returns the identity public key as a hex string.
      # @return [String] 66-character compressed public key hex
      def identity_key
        @root_key.public_key.to_hex
      end

      # Derives a public key using BRC-42 key derivation.
      #
      # @param protocol_id [Array] [security_level, protocol_name]
      # @param key_id [String] key identifier
      # @param counterparty [String] public key hex, 'self', or 'anyone'
      # @param for_self [Boolean] derive from own identity rather than counterparty's
      # @return [BSV::Primitives::PublicKey]
      def derive_public_key(protocol_id, key_id, counterparty, for_self: false)
        Validators.validate_protocol_id!(protocol_id)
        Validators.validate_key_id!(key_id)
        invoice = compute_invoice_number(protocol_id, key_id)
        counterparty_pub = resolve_counterparty(counterparty)

        if for_self
          @root_key.derive_child(counterparty_pub, invoice).public_key
        else
          counterparty_pub.derive_child(@root_key, invoice)
        end
      end

      # Derives a private key using BRC-42 key derivation.
      #
      # @param protocol_id [Array] [security_level, protocol_name]
      # @param key_id [String] key identifier
      # @param counterparty [String] public key hex, 'self', or 'anyone'
      # @return [BSV::Primitives::PrivateKey]
      def derive_private_key(protocol_id, key_id, counterparty)
        Validators.validate_protocol_id!(protocol_id)
        Validators.validate_key_id!(key_id)
        invoice = compute_invoice_number(protocol_id, key_id)
        counterparty_pub = resolve_counterparty(counterparty)
        @root_key.derive_child(counterparty_pub, invoice)
      end

      # Derives a symmetric key for encryption/HMAC operations.
      #
      # Uses ECDH between the derived private and public child keys to
      # produce a shared secret, then uses the X-coordinate as the key.
      #
      # @param protocol_id [Array] [security_level, protocol_name]
      # @param key_id [String] key identifier
      # @param counterparty [String] public key hex, 'self', or 'anyone'
      # @return [BSV::Primitives::SymmetricKey]
      def derive_symmetric_key(protocol_id, key_id, counterparty)
        Validators.validate_protocol_id!(protocol_id)
        Validators.validate_key_id!(key_id)
        invoice = compute_invoice_number(protocol_id, key_id)
        counterparty_pub = resolve_counterparty(counterparty)

        derived_private = @root_key.derive_child(counterparty_pub, invoice)
        derived_public = counterparty_pub.derive_child(@root_key, invoice)

        BSV::Primitives::SymmetricKey.from_ecdh(derived_private, derived_public)
      end

      # Reveals the ECDH shared secret between this wallet and a counterparty.
      # Used for BRC-69 Method 1 (counterparty key linkage).
      #
      # @param counterparty [String] public key hex (not 'self')
      # @return [String] compressed shared secret bytes
      def reveal_counterparty_secret(counterparty)
        raise InvalidParameterError.new('counterparty', 'not "self" for key linkage revelation') if counterparty == 'self'

        counterparty_pub = resolve_counterparty(counterparty)
        @root_key.derive_shared_secret(counterparty_pub).compressed
      end

      # Reveals the specific key offset for a particular derived key.
      # Used for BRC-69 Method 2 (specific key linkage).
      #
      # @param counterparty [String] public key hex
      # @param protocol_id [Array] [security_level, protocol_name]
      # @param key_id [String] key identifier
      # @return [String] HMAC-SHA256 bytes (the key offset)
      def reveal_specific_secret(counterparty, protocol_id, key_id)
        Validators.validate_protocol_id!(protocol_id)
        Validators.validate_key_id!(key_id)
        counterparty_pub = resolve_counterparty(counterparty)
        shared = @root_key.derive_shared_secret(counterparty_pub)
        invoice = compute_invoice_number(protocol_id, key_id)
        BSV::Primitives::Digest.hmac_sha256(shared.compressed, invoice.encode('UTF-8'))
      end

      private

      # Resolves a counterparty identifier to a PublicKey.
      #
      # @param counterparty [String] 'self', 'anyone', or a hex public key
      # @return [BSV::Primitives::PublicKey]
      def resolve_counterparty(counterparty)
        case counterparty
        when 'self'
          @root_key.public_key
        when 'anyone'
          BSV::Primitives::PrivateKey.new(ANYONE_BN).public_key
        else
          Validators.validate_counterparty!(counterparty)
          BSV::Primitives::PublicKey.from_hex(counterparty)
        end
      end

      # Computes the invoice number from a protocol ID and key ID.
      # Format: "#{security_level}-#{protocol_name}-#{key_id}"
      #
      # @param protocol_id [Array] [security_level, protocol_name]
      # @param key_id [String]
      # @return [String]
      def compute_invoice_number(protocol_id, key_id)
        "#{protocol_id[0]}-#{protocol_id[1]}-#{key_id}"
      end
    end
  end
end
