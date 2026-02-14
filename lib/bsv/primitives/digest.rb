# frozen_string_literal: true

require 'openssl'

module BSV
  module Primitives
    # Cryptographic hash functions and HMAC operations.
    #
    # Thin wrappers around +OpenSSL::Digest+ and +OpenSSL::HMAC+ providing
    # the hash algorithms used throughout the BSV protocol: SHA-1, SHA-256,
    # double-SHA-256, SHA-512, RIPEMD-160, Hash160, HMAC, and PBKDF2.
    module Digest
      module_function

      # Compute SHA-1 digest.
      #
      # @param data [String] binary data to hash
      # @return [String] 20-byte digest
      def sha1(data)
        OpenSSL::Digest::SHA1.digest(data)
      end

      # Compute SHA-256 digest.
      #
      # @param data [String] binary data to hash
      # @return [String] 32-byte digest
      def sha256(data)
        OpenSSL::Digest::SHA256.digest(data)
      end

      # Compute double-SHA-256 (SHA-256d) digest.
      #
      # Used extensively in Bitcoin for transaction and block hashing.
      #
      # @param data [String] binary data to hash
      # @return [String] 32-byte digest
      def sha256d(data)
        sha256(sha256(data))
      end

      # Compute SHA-512 digest.
      #
      # @param data [String] binary data to hash
      # @return [String] 64-byte digest
      def sha512(data)
        OpenSSL::Digest::SHA512.digest(data)
      end

      # Compute RIPEMD-160 digest.
      #
      # @param data [String] binary data to hash
      # @return [String] 20-byte digest
      def ripemd160(data)
        OpenSSL::Digest::RIPEMD160.digest(data)
      end

      # Compute Hash160: RIPEMD-160(SHA-256(data)).
      #
      # Standard Bitcoin hash used for addresses and P2PKH script matching.
      #
      # @param data [String] binary data to hash
      # @return [String] 20-byte digest
      def hash160(data)
        ripemd160(sha256(data))
      end

      # Compute HMAC-SHA-256.
      #
      # @param key [String] HMAC key
      # @param data [String] data to authenticate
      # @return [String] 32-byte MAC
      def hmac_sha256(key, data)
        OpenSSL::HMAC.digest('SHA256', key, data)
      end

      # Compute HMAC-SHA-512.
      #
      # @param key [String] HMAC key
      # @param data [String] data to authenticate
      # @return [String] 64-byte MAC
      def hmac_sha512(key, data)
        OpenSSL::HMAC.digest('SHA512', key, data)
      end

      # Derive a key using PBKDF2-HMAC-SHA-512.
      #
      # Used by BIP-39 to convert mnemonic phrases into seeds.
      #
      # @param password [String] the password (mnemonic phrase)
      # @param salt [String] the salt (+"mnemonic"+ + passphrase)
      # @param iterations [Integer] iteration count (default: 2048 per BIP-39)
      # @param key_length [Integer] desired output length in bytes (default: 64)
      # @return [String] derived key bytes
      def pbkdf2_hmac_sha512(password, salt, iterations: 2048, key_length: 64)
        OpenSSL::PKCS5.pbkdf2_hmac(password, salt, iterations, key_length, 'sha512')
      end
    end
  end
end
