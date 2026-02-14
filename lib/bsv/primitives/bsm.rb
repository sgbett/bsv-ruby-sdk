# frozen_string_literal: true

module BSV
  module Primitives
    # Bitcoin Signed Messages (BSM).
    #
    # Signs and verifies messages using the standard Bitcoin message signing
    # protocol. Messages are prefixed with +"Bitcoin Signed Message:\n"+,
    # length-prefixed, and double-SHA-256 hashed before signing with
    # recoverable ECDSA. Signatures are 65-byte compact format, base64-encoded.
    #
    # @example Sign and verify a message
    #   key = BSV::Primitives::PrivateKey.generate
    #   sig = BSV::Primitives::BSM.sign('hello', key)
    #   BSV::Primitives::BSM.verify('hello', sig, key.public_key.address) #=> true
    module BSM
      # The standard Bitcoin message signing prefix.
      MAGIC_PREFIX = "Bitcoin Signed Message:\n".b.freeze

      module_function

      # Sign a message with a private key.
      #
      # Produces a 65-byte compact recoverable signature encoded as base64.
      # The flag byte (31-34) indicates compressed P2PKH recovery per BIP-137.
      #
      # @param message [String] the message to sign
      # @param private_key [PrivateKey] the signing key
      # @return [String] base64-encoded compact signature
      def sign(message, private_key)
        hash = magic_hash(message)
        sig, recovery_id = ECDSA.sign_recoverable(hash, private_key.bn)

        # Flag byte: 31-34 = compressed P2PKH (BIP-137)
        flag = 31 + recovery_id
        compact = [flag].pack('C') + bn_to_bytes(sig.r) + bn_to_bytes(sig.s)
        [compact].pack('m0')
      end

      # Verify a signed message against a Bitcoin address.
      #
      # Recovers the public key from the compact signature and checks
      # whether the derived address matches the expected address.
      #
      # @param message [String] the original message
      # @param signature [String] base64-encoded compact signature
      # @param address [String] the expected Bitcoin address
      # @return [Boolean] +true+ if the signature is valid for the given address
      # @raise [ArgumentError] if the signature encoding or flag byte is invalid
      def verify(message, signature, address)
        compact = decode_compact(signature)
        flag = compact.getbyte(0)
        validate_flag!(flag)

        recovery_id = (flag - 27) & 3
        compressed = flag >= 31

        r_bn = OpenSSL::BN.new(compact[1, 32], 2)
        s_bn = OpenSSL::BN.new(compact[33, 32], 2)
        sig = Signature.new(r_bn, s_bn)

        hash = magic_hash(message)
        pub = ECDSA.recover_public_key(hash, sig, recovery_id)

        derived = if compressed
                    pub.address
                  else
                    h160 = Digest.hash160(pub.uncompressed)
                    Base58.check_encode(PublicKey::MAINNET_PUBKEY_HASH + h160)
                  end

        derived == address
      rescue OpenSSL::PKey::EC::Point::Error
        false
      end

      # Compute the double-SHA-256 hash of a Bitcoin-prefixed message.
      #
      # @param message [String] the message to hash
      # @return [String] 32-byte double-SHA-256 digest
      def magic_hash(message)
        message = message.encode('UTF-8') if message.encoding != Encoding::UTF_8
        msg_bytes = message.b
        buf = encode_varint(MAGIC_PREFIX.bytesize) + MAGIC_PREFIX +
              encode_varint(msg_bytes.bytesize) + msg_bytes
        Digest.sha256d(buf)
      end

      class << self
        private

        def bn_to_bytes(bn)
          bytes = bn.to_s(2)
          bytes = ("\x00".b * (32 - bytes.length)) + bytes if bytes.length < 32
          bytes
        end

        def decode_compact(signature)
          compact = signature.unpack1('m0')
          unless compact.bytesize == 65
            raise ArgumentError,
                  "invalid signature length: #{compact.bytesize} (expected 65)"
          end

          compact
        rescue ArgumentError => e
          raise e if e.message.include?('invalid signature length')

          raise ArgumentError, "invalid base64 encoding: #{e.message}"
        end

        def validate_flag!(flag)
          return if flag.between?(27, 34)

          raise ArgumentError,
                "flag byte #{flag} out of range (expected 27-34)"
        end

        def encode_varint(len)
          if len < 0xFD
            [len].pack('C')
          elsif len <= 0xFFFF
            "\xFD".b + [len].pack('v')
          else
            "\xFE".b + [len].pack('V')
          end
        end
      end
    end
  end
end
