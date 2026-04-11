# frozen_string_literal: true

require 'base64'
require 'securerandom'

module BSV
  module Auth
    # Nonce creation and verification for BRC-31 mutual authentication.
    #
    # A nonce is a 48-byte value: 16 random bytes concatenated with a 32-byte
    # HMAC-SHA256 over those 16 bytes, base64-encoded. The HMAC is computed
    # with the wallet using protocol [2, 'server hmac'] and the raw bytes as
    # the key ID (decoded to a string). This makes nonces self-authenticating —
    # only the wallet that created a nonce can verify it.
    #
    # The key ID is derived by decoding the 16 random bytes as UTF-8, replacing
    # any invalid byte sequences with the Unicode replacement character (U+FFFD).
    # This matches the ts-sdk behaviour (TextDecoder in non-fatal replacement mode).
    # Since nonces are always self-verified (counterparty='self'), the key ID
    # encoding does not need to be interoperable across SDK implementations.
    module Nonce
      PROTOCOL_ID  = [2, 'server hmac'].freeze
      RANDOM_BYTES = 16

      module_function

      # Creates a self-authenticating nonce.
      #
      # @param wallet [BSV::Wallet::Interface] wallet with HMAC capability
      # @param counterparty [String] counterparty ('self', 'anyone', or public key hex).
      #   Defaults to 'self' — nonces are self-verified by the creating wallet.
      # @return [String] base64-encoded nonce (48 bytes: 16 random + 32 HMAC)
      def create(wallet, counterparty = 'self')
        first_half = SecureRandom.random_bytes(RANDOM_BYTES)
        key_id     = decode_as_utf8(first_half)

        result = wallet.create_hmac({
                                      data: first_half.bytes,
                                      protocol_id: PROTOCOL_ID,
                                      key_id: key_id,
                                      counterparty: counterparty
                                    })

        nonce_bytes = first_half + result[:hmac].pack('C*')
        ::Base64.strict_encode64(nonce_bytes)
      end

      # Verifies that a nonce was created by the given wallet.
      #
      # @param nonce [String] base64-encoded nonce to verify
      # @param wallet [BSV::Wallet::Interface] wallet
      # @param counterparty [String] counterparty — must match the value used
      #   when the nonce was created (typically 'self')
      # @return [Boolean] true if the nonce is valid
      def verify(nonce, wallet, counterparty = 'self')
        nonce_bytes = ::Base64.strict_decode64(nonce)
        return false if nonce_bytes.bytesize <= RANDOM_BYTES

        first_half = nonce_bytes.byteslice(0, RANDOM_BYTES)
        hmac_bytes = nonce_bytes.byteslice(RANDOM_BYTES, nonce_bytes.bytesize - RANDOM_BYTES)
        key_id     = decode_as_utf8(first_half)

        wallet.verify_hmac({
                             data: first_half.bytes,
                             hmac: hmac_bytes.bytes,
                             protocol_id: PROTOCOL_ID,
                             key_id: key_id,
                             counterparty: counterparty
                           })

        true
      rescue BSV::Wallet::InvalidHmacError
        false
      end

      # Decodes a binary string as UTF-8, replacing invalid byte sequences with
      # the Unicode replacement character (U+FFFD). Used to derive the HMAC key
      # ID from the random nonce bytes in a way consistent with the ts-sdk's
      # use of TextDecoder (non-fatal mode).
      #
      # @param bytes [String] binary (ASCII-8BIT) string
      # @return [String] UTF-8 encoded string
      def decode_as_utf8(bytes)
        bytes.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: "\uFFFD")
      end
    end
  end
end
