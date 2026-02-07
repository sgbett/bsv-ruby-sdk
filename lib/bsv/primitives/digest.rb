# frozen_string_literal: true

require 'openssl'

module BSV
  module Primitives
    module Digest
      module_function

      def sha256(data)
        OpenSSL::Digest::SHA256.digest(data)
      end

      def sha256d(data)
        sha256(sha256(data))
      end

      def sha512(data)
        OpenSSL::Digest::SHA512.digest(data)
      end

      def ripemd160(data)
        OpenSSL::Digest::RIPEMD160.digest(data)
      end

      def hash160(data)
        ripemd160(sha256(data))
      end

      def hmac_sha256(key, data)
        OpenSSL::HMAC.digest('SHA256', key, data)
      end

      def hmac_sha512(key, data)
        OpenSSL::HMAC.digest('SHA512', key, data)
      end
    end
  end
end
