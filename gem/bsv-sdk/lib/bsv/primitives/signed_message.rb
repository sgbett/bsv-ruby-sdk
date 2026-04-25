# frozen_string_literal: true

require 'securerandom'

module BSV
  module Primitives
    # BRC-77 signed messages.
    #
    # Provides authenticated messaging using BRC-42 derived signing keys.
    # The sender proves their identity to a specific recipient (or anyone)
    # without encrypting the message content.
    #
    # @example Sign and verify for a specific recipient
    #   sig = SignedMessage.sign(message, sender_priv, recipient_pub)
    #   SignedMessage.verify(message, sig, recipient_priv) #=> true
    #
    # @example Sign for anyone to verify
    #   sig = SignedMessage.sign(message, sender_priv)
    #   SignedMessage.verify(message, sig) #=> true
    #
    # @see https://github.com/bitcoin-sv/BRCs/blob/master/peer-to-peer/0077.md
    module SignedMessage
      # Protocol version bytes: "BB3\x01"
      VERSION = "\x42\x42\x33\x01".b.freeze

      module_function

      # Sign a message using the BRC-77 protocol.
      #
      # @param message [String] the message to sign
      # @param signer [PrivateKey] the sender's private key
      # @param verifier [PublicKey, nil] the recipient's public key (nil for anyone-can-verify)
      # @return [String] binary signed message (version + keys + key_id + DER signature)
      def sign(message, signer, verifier = nil)
        anyone = verifier.nil?
        verifier = PrivateKey.new(OpenSSL::BN.new(1)).public_key if anyone

        key_id = SecureRandom.random_bytes(32)
        invoice = "2-message signing-#{[key_id].pack('m0')}"

        signing_key = signer.derive_child(verifier, invoice)
        hash = Digest.sha256(message.b)
        signature = signing_key.sign(hash)

        VERSION +
          signer.public_key.compressed +
          (anyone ? "\x00".b : verifier.compressed) +
          key_id +
          signature.to_der
      end

      # Verify a BRC-77 signed message.
      #
      # @param message [String] the original message
      # @param sig [String] the binary signature (from {.sign})
      # @param recipient [PrivateKey, nil] the recipient's private key (nil for anyone-can-verify)
      # @return [Boolean] true if the signature is valid
      # @raise [ArgumentError] if the version is wrong, recipient is required but missing, or recipient doesn't match
      def verify(message, sig, recipient = nil)
        sig = sig.b
        raise ArgumentError, "signed message too short: #{sig.bytesize} bytes" if sig.bytesize < 38

        version = sig.byteslice(0, 4)
        raise ArgumentError, "message version mismatch: expected #{VERSION.unpack1('H*')}, received #{version.unpack1('H*')}" if version != VERSION

        sender_pub = PublicKey.from_bytes(sig.byteslice(4, 33))
        verifier_first = sig.getbyte(37)

        if verifier_first.zero?
          # Anyone-can-verify mode
          recipient = PrivateKey.new(OpenSSL::BN.new(1))
          key_id_offset = 38
        else
          # Specific recipient
          verifier_pub_bytes = sig.byteslice(37, 33)

          if recipient.nil?
            raise ArgumentError,
                  'this signature can only be verified with knowledge of a specific private key. ' \
                  "The associated public key is: #{verifier_pub_bytes.unpack1('H*')}"
          end

          recipient_pub_bytes = recipient.public_key.compressed
          if verifier_pub_bytes != recipient_pub_bytes
            raise ArgumentError,
                  "the recipient public key is #{recipient_pub_bytes.unpack1('H*')} " \
                  "but the signature requires the recipient to have public key #{verifier_pub_bytes.unpack1('H*')}"
          end

          key_id_offset = 70
        end

        key_id = sig.byteslice(key_id_offset, 32)
        der_bytes = sig.byteslice(key_id_offset + 32, sig.bytesize - key_id_offset - 32)

        invoice = "2-message signing-#{[key_id].pack('m0')}"
        signing_pub = sender_pub.derive_child(recipient, invoice)

        signature = Signature.from_der(der_bytes)
        hash = Digest.sha256(message.b)
        ECDSA.verify(hash, signature, signing_pub.point)
      end
    end
  end
end
