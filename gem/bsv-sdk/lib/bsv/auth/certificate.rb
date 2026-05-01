# frozen_string_literal: true

require 'base64'

module BSV
  module Auth
    # Identity certificate as per the BRC-52 Wallet interface specification.
    #
    # A certificate binds identity attributes (fields) to a subject public key,
    # and is signed by a certifier. The binary serialisation format is shared
    # across all BSV SDKs (Go, TypeScript, Python, Ruby) so that certificates
    # produced by one SDK can be verified by another.
    #
    # All field values are expected to be Base64-encoded encrypted strings.
    # Signing and verification use BRC-42 key derivation:
    #
    # - Protocol:    +[2, 'certificate signature']+
    # - Key ID:      +"#{type} #{serial_number}"+
    # - Counterparty on sign:   +'anyone'+ (default for +create_signature+)
    # - Counterparty on verify: the certifier's compressed public key hex
    #
    # Wallet parameters are duck-typed — any object responding to
    # +create_signature+, +verify_signature+, and +get_public_key+ is accepted.
    # No direct dependency on +BSV::Wallet::Client+ is introduced here.
    #
    # @see https://hub.bsvblockchain.org/brc/wallet/0052 BRC-52
    class Certificate
      CERT_SIG_PROTOCOL = [2, 'certificate signature'].freeze
      CERT_FIELD_ENC_PROTOCOL = [2, 'certificate field encryption'].freeze

      # @return [String] Base64 string decoding to 32 bytes
      attr_reader :type

      # @return [String] Base64 string decoding to 32 bytes
      attr_reader :serial_number

      # @return [String] compressed public key hex (66 characters)
      attr_reader :subject

      # @return [String] compressed public key hex (66 characters)
      attr_accessor :certifier

      # @return [String] outpoint string +"<txid_hex>.<output_index>"+
      attr_reader :revocation_outpoint

      # @return [Hash] mapping field name strings to value strings
      attr_reader :fields

      # @return [String, nil] DER-encoded signature as hex string, or nil if unsigned
      attr_accessor :signature

      # @param type [String] Base64 string (32 bytes decoded)
      # @param serial_number [String] Base64 string (32 bytes decoded)
      # @param subject [String] compressed public key hex
      # @param certifier [String] compressed public key hex
      # @param revocation_outpoint [String] +"<txid_hex>.<output_index>"+
      # @param fields [Hash] field name strings to value strings
      # @param signature [String, nil] DER-encoded signature hex, or nil
      def initialize(type:, serial_number:, subject:, certifier:, revocation_outpoint:, fields:, signature: nil)
        @type                 = type
        @serial_number        = serial_number
        @subject              = subject
        @certifier            = certifier
        @revocation_outpoint  = revocation_outpoint
        @fields               = fields
        @signature            = signature
      end

      # Serialise the certificate into its binary format.
      #
      # The binary format is byte-compatible with all other BSV SDK
      # implementations. Fields are sorted lexicographically by name.
      #
      # @param include_signature [Boolean] whether to append the signature bytes
      # @return [String] binary string
      def to_binary(include_signature: true)
        buf = String.new(encoding: Encoding::ASCII_8BIT)

        buf << Base64.strict_decode64(@type)
        buf << Base64.strict_decode64(@serial_number)
        buf << [@subject].pack('H*')
        buf << [@certifier].pack('H*')

        txid_hex, output_index_str = @revocation_outpoint.to_s.split('.', 2)
        buf << [txid_hex].pack('H*')
        buf << BSV::Transaction::VarInt.encode(output_index_str.to_i)

        sorted_names = @fields.keys.sort
        buf << BSV::Transaction::VarInt.encode(sorted_names.length)
        sorted_names.each do |name|
          name_bytes  = name.to_s.encode('UTF-8').b
          value_bytes = @fields[name].to_s.encode('UTF-8').b
          buf << BSV::Transaction::VarInt.encode(name_bytes.bytesize)
          buf << name_bytes
          buf << BSV::Transaction::VarInt.encode(value_bytes.bytesize)
          buf << value_bytes
        end

        buf << [@signature].pack('H*') if include_signature && @signature && !@signature.empty?

        buf
      end

      # Deserialise a certificate from its binary format.
      #
      # When a signature is present in the trailing bytes, it is parsed via
      # {BSV::Primitives::Signature.from_der} to ensure strict DER normalisation
      # before being re-serialised as hex.
      #
      # @param data [String] binary string
      # @return [Certificate]
      def self.from_binary(data)
        data = data.b
        raise ArgumentError, "certificate binary too short (#{data.bytesize} bytes, minimum 163)" if data.bytesize < 163

        pos = 0

        type_bytes = data.byteslice(pos, 32)
        pos += 32
        serial_bytes = data.byteslice(pos, 32)
        pos += 32
        subject_bytes = data.byteslice(pos, 33)
        pos += 33
        certifier_bytes = data.byteslice(pos, 33)
        pos += 33

        txid_bytes = data.byteslice(pos, 32)
        pos += 32
        output_index, vi_len = BSV::Transaction::VarInt.decode(data, pos)
        pos += vi_len

        num_fields, vi_len = BSV::Transaction::VarInt.decode(data, pos)
        pos += vi_len
        fields = {}
        num_fields.times do
          name_len, vi_len = BSV::Transaction::VarInt.decode(data, pos)
          pos += vi_len
          name = data.byteslice(pos, name_len).force_encoding('UTF-8')
          pos += name_len

          value_len, vi_len = BSV::Transaction::VarInt.decode(data, pos)
          pos += vi_len
          value = data.byteslice(pos, value_len).force_encoding('UTF-8')
          pos += value_len

          fields[name] = value
        end

        signature = nil
        if pos < data.bytesize
          sig_bytes = data.byteslice(pos, data.bytesize - pos)
          parsed    = BSV::Primitives::Signature.from_der(sig_bytes)
          signature = parsed.to_hex
        end

        new(
          type: Base64.strict_encode64(type_bytes),
          serial_number: Base64.strict_encode64(serial_bytes),
          subject: subject_bytes.unpack1('H*'),
          certifier: certifier_bytes.unpack1('H*'),
          revocation_outpoint: "#{txid_bytes.unpack1('H*')}.#{output_index}",
          fields: fields,
          signature: signature
        )
      end

      # Verify the certificate's signature.
      #
      # Uses a fresh +'anyone'+ ProtoWallet as the verifier, which matches the
      # TS SDK behaviour. If no signature is present, raises +ArgumentError+.
      #
      # @param verifier_wallet [#verify_signature, nil] wallet to verify with;
      #   defaults to +BSV::Wallet::ProtoWallet.new('anyone')+
      # @return [Boolean] +true+ if the signature is valid
      # @raise [ArgumentError] if the certificate has no signature
      def verify(verifier_wallet = nil)
        raise ArgumentError, 'certificate has no signature to verify' if @signature.nil? || @signature.empty?

        verifier_wallet ||= BSV::Wallet::ProtoWallet.new('anyone')
        preimage  = to_binary(include_signature: false)
        sig_bytes = [@signature].pack('H*').unpack('C*')

        result = verifier_wallet.verify_signature(
          data: preimage.unpack('C*'),
          signature: sig_bytes,
          protocol_id: CERT_SIG_PROTOCOL,
          key_id: "#{@type} #{@serial_number}",
          counterparty: @certifier
        )

        result.is_a?(Hash) && result[:valid] == true
      rescue BSV::Wallet::InvalidSignatureError
        false
      end

      # Sign the certificate using the provided certifier wallet.
      #
      # The certifier field is updated to the wallet's identity key before
      # signing. Raises if the certificate is already signed.
      #
      # @param certifier_wallet [#create_signature, #get_public_key] certifier wallet
      # @raise [ArgumentError] if the certificate already has a signature
      def sign(certifier_wallet)
        raise ArgumentError, "certificate has already been signed: #{@signature}" if @signature && !@signature.empty?

        @certifier = certifier_wallet.get_public_key(identity_key: true)[:public_key]

        preimage = to_binary(include_signature: false)
        result   = certifier_wallet.create_signature(
          data: preimage.unpack('C*'),
          protocol_id: CERT_SIG_PROTOCOL,
          key_id: "#{@type} #{@serial_number}"
        )
        @signature = result[:signature].pack('C*').unpack1('H*')
      end

      # Returns the protocol ID and key ID for certificate field encryption.
      #
      # When +serial_number+ is provided (for verifier keyring creation) the
      # key ID is +"#{serial_number} #{field_name}"+. Without a serial number
      # (for master keyring creation) the key ID is just the +field_name+.
      #
      # @param field_name [String] name of the certificate field
      # @param serial_number [String, nil] certificate serial number (Base64)
      # @return [Hash] +{ protocol_id:, key_id: }+
      def self.certificate_field_encryption_details(field_name, serial_number = nil)
        key_id = serial_number ? "#{serial_number} #{field_name}" : field_name
        { protocol_id: CERT_FIELD_ENC_PROTOCOL, key_id: key_id }
      end

      # Construct a Certificate from a plain Hash.
      #
      # Accepts both snake_case and camelCase key variants for each field
      # so that wire-format hashes can be passed in directly.
      #
      # @param hash [Hash] certificate data with snake_case or camelCase keys
      # @return [Certificate]
      def self.from_hash(hash)
        h = normalise_hash_keys(hash)
        new(
          type: h['type'],
          serial_number: h['serial_number'],
          subject: h['subject'],
          certifier: h['certifier'],
          revocation_outpoint: h['revocation_outpoint'],
          fields: h['fields'] || {},
          signature: h['signature']
        )
      end

      # Return the certificate as a plain Hash with snake_case keys.
      #
      # JSON serialisation is simply +cert.to_h.to_json+.
      #
      # @return [Hash]
      def to_h
        {
          'type' => @type,
          'serial_number' => @serial_number,
          'subject' => @subject,
          'certifier' => @certifier,
          'revocation_outpoint' => @revocation_outpoint,
          'fields' => @fields.dup,
          'signature' => @signature
        }
      end

      private_class_method def self.normalise_hash_keys(hash)
        mappings = {
          'type' => %w[type],
          'serial_number' => %w[serial_number serialNumber],
          'subject' => %w[subject],
          'certifier' => %w[certifier],
          'revocation_outpoint' => %w[revocation_outpoint revocationOutpoint],
          'fields' => %w[fields],
          'signature' => %w[signature]
        }

        result = {}
        mappings.each do |canonical, aliases|
          aliases.each do |a|
            result[canonical] = hash[a] || hash[a.to_sym] if result[canonical].nil?
          end
        end
        result
      end
    end
  end
end
