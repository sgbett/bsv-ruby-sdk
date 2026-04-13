# frozen_string_literal: true

require 'base64'

module BSV
  module Auth
    # A Certificate subclass for selective field revelation on the verifier side.
    #
    # VerifiableCertificate holds a verifier-specific keyring — a map from field
    # names to Base64-encoded symmetric keys encrypted for the verifier. Calling
    # {#decrypt_fields} decrypts each entry in the keyring using the verifier's
    # wallet and then uses the recovered key to decrypt the corresponding field
    # value from the base certificate.
    #
    # == Protocol details
    #
    # Each keyring entry is decrypted via BRC-42 key derivation:
    #
    # - Protocol:    +[2, 'certificate field encryption']+
    # - Key ID:      +"#{serial_number} #{field_name}"+
    # - Counterparty: the certificate +subject+ public key
    #
    # Wallet parameters are duck-typed — any object responding to +:decrypt+
    # is accepted. No direct dependency on +BSV::Wallet::ProtoWallet+ is
    # introduced here.
    #
    # @see BSV::Auth::Certificate  base class
    # @see BSV::Auth::MasterCertificate  for creating certificates and keyrings
    class VerifiableCertificate < Certificate
      # @return [Hash] field name → Base64-encoded verifier-specific encrypted key
      attr_reader :keyring

      # @return [Hash, nil] field name → decrypted plaintext string, or nil before decryption
      attr_reader :decrypted_fields

      # @param type [String] Base64 string (32 bytes decoded)
      # @param serial_number [String] Base64 string (32 bytes decoded)
      # @param subject [String] compressed public key hex
      # @param certifier [String] compressed public key hex
      # @param revocation_outpoint [String] +"<txid_hex>.<output_index>"+
      # @param fields [Hash] field name strings to encrypted value strings (Base64)
      # @param keyring [Hash] field name strings to Base64-encoded verifier-specific encrypted keys
      # @param signature [String, nil] DER-encoded signature hex, or nil
      # @param decrypted_fields [Hash, nil] pre-populated decrypted fields, or nil
      def initialize(type:, serial_number:, subject:, certifier:, revocation_outpoint:,
                     fields:, keyring:, signature: nil, decrypted_fields: nil)
        super(
          type: type,
          serial_number: serial_number,
          subject: subject,
          certifier: certifier,
          revocation_outpoint: revocation_outpoint,
          fields: fields,
          signature: signature
        )
        @keyring          = keyring
        @decrypted_fields = decrypted_fields
      end

      # Construct a VerifiableCertificate from a base Certificate and a keyring.
      #
      # @param certificate [Certificate] any Certificate instance (or duck-typed object
      #   responding to +type+, +serial_number+, +subject+, +certifier+,
      #   +revocation_outpoint+, +fields+, +signature+)
      # @param keyring [Hash] field name → Base64-encoded verifier-specific encrypted key
      # @return [VerifiableCertificate]
      def self.from_certificate(certificate, keyring)
        new(
          type: certificate.type,
          serial_number: certificate.serial_number,
          subject: certificate.subject,
          certifier: certificate.certifier,
          revocation_outpoint: certificate.revocation_outpoint,
          fields: certificate.fields,
          keyring: keyring,
          signature: certificate.signature
        )
      end

      # Construct a VerifiableCertificate from a plain Hash.
      #
      # Accepts both snake_case and camelCase key variants.
      #
      # @param hash [Hash] certificate data including +keyring+ and optional +decrypted_fields+
      # @return [VerifiableCertificate]
      def self.from_hash(hash)
        h = normalise_hash_keys(hash)
        new(
          type: h['type'],
          serial_number: h['serial_number'],
          subject: h['subject'],
          certifier: h['certifier'],
          revocation_outpoint: h['revocation_outpoint'],
          fields: h['fields'] || {},
          keyring: h['keyring'] || {},
          signature: h['signature'],
          decrypted_fields: h['decrypted_fields']
        )
      end

      # Decrypt selectively revealed certificate fields using the verifier's wallet.
      #
      # Algorithm:
      # 1. Raises if +keyring+ is nil or empty.
      # 2. For each field in +keyring+:
      #    a. Decrypts the encrypted revelation key via +verifier_wallet.decrypt+,
      #       using protocol +[2, 'certificate field encryption']+ and
      #       key_id +"#{serial_number} #{field_name}"+, counterparty = subject.
      #    b. Uses the recovered bytes as a {BSV::Primitives::SymmetricKey}.
      #    c. Decrypts the corresponding encrypted field value.
      #    d. Stores the UTF-8 plaintext.
      # 3. Caches and returns the decrypted fields hash.
      #
      # @param verifier_wallet [#decrypt] wallet belonging to the verifier
      # @param privileged [Boolean] whether this is a privileged operation
      # @param privileged_reason [String, nil] reason for privileged access
      # @return [Hash] field name → decrypted plaintext string
      # @raise [ArgumentError] if +keyring+ is nil or empty
      # @raise [RuntimeError] if decryption fails for any field
      def decrypt_fields(verifier_wallet, privileged: false, privileged_reason: nil)
        raise ArgumentError, 'A keyring is required to decrypt certificate fields for the verifier.' if @keyring.nil? || @keyring.empty?

        begin
          result = {}
          @keyring.each do |field_name, encrypted_key_b64|
            dec_args = {
              ciphertext: Base64.strict_decode64(encrypted_key_b64).bytes,
              counterparty: @subject,
              privileged: privileged,
              privileged_reason: privileged_reason
            }.merge(Certificate.certificate_field_encryption_details(field_name, @serial_number))

            field_revelation_key = verifier_wallet.decrypt(dec_args)[:plaintext]

            sym_key = BSV::Primitives::SymmetricKey.new(field_revelation_key.pack('C*'))
            decrypted_bytes = sym_key.decrypt(Base64.strict_decode64(@fields[field_name]))
            result[field_name] = decrypted_bytes.force_encoding('UTF-8')
          end

          @decrypted_fields = result
          result
        rescue StandardError => e
          raise "Failed to decrypt selectively revealed certificate fields using keyring: #{e.message}"
        end
      end

      # Return the certificate as a plain Hash with snake_case keys, including
      # +keyring+ and +decrypted_fields+ (if present).
      #
      # @return [Hash]
      def to_h
        h = super
        h['keyring'] = @keyring.dup
        h['decrypted_fields'] = @decrypted_fields.dup if @decrypted_fields
        h
      end

      private_class_method def self.normalise_hash_keys(hash)
        result = Certificate.send(:normalise_hash_keys, hash)
        %w[keyring].each do |k|
          result[k] ||= hash[k] || hash[k.to_sym]
        end
        %w[decrypted_fields decryptedFields].each do |k|
          result['decrypted_fields'] ||= hash[k] || hash[k.to_sym]
        end
        result
      end
    end
  end
end
