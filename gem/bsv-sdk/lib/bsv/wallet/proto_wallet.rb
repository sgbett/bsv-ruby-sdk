# frozen_string_literal: true

require 'openssl'
require_relative 'proto_wallet/validators'
require_relative 'proto_wallet/key_deriver'

module BSV
  module Wallet
    # Minimal cryptographic wallet implementing the BRC-100 interface.
    #
    # ProtoWallet is a direct, in-process implementation of the BRC-100 crypto
    # operations. It requires no external gem, no storage, and no blockchain
    # access — making it suitable for use inside the SDK itself (e.g. the Auth
    # module) as well as lightweight applications that need cryptographic
    # operations without full wallet infrastructure.
    #
    # == Supported BRC-100 areas
    #
    # - *Public key management* — {#get_public_key}, {#reveal_counterparty_key_linkage},
    #   {#reveal_specific_key_linkage}
    # - *Cryptography* — {#encrypt}, {#decrypt}, {#create_hmac}, {#verify_hmac},
    #   {#create_signature}, {#verify_signature}
    # - *Certificates (read-only stub)* — {#list_certificates} returns an empty list;
    #   {#prove_certificate} raises {UnsupportedActionError}
    #
    # == NOT supported
    #
    # The following BRC-100 areas are not implemented and will raise
    # +NotImplementedError+:
    #
    # - Transactions (+create_action+, +sign_action+, +list_actions+, etc.)
    # - Output management (+list_outputs+, +relinquish_output+, etc.)
    # - Authentication (+authenticated?+, +wait_for_authentication+)
    # - Blockchain / network data (+get_height+, +get_header_for_height+, etc.)
    # - Certificate acquisition / discovery (+acquire_certificate+,
    #   +discover_by_identity_key+, etc.)
    #
    # For full wallet functionality, use the +bsv-wallet+ gem. See
    # +docs/sdk/wallet.md+ for usage guidance.
    #
    # == Construction
    #
    # Pass a {BSV::Primitives::PrivateKey} or the special string <tt>'anyone'</tt>.
    # The <tt>'anyone'</tt> variant uses a well-known key (private key = 1) and is
    # suitable for verifying or encrypting data that should be readable by
    # any party — it must not be used where secrecy is required.
    #
    # @example Normal usage
    #   wallet = BSV::Wallet::ProtoWallet.new(BSV::Primitives::PrivateKey.generate)
    #   sig = wallet.create_signature(protocol_id: [1, 'my-app'], key_id: 'msg-1',
    #                                 data: 'hello'.bytes)
    #
    # @example Anyone wallet
    #   wallet = BSV::Wallet::ProtoWallet.new('anyone')
    #   pub = wallet.get_public_key(identity_key: true)
    #
    class ProtoWallet
      include Interface::BRC100

      # @param root_key [BSV::Primitives::PrivateKey, String] a private key or 'anyone'
      def initialize(root_key)
        @key_deriver = KeyDeriver.new(root_key)
      end

      # Returns a derived or identity public key.
      #
      # @param identity_key [Boolean] return the root identity key
      # @param protocol_id [Array] [security_level, protocol_name]
      # @param key_id [String] key identifier
      # @param counterparty [String] pubkey hex, 'self', or 'anyone'
      # @param for_self [Boolean] derive from own identity
      # @return [Hash] { public_key: String } hex-encoded compressed public key
      def get_public_key(identity_key: false, protocol_id: nil, key_id: nil,
                         counterparty: nil, for_self: false,
                         privileged: false, privileged_reason: nil,
                         seek_permission: true, originator: nil)
        if identity_key
          { public_key: @key_deriver.identity_key }
        else
          counterparty ||= 'self'
          pub = @key_deriver.derive_public_key(
            protocol_id, key_id, counterparty, for_self: for_self
          )
          { public_key: pub.to_hex }
        end
      end

      # Encrypts plaintext using AES-256-GCM with a derived symmetric key.
      #
      # @param plaintext [Array<Integer>] byte array to encrypt
      # @param protocol_id [Array] [security_level, protocol_name]
      # @param key_id [String] key identifier
      # @param counterparty [String] pubkey hex, 'self', or 'anyone'
      # @return [Hash] { ciphertext: Array<Integer> }
      def encrypt(plaintext:, protocol_id:, key_id:,
                  counterparty: nil, privileged: false, privileged_reason: nil,
                  seek_permission: true, originator: nil)
        sym_key    = derive_sym_key(protocol_id, key_id, counterparty)
        ciphertext = sym_key.encrypt(bytes_to_string(plaintext))
        { ciphertext: string_to_bytes(ciphertext) }
      end

      # Decrypts ciphertext using AES-256-GCM with a derived symmetric key.
      #
      # @param ciphertext [Array<Integer>] byte array to decrypt
      # @param protocol_id [Array] [security_level, protocol_name]
      # @param key_id [String] key identifier
      # @param counterparty [String] pubkey hex, 'self', or 'anyone'
      # @return [Hash] { plaintext: Array<Integer> }
      def decrypt(ciphertext:, protocol_id:, key_id:,
                  counterparty: nil, privileged: false, privileged_reason: nil,
                  seek_permission: true, originator: nil)
        sym_key   = derive_sym_key(protocol_id, key_id, counterparty)
        plaintext = sym_key.decrypt(bytes_to_string(ciphertext))
        { plaintext: string_to_bytes(plaintext) }
      end

      # Creates an HMAC-SHA256 using a derived symmetric key.
      #
      # @param data [Array<Integer>] byte array to authenticate
      # @param protocol_id [Array] [security_level, protocol_name]
      # @param key_id [String] key identifier
      # @param counterparty [String] pubkey hex, 'self', or 'anyone'
      # @return [Hash] { hmac: Array<Integer> }
      def create_hmac(data:, protocol_id:, key_id:,
                      counterparty: nil, privileged: false, privileged_reason: nil,
                      seek_permission: true, originator: nil)
        sym_key = derive_sym_key(protocol_id, key_id, counterparty)
        hmac    = BSV::Primitives::Digest.hmac_sha256(sym_key.to_bytes, bytes_to_string(data))
        { hmac: string_to_bytes(hmac) }
      end

      # Verifies an HMAC-SHA256 using a derived symmetric key.
      #
      # @param data [Array<Integer>] byte array that was authenticated
      # @param hmac [Array<Integer>] HMAC to verify
      # @param protocol_id [Array] [security_level, protocol_name]
      # @param key_id [String] key identifier
      # @param counterparty [String] pubkey hex, 'self', or 'anyone'
      # @return [Hash] { valid: true }
      # @raise [InvalidHmacError] if the HMAC does not match
      def verify_hmac(data:, hmac:, protocol_id:, key_id:,
                      counterparty: nil, privileged: false, privileged_reason: nil,
                      seek_permission: true, originator: nil)
        sym_key  = derive_sym_key(protocol_id, key_id, counterparty)
        expected = BSV::Primitives::Digest.hmac_sha256(sym_key.to_bytes, bytes_to_string(data))
        provided = bytes_to_string(hmac)

        raise InvalidHmacError unless secure_compare(expected, provided)

        { valid: true }
      end

      # Creates an ECDSA signature using a derived private key.
      #
      # @param protocol_id [Array] [security_level, protocol_name]
      # @param key_id [String] key identifier
      # @param data [Array<Integer>] data to hash and sign
      # @param hash_to_directly_sign [Array<Integer>] pre-computed 32-byte hash
      # @param counterparty [String] pubkey hex, 'self', or 'anyone'
      # @return [Hash] { signature: Array<Integer> } DER-encoded signature as byte array
      def create_signature(protocol_id:, key_id:, data: nil, hash_to_directly_sign: nil,
                           counterparty: nil, privileged: false, privileged_reason: nil,
                           seek_permission: true, originator: nil)
        counterparty ||= 'anyone'
        BSV.logger&.debug { "[ProtoWallet] create_signature: protocol=#{protocol_id} key_id=#{key_id.inspect} counterparty=#{counterparty}" }
        priv_key = @key_deriver.derive_private_key(protocol_id, key_id, counterparty)

        hash = if hash_to_directly_sign
                 bytes_to_string(hash_to_directly_sign)
               else
                 BSV::Primitives::Digest.sha256(bytes_to_string(data))
               end

        sig = priv_key.sign(hash)
        { signature: string_to_bytes(sig.to_der) }
      end

      # Verifies an ECDSA signature using a derived public key.
      #
      # @param signature [Array<Integer>] DER-encoded signature as byte array
      # @param protocol_id [Array] [security_level, protocol_name]
      # @param key_id [String] key identifier
      # @param data [Array<Integer>] original data that was signed
      # @param hash_to_directly_verify [Array<Integer>] pre-computed 32-byte hash
      # @param counterparty [String] pubkey hex, 'self', or 'anyone'
      # @param for_self [Boolean] verify own derived key (default false)
      # @return [Hash] { valid: true }
      # @raise [InvalidSignatureError] if the signature does not verify
      def verify_signature(signature:, protocol_id:, key_id:, data: nil,
                           hash_to_directly_verify: nil,
                           counterparty: nil, for_self: false,
                           privileged: false, privileged_reason: nil,
                           seek_permission: true, originator: nil)
        counterparty ||= 'self'
        BSV.logger&.debug do
          "[ProtoWallet] verify_signature: protocol=#{protocol_id} key_id=#{key_id.inspect} " \
            "counterparty=#{counterparty} for_self=#{for_self}"
        end

        pub_key = @key_deriver.derive_public_key(
          protocol_id, key_id, counterparty, for_self: for_self
        )

        hash = if hash_to_directly_verify
                 bytes_to_string(hash_to_directly_verify)
               else
                 BSV::Primitives::Digest.sha256(bytes_to_string(data))
               end

        sig   = BSV::Primitives::Signature.from_der(bytes_to_string(signature))
        valid = pub_key.verify(hash, sig)
        BSV.logger&.debug { "[ProtoWallet] verify_signature result=#{valid}" }

        raise InvalidSignatureError unless valid

        { valid: true }
      end

      # Reveals counterparty key linkage to a verifier (BRC-69 Method 1).
      #
      # @param counterparty [String] counterparty public key hex (not 'self' or 'anyone')
      # @param verifier [String] verifier public key hex
      # @return [Hash] { prover:, verifier:, counterparty:, revelation_time:,
      #   encrypted_linkage:, encrypted_linkage_proof: }
      def reveal_counterparty_key_linkage(counterparty:, verifier:,
                                          privileged: false, privileged_reason: nil,
                                          originator: nil)
        raise InvalidParameterError.new('counterparty', 'a specific public key hex, not "anyone"') if counterparty == 'anyone'

        Validators.validate_pub_key_hex!(verifier, 'verifier')

        linkage         = @key_deriver.reveal_counterparty_secret(counterparty)
        revelation_time = Time.now.utc.iso8601

        encrypted_linkage_result = encrypt(
          plaintext: string_to_bytes(linkage),
          protocol_id: [2, 'counterparty linkage revelation'],
          key_id: revelation_time,
          counterparty: verifier
        )

        counterparty_pub = BSV::Primitives::PublicKey.from_hex(counterparty)
        linkage_point    = BSV::Primitives::PublicKey.from_bytes(linkage)
        schnorr_proof    = BSV::Primitives::Schnorr.generate_proof(
          @key_deriver.root_key,
          @key_deriver.root_key.public_key,
          counterparty_pub,
          linkage_point
        )

        z_bytes = schnorr_proof.z.to_s(2)
        z_bytes = ("\x00".b * (32 - z_bytes.length)) + z_bytes if z_bytes.length < 32
        proof_bin = schnorr_proof.r.compressed + schnorr_proof.s_prime.compressed + z_bytes

        encrypted_proof_result = encrypt(
          plaintext: string_to_bytes(proof_bin),
          protocol_id: [2, 'counterparty linkage revelation'],
          key_id: revelation_time,
          counterparty: verifier
        )

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
      # @param counterparty [String] counterparty public key hex
      # @param verifier [String] verifier public key hex
      # @param protocol_id [Array] [security_level, protocol_name]
      # @param key_id [String] key identifier
      # @return [Hash] { prover:, verifier:, counterparty:, protocol_id:, key_id:,
      #   encrypted_linkage:, encrypted_linkage_proof:, proof_type: }
      def reveal_specific_key_linkage(counterparty:, verifier:, protocol_id:, key_id:,
                                      privileged: false, privileged_reason: nil,
                                      originator: nil)
        raise InvalidParameterError.new('counterparty', 'a specific public key hex, not "anyone"') if counterparty == 'anyone'

        Validators.validate_pub_key_hex!(verifier, 'verifier')

        linkage          = @key_deriver.reveal_specific_secret(counterparty, protocol_id, key_id)
        derived_protocol = "specific linkage revelation #{protocol_id[0]} #{protocol_id[1]}"

        encrypted_linkage_result = encrypt(
          plaintext: string_to_bytes(linkage),
          protocol_id: [2, derived_protocol],
          key_id: key_id,
          counterparty: verifier
        )

        encrypted_proof_result = encrypt(
          plaintext: [0],
          protocol_id: [2, derived_protocol],
          key_id: key_id,
          counterparty: verifier
        )

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

      # Returns an empty certificate list.
      #
      # ProtoWallet has no storage, so there are never any certificates.
      #
      # @return [Hash] { certificates: [] }
      def list_certificates(certifiers: nil, types: nil, limit: 10, offset: 0,
                            privileged: false, privileged_reason: nil, originator: nil)
        { certificates: [] }
      end

      # Not supported — ProtoWallet has no certificate storage.
      #
      # @raise [UnsupportedActionError] always
      def prove_certificate(certificate: nil, fields_to_reveal: nil, verifier: nil,
                            privileged: false, privileged_reason: nil, originator: nil)
        raise UnsupportedActionError, 'prove_certificate'
      end

      private

      def derive_sym_key(protocol_id, key_id, counterparty)
        counterparty ||= 'self'
        @key_deriver.derive_symmetric_key(protocol_id, key_id, counterparty)
      end

      def bytes_to_string(bytes)
        bytes.pack('C*')
      end

      def string_to_bytes(str)
        str.unpack('C*')
      end

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
