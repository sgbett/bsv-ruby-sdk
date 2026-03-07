# frozen_string_literal: true

require 'openssl'
require 'securerandom'

module BSV
  module Primitives
    # AES-256-GCM symmetric encryption.
    #
    # Provides authenticated encryption matching the interface used by the
    # TS, Go, and Python reference SDKs. The wire format is:
    #
    #   |--- 32-byte IV ---|--- ciphertext ---|--- 16-byte auth tag ---|
    #
    # All three reference SDKs use a 32-byte IV (non-standard but
    # cross-SDK compatible) and 16-byte authentication tag.
    #
    # @example Round-trip encryption
    #   key = BSV::Primitives::SymmetricKey.from_random
    #   encrypted = key.encrypt('hello world')
    #   key.decrypt(encrypted) #=> "hello world"
    class SymmetricKey
      IV_SIZE = 32
      TAG_SIZE = 16
      KEY_SIZE = 32

      # @param key_bytes [String] 32-byte binary key (shorter keys are left-zero-padded)
      # @raise [ArgumentError] if key is empty or longer than 32 bytes
      def initialize(key_bytes)
        key_bytes = key_bytes.b
        raise ArgumentError, 'key must not be empty' if key_bytes.empty?
        raise ArgumentError, "key must be at most #{KEY_SIZE} bytes, got #{key_bytes.bytesize}" if key_bytes.bytesize > KEY_SIZE

        @key = if key_bytes.bytesize < KEY_SIZE
                 ("\x00".b * (KEY_SIZE - key_bytes.bytesize)) + key_bytes
               else
                 key_bytes
               end
      end

      # Generate a random symmetric key.
      #
      # @return [SymmetricKey]
      def self.from_random
        new(SecureRandom.random_bytes(KEY_SIZE))
      end

      # Derive a symmetric key from an ECDH shared secret.
      #
      # Computes the shared point between the two parties and uses the
      # X-coordinate as the key material. The X-coordinate may be 31 or
      # 32 bytes; shorter values are left-zero-padded automatically.
      #
      # @example Alice and Bob derive the same key
      #   alice_key = SymmetricKey.from_ecdh(alice_priv, bob_pub)
      #   bob_key   = SymmetricKey.from_ecdh(bob_priv, alice_pub)
      #   alice_key.to_bytes == bob_key.to_bytes #=> true
      #
      # @param private_key [PrivateKey] one party's private key
      # @param public_key [PublicKey] the other party's public key
      # @return [SymmetricKey]
      def self.from_ecdh(private_key, public_key)
        shared = private_key.derive_shared_secret(public_key)
        # X-coordinate = bytes 1..32 of the compressed point (skip the 02/03 prefix)
        x_bytes = shared.compressed.byteslice(1, 32)
        new(x_bytes)
      end

      # Encrypt a message with AES-256-GCM.
      #
      # Generates a random 32-byte IV per call. Returns the concatenation
      # of IV, ciphertext, and 16-byte authentication tag.
      #
      # @param plaintext [String] the message to encrypt
      # @return [String] binary string: IV (32) + ciphertext + auth tag (16)
      def encrypt(plaintext)
        iv = SecureRandom.random_bytes(IV_SIZE)

        cipher = OpenSSL::Cipher.new('aes-256-gcm')
        cipher.encrypt
        cipher.key = @key
        cipher.iv_len = IV_SIZE
        cipher.iv = iv
        cipher.auth_data = ''.b

        ciphertext = cipher.update(plaintext.b) + cipher.final
        tag = cipher.auth_tag(TAG_SIZE)

        iv + ciphertext + tag
      end

      # Decrypt an AES-256-GCM encrypted message.
      #
      # Expects the wire format: IV (32) + ciphertext + auth tag (16).
      #
      # @param data [String] the encrypted message
      # @return [String] the decrypted plaintext (binary)
      # @raise [ArgumentError] if the data is too short
      # @raise [OpenSSL::Cipher::CipherError] if authentication fails (wrong key or tampered data)
      def decrypt(data)
        data = data.b
        raise ArgumentError, "ciphertext too short: #{data.bytesize} bytes (minimum #{IV_SIZE + TAG_SIZE})" if data.bytesize < IV_SIZE + TAG_SIZE

        iv = data.byteslice(0, IV_SIZE)
        tag = data.byteslice(-TAG_SIZE, TAG_SIZE)
        ciphertext = data.byteslice(IV_SIZE, data.bytesize - IV_SIZE - TAG_SIZE)

        decipher = OpenSSL::Cipher.new('aes-256-gcm')
        decipher.decrypt
        decipher.key = @key
        decipher.iv_len = IV_SIZE
        decipher.iv = iv
        decipher.auth_tag = tag
        decipher.auth_data = ''.b

        decipher.update(ciphertext) + decipher.final
      end

      # Return the raw key bytes.
      #
      # @return [String] 32-byte binary key
      def to_bytes
        @key.dup
      end
    end
  end
end
