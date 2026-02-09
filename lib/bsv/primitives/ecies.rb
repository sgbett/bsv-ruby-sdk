# frozen_string_literal: true

require 'openssl'

module BSV
  module Primitives
    module ECIES
      MAGIC = 'BIE1'.b.freeze

      class DecryptionError < StandardError; end

      module_function

      def encrypt(message, public_key, private_key: nil)
        message = message.b if message.encoding != Encoding::ASCII_8BIT

        ephemeral = private_key || PrivateKey.generate
        ephemeral_pub = ephemeral.public_key

        iv, key_e, key_m = derive_keys(public_key.point, ephemeral.bn)

        cipher = OpenSSL::Cipher.new('aes-128-cbc')
        cipher.encrypt
        cipher.key = key_e
        cipher.iv = iv
        ciphertext = message.empty? ? cipher.final : cipher.update(message) + cipher.final

        payload = MAGIC + ephemeral_pub.compressed + ciphertext
        mac = Digest.hmac_sha256(key_m, payload)

        payload + mac
      end

      def decrypt(data, private_key)
        data = data.b if data.encoding != Encoding::ASCII_8BIT

        raise ArgumentError, 'data too short' if data.bytesize < 85

        magic = data[0, 4]
        raise ArgumentError, 'invalid magic: expected BIE1' unless magic == MAGIC

        ephemeral_pub_bytes = data[4, 33]
        mac = data[-32, 32]
        ciphertext = data[37...-32]

        ephemeral_pub = PublicKey.from_bytes(ephemeral_pub_bytes)

        iv, key_e, key_m = derive_keys(ephemeral_pub.point, private_key.bn)

        # Verify HMAC before decryption (encrypt-then-MAC)
        payload = data[0...-32]
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

        def derive_keys(point, scalar_bn)
          shared_point = Curve.multiply_point(point, scalar_bn)
          ecdh_key = shared_point.to_octet_string(:compressed)
          derived = Digest.sha512(ecdh_key)

          iv    = derived[0, 16]
          key_e = derived[16, 16]
          key_m = derived[32, 32]

          [iv, key_e, key_m]
        end
      end
    end
  end
end
