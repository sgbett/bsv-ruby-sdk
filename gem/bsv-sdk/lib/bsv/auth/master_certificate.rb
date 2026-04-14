# frozen_string_literal: true

require 'base64'
require 'securerandom'

module BSV
  module Auth
    # A Certificate subclass that manages a master keyring for certificate issuance
    # and selective field disclosure.
    #
    # MasterCertificate adds a +master_keyring+ to the base Certificate. The master
    # keyring maps each field name to a Base64-encoded encrypted symmetric key that
    # was used to encrypt that field's value. This allows the certificate holder to:
    #
    # 1. Decrypt all fields via {.decrypt_fields}.
    # 2. Re-encrypt individual field keys for a specific verifier via
    #    {.create_keyring_for_verifier}, producing a {VerifiableCertificate}.
    #
    # == Protocol details
    #
    # Field encryption uses BRC-42 key derivation:
    #
    # - Protocol:    +[2, 'certificate field encryption']+
    # - Master key ID (no serial):  +field_name+
    # - Verifier key ID (with serial): +"#{serial_number} #{field_name}"+
    #
    # Wallet parameters are duck-typed — any object responding to +:encrypt+,
    # +:decrypt+, and +:get_public_key+ is accepted.
    #
    # @see BSV::Auth::Certificate  base class
    # @see BSV::Auth::VerifiableCertificate  consumer of verifier keyrings
    class MasterCertificate < Certificate
      # @return [Hash] mapping field names to Base64-encoded encrypted symmetric keys
      attr_reader :master_keyring

      # @param type [String] Base64 string (32 bytes decoded)
      # @param serial_number [String] Base64 string (32 bytes decoded)
      # @param subject [String] compressed public key hex
      # @param certifier [String] compressed public key hex
      # @param revocation_outpoint [String] +"<txid_hex>.<output_index>"+
      # @param fields [Hash] field name strings to encrypted value strings (Base64)
      # @param master_keyring [Hash] field name strings to Base64-encoded encrypted symmetric keys
      # @param signature [String, nil] DER-encoded signature hex, or nil
      # @raise [ArgumentError] if any field in +fields+ is missing from +master_keyring+
      def initialize(type:, serial_number:, subject:, certifier:, revocation_outpoint:,
                     fields:, master_keyring:, signature: nil)
        super(
          type: type,
          serial_number: serial_number,
          subject: subject,
          certifier: certifier,
          revocation_outpoint: revocation_outpoint,
          fields: fields,
          signature: signature
        )

        fields.each_key do |field_name|
          entry = master_keyring[field_name]
          next unless entry.nil? || entry.empty?

          raise ArgumentError,
                'Master keyring must contain a value for every field. ' \
                "Missing or empty key for field: \"#{field_name}\"."
        end

        @master_keyring = master_keyring
      end

      # Return the certificate as a plain Hash with snake_case keys, including
      # +master_keyring+.
      #
      # @return [Hash]
      def to_h
        super.merge('master_keyring' => @master_keyring.dup)
      end

      # Construct a MasterCertificate from a plain Hash.
      #
      # Accepts both snake_case and camelCase key variants.
      #
      # @param hash [Hash] certificate data
      # @return [MasterCertificate]
      def self.from_hash(hash)
        h = normalise_hash_keys(hash)
        master_keyring = h['master_keyring'] || {}
        new(
          type: h['type'],
          serial_number: h['serial_number'],
          subject: h['subject'],
          certifier: h['certifier'],
          revocation_outpoint: h['revocation_outpoint'],
          fields: h['fields'] || {},
          master_keyring: master_keyring,
          signature: h['signature']
        )
      end

      # Encrypts certificate fields and generates a master keyring.
      #
      # For each field:
      # 1. Generates a random {BSV::Primitives::SymmetricKey}.
      # 2. Encrypts the field value with that key.
      # 3. Encrypts the symmetric key bytes for +certifier_or_subject+ using
      #    BRC-42 with key_id = +field_name+ (no serial number).
      #
      # @param creator_wallet [#encrypt] wallet used to encrypt field keys
      # @param certifier_or_subject [String] counterparty pubkey hex, +'self'+,
      #   or +'anyone'+ — the party who will later decrypt the master keyring
      # @param fields [Hash] plain-text field name → plain-text field value
      # @param privileged [Boolean] whether this is a privileged operation
      # @param privileged_reason [String, nil] reason for privileged access
      # @return [Hash] +{ certificate_fields: Hash, master_keyring: Hash }+
      def self.create_certificate_fields(creator_wallet, certifier_or_subject, fields,
                                         privileged: false, privileged_reason: nil)
        certificate_fields = {}
        master_keyring = {}

        fields.each do |field_name, field_value|
          sym_key = BSV::Primitives::SymmetricKey.from_random

          encrypted_value = sym_key.encrypt(field_value.encode('UTF-8'))
          certificate_fields[field_name] = Base64.strict_encode64(encrypted_value)

          enc_args = {
            plaintext: sym_key.to_bytes.bytes,
            counterparty: certifier_or_subject,
            privileged: privileged,
            privileged_reason: privileged_reason
          }.merge(Certificate.certificate_field_encryption_details(field_name))

          result = creator_wallet.encrypt(enc_args)
          master_keyring[field_name] = Base64.strict_encode64(result[:ciphertext].pack('C*'))
        end

        { certificate_fields: certificate_fields, master_keyring: master_keyring }
      end

      # Creates a verifier-specific keyring for selective field disclosure.
      #
      # For each field in +fields_to_reveal+:
      # 1. Decrypts the master symmetric key (counterparty = certifier, key_id = field_name only).
      # 2. Verifies the decrypted key actually decrypts the field value.
      # 3. Re-encrypts the key for the verifier with key_id = +"#{serial_number} #{field_name}"+.
      #
      # The resulting keyring is suitable for constructing a {VerifiableCertificate}.
      #
      # @param subject_wallet [#encrypt, #decrypt] subject's wallet
      # @param certifier [String] certifier pubkey hex, +'self'+, or +'anyone'+
      # @param verifier [String] verifier pubkey hex, +'self'+, or +'anyone'+
      # @param fields [Hash] field name → encrypted field value (Base64)
      # @param fields_to_reveal [Array<String>] subset of field names to expose
      # @param master_keyring [Hash] field name → Base64 encrypted symmetric key
      # @param serial_number [String] certificate serial number (Base64)
      # @param privileged [Boolean] whether this is a privileged operation
      # @param privileged_reason [String, nil] reason for privileged access
      # @return [Hash] field name → Base64 encrypted key (verifier-specific)
      # @raise [ArgumentError] if +fields_to_reveal+ is not an Array
      # @raise [ArgumentError] if a field to reveal does not exist in +fields+
      def self.create_keyring_for_verifier(subject_wallet, certifier:, verifier:, fields:,
                                           fields_to_reveal:, master_keyring:, serial_number:,
                                           privileged: false, privileged_reason: nil)
        raise ArgumentError, 'fields_to_reveal must be an array of strings' unless fields_to_reveal.is_a?(Array)

        keyring = {}

        fields_to_reveal.each do |field_name|
          unless fields.key?(field_name) && !fields[field_name].to_s.empty?
            raise ArgumentError,
                  'Fields to reveal must be a subset of the certificate fields. ' \
                  "Missing the \"#{field_name}\" field."
          end

          master_field_key = decrypt_field(
            subject_wallet,
            master_keyring,
            field_name,
            fields[field_name],
            certifier,
            privileged: privileged,
            privileged_reason: privileged_reason
          )[:field_revelation_key]

          enc_args = {
            plaintext: master_field_key,
            counterparty: verifier,
            privileged: privileged,
            privileged_reason: privileged_reason
          }.merge(Certificate.certificate_field_encryption_details(field_name, serial_number))

          result = subject_wallet.encrypt(enc_args)
          keyring[field_name] = Base64.strict_encode64(result[:ciphertext].pack('C*'))
        end

        keyring
      end

      # Issues a signed MasterCertificate for a subject.
      #
      # 1. Generates a random 32-byte serial_number if none provided.
      # 2. Calls {.create_certificate_fields} to encrypt fields and build the master keyring.
      # 3. Resolves +'self'+ subject to the certifier's identity key.
      # 4. Obtains a revocation outpoint (via callback or default placeholder).
      # 5. Constructs and signs the MasterCertificate.
      #
      # @param certifier_wallet [#encrypt, #create_signature, #get_public_key] certifier's wallet
      # @param subject [String] subject pubkey hex, +'self'+, or +'anyone'+
      # @param fields [Hash] plain-text field name → plain-text field value
      # @param certificate_type [String] Base64-encoded type (32 bytes decoded)
      # @param get_revocation_outpoint [Proc, nil] called with serial_number; returns outpoint string
      # @param serial_number [String, nil] custom serial_number (Base64); randomly generated if nil
      # @return [MasterCertificate] signed certificate
      def self.issue_certificate_for_subject(certifier_wallet, subject, fields, certificate_type,
                                             get_revocation_outpoint: nil, serial_number: nil)
        final_serial = serial_number || Base64.strict_encode64(SecureRandom.random_bytes(32))

        result = create_certificate_fields(certifier_wallet, subject, fields)
        certificate_fields = result[:certificate_fields]
        keyring = result[:master_keyring]

        subject_key = if subject == 'self'
                        certifier_wallet.get_public_key({ identity_key: true })[:public_key]
                      else
                        subject
                      end

        revocation_outpoint = if get_revocation_outpoint
                                get_revocation_outpoint.call(final_serial)
                              else
                                "#{'00' * 32}.0"
                              end

        certifier_key = certifier_wallet.get_public_key({ identity_key: true })[:public_key]

        cert = new(
          type: certificate_type,
          serial_number: final_serial,
          subject: subject_key,
          certifier: certifier_key,
          revocation_outpoint: revocation_outpoint,
          fields: certificate_fields,
          master_keyring: keyring
        )

        cert.sign(certifier_wallet)
        cert
      end

      # Decrypts all fields in the certificate using a master keyring.
      #
      # @param wallet [#decrypt] subject's or certifier's wallet
      # @param master_keyring [Hash] field name → Base64 encrypted symmetric key
      # @param fields [Hash] field name → Base64 encrypted field value
      # @param counterparty [String] pubkey hex, +'self'+, or +'anyone'+
      # @param privileged [Boolean] whether this is a privileged operation
      # @param privileged_reason [String, nil] reason for privileged access
      # @return [Hash] field name → decrypted plaintext string
      # @raise [ArgumentError] if +master_keyring+ is nil or empty
      # @raise [RuntimeError] if decryption fails for any field
      def self.decrypt_fields(wallet, master_keyring, fields, counterparty,
                              privileged: false, privileged_reason: nil)
        raise ArgumentError, 'A MasterCertificate must have a valid masterKeyring!' if master_keyring.nil? || master_keyring.empty?

        begin
          decrypted = {}
          fields.each_key do |field_name|
            decrypted[field_name] = decrypt_field(
              wallet,
              master_keyring,
              field_name,
              fields[field_name],
              counterparty,
              privileged: privileged,
              privileged_reason: privileged_reason
            )[:decrypted_field_value]
          end
          decrypted
        rescue ArgumentError
          raise
        rescue StandardError
          raise 'Failed to decrypt all master certificate fields.'
        end
      end

      # Decrypts a single certificate field.
      #
      # 1. Decrypts the encrypted symmetric key from +master_keyring+ for +field_name+.
      # 2. Uses the decrypted key bytes as a {BSV::Primitives::SymmetricKey}.
      # 3. Decrypts the field value and returns both the key and plaintext.
      #
      # @param wallet [#decrypt] subject's or certifier's wallet
      # @param master_keyring [Hash] field name → Base64 encrypted symmetric key
      # @param field_name [String] name of the field to decrypt
      # @param field_value [String] Base64-encoded encrypted field value
      # @param counterparty [String] pubkey hex, +'self'+, or +'anyone'+
      # @param privileged [Boolean] whether this is a privileged operation
      # @param privileged_reason [String, nil] reason for privileged access
      # @return [Hash] +{ field_revelation_key: Array<Integer>, decrypted_field_value: String }+
      # @raise [ArgumentError] if +master_keyring+ is nil or empty
      # @raise [RuntimeError] if decryption fails
      def self.decrypt_field(wallet, master_keyring, field_name, field_value, counterparty,
                             privileged: false, privileged_reason: nil)
        raise ArgumentError, 'A MasterCertificate must have a valid masterKeyring!' if master_keyring.nil? || master_keyring.empty?

        begin
          dec_args = {
            ciphertext: Base64.strict_decode64(master_keyring[field_name]).bytes,
            counterparty: counterparty,
            privileged: privileged,
            privileged_reason: privileged_reason
          }.merge(Certificate.certificate_field_encryption_details(field_name))

          field_revelation_key = wallet.decrypt(dec_args)[:plaintext]

          sym_key = BSV::Primitives::SymmetricKey.new(field_revelation_key.pack('C*'))
          decrypted_bytes = sym_key.decrypt(Base64.strict_decode64(field_value))
          decrypted_field_value = decrypted_bytes.force_encoding('UTF-8')

          { field_revelation_key: field_revelation_key, decrypted_field_value: decrypted_field_value }
        rescue ArgumentError
          raise
        rescue StandardError
          raise 'Failed to decrypt certificate field!'
        end
      end

      private_class_method def self.normalise_hash_keys(hash)
        result = super
        %w[master_keyring masterKeyring].each do |k|
          result['master_keyring'] ||= hash[k] || hash[k.to_sym]
        end
        result
      end
    end
  end
end
