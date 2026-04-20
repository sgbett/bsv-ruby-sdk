# frozen_string_literal: true

require 'openssl'

module BSV
  module Wallet
    # Cryptographic wallet implementing the 8 key/crypto BRC-100 methods.
    #
    # ProtoWallet handles key derivation, encryption, decryption, HMAC,
    # and signature operations using BRC-42/43 key derivation. Transaction,
    # certificate, blockchain, and authentication methods raise
    # {UnsupportedActionError} via the included {Interface}.
    #
    # @example Encrypt and decrypt a message
    #   wallet = BSV::Wallet::ProtoWallet.new(BSV::Primitives::PrivateKey.generate)
    #   args = { protocol_id: [0, 'hello world'], key_id: '1', counterparty: 'self' }
    #   result = wallet.encrypt(args.merge(plaintext: [104, 101, 108, 108, 111]))
    #   wallet.decrypt(args.merge(ciphertext: result[:ciphertext]))[:plaintext]
    class ProtoWallet
      include Interface

      # @return [KeyDeriver] the underlying key deriver
      attr_reader :key_deriver

      # @param key [BSV::Primitives::PrivateKey, String, KeyDeriver]
      #   A private key, the string +'anyone'+, or a pre-built {KeyDeriver}
      def initialize(key)
        @key_deriver = if key.is_a?(KeyDeriver)
                         key
                       else
                         KeyDeriver.new(key)
                       end
      end

      # Returns a derived or identity public key.
      #
      # When +args[:identity_key]+ is true, returns the wallet's identity key.
      # Otherwise derives a key for the given protocol, key ID, and counterparty.
      #
      # @param args [Hash]
      # @option args [Boolean] :identity_key return the identity key instead of deriving
      # @option args [Array] :protocol_id [security_level, protocol_name]
      # @option args [String] :key_id key identifier
      # @option args [String] :counterparty public key hex, 'self', or 'anyone'
      # @option args [Boolean] :for_self derive from own identity
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { public_key: String } hex-encoded compressed public key
      def get_public_key(args, originator: nil)
        if args[:identity_key]
          { public_key: @key_deriver.identity_key }
        else
          counterparty = args[:counterparty] || 'self'
          pub = @key_deriver.derive_public_key(
            args[:protocol_id],
            args[:key_id],
            counterparty,
            for_self: args[:for_self] || false
          )
          { public_key: pub.to_hex }
        end
      end

      # Encrypts plaintext using AES-256-GCM with a derived symmetric key.
      #
      # @param args [Hash]
      # @option args [Array<Integer>] :plaintext byte array to encrypt
      # @option args [Array] :protocol_id [security_level, protocol_name]
      # @option args [String] :key_id key identifier
      # @option args [String] :counterparty public key hex, 'self', or 'anyone'
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { ciphertext: Array<Integer> }
      def encrypt(args, originator: nil)
        sym_key = derive_sym_key(args)
        ciphertext = sym_key.encrypt(bytes_to_string(args[:plaintext]))
        { ciphertext: string_to_bytes(ciphertext) }
      end

      # Decrypts ciphertext using AES-256-GCM with a derived symmetric key.
      #
      # @param args [Hash]
      # @option args [Array<Integer>] :ciphertext byte array to decrypt
      # @option args [Array] :protocol_id [security_level, protocol_name]
      # @option args [String] :key_id key identifier
      # @option args [String] :counterparty public key hex, 'self', or 'anyone'
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { plaintext: Array<Integer> }
      def decrypt(args, originator: nil)
        sym_key = derive_sym_key(args)
        plaintext = sym_key.decrypt(bytes_to_string(args[:ciphertext]))
        { plaintext: string_to_bytes(plaintext) }
      end

      # Creates an HMAC-SHA256 using a derived symmetric key.
      #
      # @param args [Hash]
      # @option args [Array<Integer>] :data byte array to authenticate
      # @option args [Array] :protocol_id [security_level, protocol_name]
      # @option args [String] :key_id key identifier
      # @option args [String] :counterparty public key hex, 'self', or 'anyone'
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { hmac: Array<Integer> }
      def create_hmac(args, originator: nil)
        sym_key = derive_sym_key(args)
        hmac = BSV::Primitives::Digest.hmac_sha256(sym_key.to_bytes, bytes_to_string(args[:data]))
        { hmac: string_to_bytes(hmac) }
      end

      # Verifies an HMAC-SHA256 using a derived symmetric key.
      #
      # @param args [Hash]
      # @option args [Array<Integer>] :data byte array that was authenticated
      # @option args [Array<Integer>] :hmac HMAC to verify
      # @option args [Array] :protocol_id [security_level, protocol_name]
      # @option args [String] :key_id key identifier
      # @option args [String] :counterparty public key hex, 'self', or 'anyone'
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { valid: true }
      # @raise [InvalidHmacError] if the HMAC does not match
      def verify_hmac(args, originator: nil)
        sym_key = derive_sym_key(args)
        expected = BSV::Primitives::Digest.hmac_sha256(sym_key.to_bytes, bytes_to_string(args[:data]))
        provided = bytes_to_string(args[:hmac])

        raise InvalidHmacError unless secure_compare(expected, provided)

        { valid: true }
      end

      # Creates an ECDSA signature using a derived private key.
      #
      # Either +:data+ or +:hash_to_directly_sign+ must be provided.
      # If +:data+ is given it is SHA-256 hashed before signing.
      # If +:hash_to_directly_sign+ is given it is used as the 32-byte hash directly.
      #
      # @param args [Hash]
      # @option args [Array<Integer>] :data data to hash and sign
      # @option args [Array<Integer>] :hash_to_directly_sign pre-computed 32-byte hash to sign
      # @option args [Array] :protocol_id [security_level, protocol_name]
      # @option args [String] :key_id key identifier
      # @option args [String] :counterparty public key hex, 'self', or 'anyone'
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { signature: Array<Integer> } DER-encoded signature as byte array
      def create_signature(args, originator: nil)
        counterparty = args[:counterparty] || 'anyone'
        priv_key = @key_deriver.derive_private_key(args[:protocol_id], args[:key_id], counterparty)

        hash = if args[:hash_to_directly_sign]
                 bytes_to_string(args[:hash_to_directly_sign])
               else
                 BSV::Primitives::Digest.sha256(bytes_to_string(args[:data]))
               end

        sig = priv_key.sign(hash)
        { signature: string_to_bytes(sig.to_der) }
      end

      # Verifies an ECDSA signature using a derived public key.
      #
      # Either +:data+ or +:hash_to_directly_verify+ must be provided.
      # If +:data+ is given it is SHA-256 hashed before verification.
      #
      # @param args [Hash]
      # @option args [Array<Integer>] :data original data that was signed
      # @option args [Array<Integer>] :hash_to_directly_verify pre-computed 32-byte hash
      # @option args [Array<Integer>] :signature DER-encoded signature as byte array
      # @option args [Array] :protocol_id [security_level, protocol_name]
      # @option args [String] :key_id key identifier
      # @option args [String] :counterparty public key hex, 'self', or 'anyone'
      # @option args [Boolean] :for_self verify own derived key (default false)
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] { valid: true }
      # @raise [InvalidSignatureError] if the signature does not verify
      def verify_signature(args, originator: nil)
        counterparty = args[:counterparty] || 'self'
        for_self = args[:for_self] || false

        pub_key = @key_deriver.derive_public_key(
          args[:protocol_id],
          args[:key_id],
          counterparty,
          for_self: for_self
        )

        hash = if args[:hash_to_directly_verify]
                 bytes_to_string(args[:hash_to_directly_verify])
               else
                 BSV::Primitives::Digest.sha256(bytes_to_string(args[:data]))
               end

        sig = BSV::Primitives::Signature.from_der(bytes_to_string(args[:signature]))
        valid = pub_key.verify(hash, sig)

        raise InvalidSignatureError unless valid

        { valid: true }
      end

      # Reveals counterparty key linkage to a verifier (BRC-69 Method 1).
      #
      # Encrypts the ECDH shared secret between this wallet and the counterparty
      # for the verifier using a BRC-72 protocol-derived key. Also generates a
      # BRC-94 Schnorr zero-knowledge proof of the linkage and encrypts it for
      # the verifier.
      #
      # @param args [Hash]
      # @option args [String] :counterparty counterparty public key hex (not 'self')
      # @option args [String] :verifier verifier public key hex
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] with :prover, :verifier, :counterparty, :revelation_time,
      #   :encrypted_linkage, :encrypted_linkage_proof
      def reveal_counterparty_key_linkage(args, originator: nil)
        counterparty = args[:counterparty]
        verifier = args[:verifier]

        raise InvalidParameterError.new('counterparty', 'a specific public key hex, not "anyone"') if counterparty == 'anyone'

        Validators.validate_pub_key_hex!(verifier, 'verifier')

        linkage = @key_deriver.reveal_counterparty_secret(counterparty)
        revelation_time = Time.now.utc.iso8601

        encrypted_linkage_result = encrypt({
                                             plaintext: string_to_bytes(linkage),
                                             protocol_id: [2, 'counterparty linkage revelation'],
                                             key_id: revelation_time,
                                             counterparty: verifier
                                           })

        counterparty_pub = BSV::Primitives::PublicKey.from_hex(counterparty)
        linkage_point = BSV::Primitives::PublicKey.from_bytes(linkage)
        schnorr_proof = BSV::Primitives::Schnorr.generate_proof(
          @key_deriver.root_key,
          @key_deriver.root_key.public_key,
          counterparty_pub,
          linkage_point
        )

        z_bytes = schnorr_proof.z.to_s(2)
        z_bytes = ("\x00".b * (32 - z_bytes.length)) + z_bytes if z_bytes.length < 32
        proof_bin = schnorr_proof.r.compressed + schnorr_proof.s_prime.compressed + z_bytes

        encrypted_proof_result = encrypt({
                                           plaintext: string_to_bytes(proof_bin),
                                           protocol_id: [2, 'counterparty linkage revelation'],
                                           key_id: revelation_time,
                                           counterparty: verifier
                                         })

        {
          prover: @key_deriver.identity_key,
          verifier: verifier,
          counterparty: counterparty,
          revelation_time: revelation_time,
          encrypted_linkage: encrypted_linkage_result[:ciphertext],
          encrypted_linkage_proof: encrypted_proof_result[:ciphertext]
        }
      end

      # Reveals specific key linkage for a particular interaction (BRC-69 Method 2).
      #
      # Encrypts the HMAC-derived key offset for the given protocol/key combination
      # for the verifier using a BRC-72 protocol-derived key. Proof type 0 means
      # no cryptographic proof is provided (consistent with the ts-sdk behaviour).
      #
      # @param args [Hash]
      # @option args [String] :counterparty counterparty public key hex
      # @option args [String] :verifier verifier public key hex
      # @option args [Array] :protocol_id [security_level, protocol_name]
      # @option args [String] :key_id key identifier
      # @param originator [String, nil] FQDN of the originating application
      # @return [Hash] with :prover, :verifier, :counterparty, :protocol_id, :key_id,
      #   :encrypted_linkage, :encrypted_linkage_proof, :proof_type
      def reveal_specific_key_linkage(args, originator: nil)
        counterparty = args[:counterparty]
        verifier = args[:verifier]
        protocol_id = args[:protocol_id]
        key_id = args[:key_id]

        raise InvalidParameterError.new('counterparty', 'a specific public key hex, not "anyone"') if counterparty == 'anyone'

        Validators.validate_pub_key_hex!(verifier, 'verifier')

        linkage = @key_deriver.reveal_specific_secret(counterparty, protocol_id, key_id)

        derived_protocol = "specific linkage revelation #{protocol_id[0]} #{protocol_id[1]}"

        encrypted_linkage_result = encrypt({
                                             plaintext: string_to_bytes(linkage),
                                             protocol_id: [2, derived_protocol],
                                             key_id: key_id,
                                             counterparty: verifier
                                           })

        encrypted_proof_result = encrypt({
                                           plaintext: [0],
                                           protocol_id: [2, derived_protocol],
                                           key_id: key_id,
                                           counterparty: verifier
                                         })

        {
          prover: @key_deriver.identity_key,
          verifier: verifier,
          counterparty: counterparty,
          protocol_id: protocol_id,
          key_id: key_id,
          encrypted_linkage: encrypted_linkage_result[:ciphertext],
          encrypted_linkage_proof: encrypted_proof_result[:ciphertext],
          proof_type: 0
        }
      end

      private

      # Derives a symmetric key from the args hash.
      #
      # @param args [Hash] must contain :protocol_id, :key_id; :counterparty defaults to 'self'
      # @return [BSV::Primitives::SymmetricKey]
      def derive_sym_key(args)
        counterparty = args[:counterparty] || 'self'
        @key_deriver.derive_symmetric_key(args[:protocol_id], args[:key_id], counterparty)
      end

      # Converts a byte array (Array of Integers 0..255) to a binary string.
      #
      # @param bytes [Array<Integer>] byte array
      # @return [String] binary string
      def bytes_to_string(bytes)
        bytes.pack('C*')
      end

      # Converts a binary string to a byte array (Array of Integers 0..255).
      #
      # @param str [String] binary string
      # @return [Array<Integer>] byte array
      def string_to_bytes(str)
        str.unpack('C*')
      end

      # Constant-time string comparison to prevent timing attacks.
      #
      # Falls back to a manual XOR loop on platforms where
      # +OpenSSL.fixed_length_secure_compare+ is unavailable.
      #
      # @param a [String] first binary string
      # @param b [String] second binary string
      # @return [Boolean]
      def secure_compare(a, b)
        return false unless a.bytesize == b.bytesize

        if OpenSSL.respond_to?(:fixed_length_secure_compare)
          OpenSSL.fixed_length_secure_compare(a, b)
        else
          result = 0
          a.bytes.zip(b.bytes) { |x, y| result |= x ^ y }
          result.zero?
        end
      end
    end
  end
end
