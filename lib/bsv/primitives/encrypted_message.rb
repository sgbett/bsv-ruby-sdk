# frozen_string_literal: true

require 'securerandom'

module BSV
  module Primitives
    # BRC-78 encrypted messages.
    #
    # Provides confidential authenticated messaging using BRC-42 derived keys
    # and AES-256-GCM symmetric encryption. Both parties derive the same
    # symmetric key from their respective BRC-42 child keys via ECDH.
    #
    # @example Encrypt and decrypt
    #   ct = EncryptedMessage.encrypt(message, sender_priv, recipient_pub)
    #   EncryptedMessage.decrypt(ct, recipient_priv) #=> message
    #
    # @see https://github.com/bitcoin-sv/BRCs/blob/master/peer-to-peer/0078.md
    module EncryptedMessage
      # Protocol version bytes: "BB\x10\x33"
      VERSION = "\x42\x42\x10\x33".b.freeze

      # Minimum message size: VERSION(4) + sender(33) + recipient(33) + key_id(32) = 102
      HEADER_SIZE = 102

      module_function

      # Encrypt a message using the BRC-78 protocol.
      #
      # @param message [String] the message to encrypt
      # @param sender [PrivateKey] the sender's private key
      # @param recipient [PublicKey] the recipient's public key
      # @return [String] binary encrypted message (header + AES-GCM payload)
      def encrypt(message, sender, recipient)
        key_id = SecureRandom.random_bytes(32)
        invoice = "2-message encryption-#{[key_id].pack('m0')}"

        sym_key = derive_symmetric_key(sender, recipient, invoice)
        encrypted = sym_key.encrypt(message)

        VERSION +
          sender.public_key.compressed +
          recipient.compressed +
          key_id +
          encrypted
      end

      # Decrypt a BRC-78 encrypted message.
      #
      # @param data [String] the binary encrypted message (from {.encrypt})
      # @param recipient [PrivateKey] the recipient's private key
      # @return [String] the decrypted plaintext (binary)
      # @raise [ArgumentError] if version is wrong, recipient doesn't match, or message is too short
      # @raise [OpenSSL::Cipher::CipherError] if decryption fails (tampered or wrong key)
      def decrypt(data, recipient)
        data = data.b
        raise ArgumentError, "encrypted message too short: #{data.bytesize} bytes (minimum #{HEADER_SIZE})" if data.bytesize < HEADER_SIZE

        version = data.byteslice(0, 4)
        raise ArgumentError, "message version mismatch: expected #{VERSION.unpack1('H*')}, received #{version.unpack1('H*')}" if version != VERSION

        sender_pub = PublicKey.from_bytes(data.byteslice(4, 33))
        expected_recipient = data.byteslice(37, 33)
        actual_recipient = recipient.public_key.compressed

        if expected_recipient != actual_recipient
          raise ArgumentError,
                "the encrypted message expects a recipient public key of #{expected_recipient.unpack1('H*')}, " \
                "but the provided key is #{actual_recipient.unpack1('H*')}"
        end

        key_id = data.byteslice(70, 32)
        encrypted_payload = data.byteslice(HEADER_SIZE, data.bytesize - HEADER_SIZE)

        invoice = "2-message encryption-#{[key_id].pack('m0')}"
        sym_key = derive_symmetric_key_for_decrypt(sender_pub, recipient, invoice)
        sym_key.decrypt(encrypted_payload)
      end

      class << self
        private

        # Derive the symmetric key for encryption (sender has private key).
        def derive_symmetric_key(sender_priv, recipient_pub, invoice)
          sender_child = sender_priv.derive_child(recipient_pub, invoice)
          recipient_child = recipient_pub.derive_child(sender_priv, invoice)
          shared = sender_child.derive_shared_secret(recipient_child)
          SymmetricKey.new(shared.compressed.byteslice(1, 32))
        end

        # Derive the symmetric key for decryption (recipient has private key).
        def derive_symmetric_key_for_decrypt(sender_pub, recipient_priv, invoice)
          sender_child = sender_pub.derive_child(recipient_priv, invoice)
          recipient_child = recipient_priv.derive_child(sender_pub, invoice)
          shared = recipient_child.derive_shared_secret(sender_child)
          SymmetricKey.new(shared.compressed.byteslice(1, 32))
        end
      end
    end
  end
end
