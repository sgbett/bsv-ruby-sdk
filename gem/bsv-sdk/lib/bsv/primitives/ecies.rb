# frozen_string_literal: true

require 'openssl'
require 'securerandom'

module BSV
  module Primitives
    # Elliptic Curve Integrated Encryption Scheme (ECIES) using the
    # Electrum/BIE1 protocol.
    #
    # Provides authenticated encryption using an ephemeral ECDH shared secret.
    # The sender generates a random key pair, derives a shared secret with the
    # recipient's public key, then encrypts with AES-128-CBC and authenticates
    # with HMAC-SHA-256 (encrypt-then-MAC).
    #
    # @example Encrypt and decrypt a message
    #   alice = BSV::Primitives::PrivateKey.generate
    #   bob   = BSV::Primitives::PrivateKey.generate
    #
    #   ciphertext = BSV::Primitives::ECIES.encrypt('hello', bob.public_key)
    #   plaintext  = BSV::Primitives::ECIES.decrypt(ciphertext, bob)
    module ECIES
      # BIE1 magic bytes identifying the Electrum ECIES format.
      MAGIC = 'BIE1'.b.freeze

      # Raised when HMAC verification or AES decryption fails.
      class DecryptionError < StandardError; end

      module_function

      # Encrypt a message for a recipient's public key.
      #
      # @param message [String] the plaintext message
      # @param public_key [PublicKey] the recipient's public key
      # @param private_key [PrivateKey, nil] optional ephemeral key (random if omitted)
      # @param no_key [Boolean] when +true+, omit the ephemeral public key from the payload
      # @return [String] encrypted payload: BIE1 magic + [ephemeral pubkey] + ciphertext + HMAC
      def encrypt(message, public_key, private_key: nil, no_key: false)
        message = message.b if message.encoding != Encoding::ASCII_8BIT

        ephemeral = private_key || PrivateKey.generate
        ephemeral_pub = ephemeral.public_key

        iv, key_e, key_m = derive_keys(ephemeral, public_key)

        cipher = OpenSSL::Cipher.new('aes-128-cbc')
        cipher.encrypt
        cipher.key = key_e
        cipher.iv = iv
        ciphertext = message.empty? ? cipher.final : cipher.update(message) + cipher.final

        payload = if no_key
                    MAGIC + ciphertext
                  else
                    MAGIC + ephemeral_pub.compressed + ciphertext
                  end
        mac = Digest.hmac_sha256(key_m, payload)

        payload + mac
      end

      # Decrypt an ECIES-encrypted message with a private key.
      #
      # Verifies the HMAC before attempting decryption (encrypt-then-MAC).
      #
      # The ephemeral public key may be embedded in the payload (compressed or
      # uncompressed), or absent entirely (when the payload was encrypted with
      # +no_key: true+). When absent, +sender_public_key+ must be provided.
      #
      # If a key is found in the payload and +sender_public_key+ is also given,
      # the payload key takes precedence (matching TS SDK behaviour).
      #
      # @param data [String] the encrypted payload (BIE1 format)
      # @param private_key [PrivateKey] the recipient's private key
      # @param sender_public_key [PublicKey, nil] sender's public key (required when no key in payload)
      # @return [String] the decrypted plaintext
      # @raise [ArgumentError] if the data is too short, has invalid magic, or has no key and none provided
      # @raise [DecryptionError] if HMAC verification or AES decryption fails
      def decrypt(data, private_key, sender_public_key: nil)
        data = data.b if data.encoding != Encoding::ASCII_8BIT

        # Minimum: magic(4) + ciphertext(16) + HMAC(32) = 52 (no-key case)
        raise ArgumentError, 'data too short' if data.bytesize < 52

        magic = data[0, 4]
        raise ArgumentError, 'invalid magic: expected BIE1' unless magic == MAGIC

        # Determine ephemeral key presence and format by inspecting byte at offset 4.
        # Guard: only attempt to read a key if sufficient bytes remain beyond HMAC.
        tag_length = 32
        offset = 4
        ephemeral_pub = nil

        remaining_after_offset = data.bytesize - offset - tag_length
        if remaining_after_offset >= 33
          first_byte = data.getbyte(offset)
          if [0x02, 0x03].include?(first_byte)
            # Compressed key: 33 bytes
            ephemeral_pub = PublicKey.from_bytes(data[offset, 33])
            offset += 33
          elsif first_byte == 0x04 && remaining_after_offset >= 65
            # Uncompressed key: 65 bytes
            ephemeral_pub = PublicKey.from_bytes(data[offset, 65])
            offset += 65
          end
        end

        # If no key found in payload, fall back to provided sender_public_key
        ephemeral_pub ||= sender_public_key
        raise ArgumentError, 'sender_public_key required when no key in payload' if ephemeral_pub.nil?

        mac = data[-tag_length, tag_length]
        ciphertext = data[offset...-tag_length]

        iv, key_e, key_m = derive_keys(private_key, ephemeral_pub)

        # Verify HMAC before decryption (encrypt-then-MAC)
        payload = data[0...-tag_length]
        expected_mac = Digest.hmac_sha256(key_m, payload)

        raise DecryptionError, 'HMAC verification failed' unless secure_compare(mac, expected_mac)

        begin
          cipher = OpenSSL::Cipher.new('aes-128-cbc')
          cipher.decrypt
          cipher.key = key_e
          cipher.iv = iv
          cipher.update(ciphertext) + cipher.final
        rescue OpenSSL::Cipher::CipherError => e
          raise DecryptionError, "decryption failed: #{e.message}"
        end
      end

      # Encrypt a message using the Bitcore ECIES variant.
      #
      # Differs from the Electrum variant: no magic prefix, AES-256-CBC
      # (not AES-128), random IV prepended to ciphertext, and HMAC covers
      # the ciphertext (not the ephemeral pubkey).
      #
      # Wire format: +ephemeral_pub(33) + IV(16) + ciphertext + HMAC(32)+
      #
      # @param message [String] the plaintext message
      # @param public_key [PublicKey] the recipient's public key
      # @param private_key [PrivateKey, nil] optional ephemeral key (random if omitted)
      # @return [String] encrypted payload
      def bitcore_encrypt(message, public_key, private_key: nil)
        message = message.b if message.encoding != Encoding::ASCII_8BIT

        ephemeral = private_key || PrivateKey.generate
        key_e, key_m = derive_bitcore_keys(ephemeral, public_key)

        iv = SecureRandom.random_bytes(16)

        cipher = OpenSSL::Cipher.new('aes-256-cbc')
        cipher.encrypt
        cipher.key = key_e
        cipher.iv = iv
        ciphertext = message.empty? ? cipher.final : cipher.update(message) + cipher.final

        c = iv + ciphertext
        mac = Digest.hmac_sha256(key_m, c)

        ephemeral.public_key.compressed + c + mac
      end

      # Decrypt a message encrypted with the Bitcore ECIES variant.
      #
      # @param data [String] the encrypted payload (Bitcore ECIES format)
      # @param private_key [PrivateKey] the recipient's private key
      # @return [String] the decrypted plaintext
      # @raise [ArgumentError] if the data is too short
      # @raise [DecryptionError] if HMAC verification or AES decryption fails
      def bitcore_decrypt(data, private_key)
        data = data.b if data.encoding != Encoding::ASCII_8BIT

        # Minimum: ephemeral_pub(33) + IV(16) + AES block(16) + HMAC(32) = 97
        raise ArgumentError, 'data too short' if data.bytesize < 97

        ephemeral_pub = PublicKey.from_bytes(data[0, 33])
        mac = data[-32, 32]
        c = data[33...-32] # IV + ciphertext

        key_e, key_m = derive_bitcore_keys(private_key, ephemeral_pub)

        expected_mac = Digest.hmac_sha256(key_m, c)
        raise DecryptionError, 'HMAC verification failed' unless secure_compare(mac, expected_mac)

        iv = c[0, 16]
        ciphertext = c[16..]

        begin
          cipher = OpenSSL::Cipher.new('aes-256-cbc')
          cipher.decrypt
          cipher.key = key_e
          cipher.iv = iv
          cipher.update(ciphertext) + cipher.final
        rescue OpenSSL::Cipher::CipherError => e
          raise DecryptionError, "decryption failed: #{e.message}"
        end
      end

      class << self
        private

        def secure_compare(mac, expected)
          return false unless mac.bytesize == expected.bytesize

          if OpenSSL.respond_to?(:fixed_length_secure_compare)
            OpenSSL.fixed_length_secure_compare(mac, expected)
          else
            # Constant-time comparison for Ruby < 3.2
            result = 0
            mac.bytes.zip(expected.bytes) { |x, y| result |= x ^ y }
            result.zero?
          end
        end

        def derive_keys(private_key, public_key)
          shared = private_key.derive_shared_secret(public_key)
          ecdh_key = shared.compressed
          derived = Digest.sha512(ecdh_key)

          iv    = derived[0, 16]
          key_e = derived[16, 16]
          key_m = derived[32, 32]

          [iv, key_e, key_m]
        end

        # Bitcore key derivation: SHA-512(ECDH X-coordinate) → key_e(32) + key_m(32)
        def derive_bitcore_keys(private_key, public_key)
          shared = private_key.derive_shared_secret(public_key)
          # Bitcore uses raw X-coordinate (32 bytes BE), not compressed point
          x_bytes = shared.point.to_octet_string(:uncompressed)[1, 32]
          derived = Digest.sha512(x_bytes)

          key_e = derived[0, 32]
          key_m = derived[32, 32]

          [key_e, key_m]
        end
      end
    end
  end
end
