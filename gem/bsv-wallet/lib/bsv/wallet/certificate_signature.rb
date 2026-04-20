# frozen_string_literal: true

require 'base64'

module BSV
  module Wallet
    # BRC-52 identity certificate signature verification.
    #
    # Certificates carry a signature from the certifier over a canonical
    # binary serialisation of their fields (excluding the signature itself).
    # This module builds that canonical serialisation and delegates
    # verification to a {ProtoWallet}-compatible verifier.
    #
    # Every field is included in the preimage in this order:
    #
    # - +type+ (base64 → 32 bytes)
    # - +serial_number+ (base64 → 32 bytes)
    # - +subject+ (hex → 33-byte compressed pubkey)
    # - +certifier+ (hex → 33-byte compressed pubkey)
    # - +revocation_outpoint+: txid hex (32 bytes) + output index VarInt
    # - +fields+: VarInt count, then for each field (sorted
    #   lexicographically by name): VarInt name length + UTF-8 name bytes
    #   + VarInt value length + UTF-8 value bytes
    #
    # Signing uses BRC-42 key derivation with:
    #
    # - protocol ID: +[2, 'certificate signature']+
    # - key ID: +"\#{type} \#{serial_number}"+
    # - counterparty on sign: +'anyone'+ (default of
    #   +ProtoWallet#create_signature+ in TS — Ruby consumers should pass
    #   it explicitly since Ruby defaults to +'self'+)
    # - counterparty on verify: the certifier's public key hex
    #
    # @see https://hub.bsvblockchain.org/brc/wallet/0052 BRC-52
    module CertificateSignature
      PROTOCOL_ID = [2, 'certificate signature'].freeze

      # Error raised when a certificate's signature cannot be verified.
      class InvalidError < InvalidSignatureError
        def initialize(detail)
          super("certificate signature verification failed: #{detail}")
        end
      end

      module_function

      # Verify a certificate's certifier signature.
      #
      # Raises {InvalidError} if the signature is missing, malformed, or
      # does not match the expected certifier.
      #
      # @param cert [Hash] certificate fields. Required keys:
      #   +:type+, +:serial_number+, +:subject+, +:certifier+,
      #   +:revocation_outpoint+, +:fields+, +:signature+
      # @param verifier [#verify_signature] optional verifier; defaults to
      #   a fresh +ProtoWallet.new('anyone')+
      # @return [true] when the signature verifies
      # @raise [InvalidError] otherwise
      def verify!(cert, verifier: ProtoWallet.new('anyone'))
        signature_hex = cert[:signature]
        raise InvalidError, 'signature is missing' if signature_hex.nil? || signature_hex.empty?

        preimage = serialise_preimage(cert)
        sig_bytes = hex_to_bytes(signature_hex)

        verifier.verify_signature({
                                    data: preimage.unpack('C*'),
                                    signature: sig_bytes,
                                    protocol_id: PROTOCOL_ID,
                                    key_id: "#{cert[:type]} #{cert[:serial_number]}",
                                    counterparty: cert[:certifier]
                                  })

        true
      rescue InvalidSignatureError => e
        raise if e.is_a?(InvalidError)

        raise InvalidError, e.message
      rescue ArgumentError, EncodingError => e
        # EncodingError covers Encoding::InvalidByteSequenceError and
        # Encoding::UndefinedConversionError, which `encode_fields`
        # raises for non-UTF-8 field names or values. Callers of
        # `acquire_certificate` expect `InvalidError` on bad cert input
        # — leaking EncodingError would break that contract.
        raise InvalidError, e.message
      end

      # Build the BRC-52 canonical preimage for signing or verifying.
      #
      # @param cert [Hash] certificate fields (see {.verify!})
      # @return [String] binary string suitable for +sha256+ (via
      #   {ProtoWallet#verify_signature})
      def serialise_preimage(cert)
        buf = String.new(encoding: Encoding::ASCII_8BIT)
        buf << decode_base64_exact(cert[:type], 32, 'type')
        buf << decode_base64_exact(cert[:serial_number], 32, 'serial_number')
        buf << decode_hex_exact(cert[:subject], 33, 'subject')
        buf << decode_hex_exact(cert[:certifier], 33, 'certifier')

        buf << encode_revocation_outpoint(cert[:revocation_outpoint])
        buf << encode_fields(cert[:fields])
        buf
      end

      class << self
        private

        def encode_revocation_outpoint(outpoint)
          raise ArgumentError, 'revocation_outpoint is missing' if outpoint.nil? || outpoint.empty?

          txid_hex, output_index_str = outpoint.to_s.split('.', 2)
          raise ArgumentError, "revocation_outpoint #{outpoint.inspect} missing '.<output_index>'" if output_index_str.nil?

          unless output_index_str.match?(/\A\d+\z/)
            raise ArgumentError, "revocation_outpoint output index must be a non-negative integer, got #{output_index_str.inspect}"
          end

          buf = String.new(encoding: Encoding::ASCII_8BIT)
          buf << decode_hex_exact(txid_hex, 32, 'revocation_outpoint txid')
          buf << BSV::Transaction::VarInt.encode(output_index_str.to_i)
          buf
        end

        def encode_fields(fields)
          raise ArgumentError, 'fields must be a Hash' unless fields.is_a?(Hash)

          normalised = normalise_field_keys(fields)

          buf = String.new(encoding: Encoding::ASCII_8BIT)
          sorted_names = normalised.keys.sort
          buf << BSV::Transaction::VarInt.encode(sorted_names.length)

          sorted_names.each do |name|
            name_bytes = name.encode('UTF-8').b
            value_bytes = normalised[name].to_s.encode('UTF-8').b

            buf << BSV::Transaction::VarInt.encode(name_bytes.bytesize)
            buf << name_bytes
            buf << BSV::Transaction::VarInt.encode(value_bytes.bytesize)
            buf << value_bytes
          end
          buf
        end

        # Normalise Hash keys to strings and reject post-normalisation
        # duplicates (e.g. both `:email` and `'email'`). Without this,
        # `fields.keys.map(&:to_s)` silently produces duplicate entries
        # with ambiguous value ordering, which makes the BRC-52 preimage
        # non-deterministic.
        def normalise_field_keys(fields)
          normalised = {}
          fields.each do |key, value|
            str_key = key.to_s
            if normalised.key?(str_key)
              raise ArgumentError,
                    "duplicate field name #{str_key.inspect} " \
                    '(once as string, once as symbol)'
            end

            normalised[str_key] = value
          end
          normalised
        end

        def decode_base64_exact(value, expected_length, field_name)
          raise ArgumentError, "#{field_name} is missing" if value.nil? || value.empty?

          # strict_decode64 (vs permissive decode64) rejects whitespace,
          # non-base64 characters, and non-canonical padding. The rest
          # of bsv-wallet (e.g. the wire serialiser) uses strict mode,
          # and the BRC-52 preimage must be unambiguous — a cert with
          # whitespace-injected type/serial_number would decode to the
          # right length but produce a different canonical form than
          # the same data re-submitted cleanly.
          bytes = begin
            Base64.strict_decode64(value)
          rescue ArgumentError => e
            raise ArgumentError, "#{field_name} is not valid base64: #{e.message}"
          end

          if bytes.bytesize != expected_length
            raise ArgumentError,
                  "#{field_name} must decode to #{expected_length} bytes, got #{bytes.bytesize}"
          end

          bytes.b
        end

        def decode_hex_exact(value, expected_length, field_name)
          raise ArgumentError, "#{field_name} is missing" if value.nil? || value.empty?
          raise ArgumentError, "#{field_name} must be a hex string" unless value.match?(/\A\h+\z/)
          raise ArgumentError, "#{field_name} hex length must be even" unless value.length.even?

          bytes = [value].pack('H*')
          if bytes.bytesize != expected_length
            raise ArgumentError,
                  "#{field_name} must decode to #{expected_length} bytes, got #{bytes.bytesize}"
          end

          bytes.b
        end

        def hex_to_bytes(hex)
          raise ArgumentError, 'signature must be a hex string' unless hex.is_a?(String) && hex.match?(/\A\h+\z/)
          raise ArgumentError, 'signature hex length must be even' unless hex.length.even?

          [hex].pack('H*').unpack('C*')
        end
      end
    end
  end
end
