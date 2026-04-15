# frozen_string_literal: true

module BSV
  module Auth
    # BRC-104 HTTP header name constants and filtering helpers.
    #
    # Provides the canonical header names used in BSV auth HTTP transport,
    # matching the Go SDK's brc104/auth_http_headers.go exactly.
    #
    # Header filtering:
    # - Requests: content-type (normalised), authorization, x-bsv-* (excl. x-bsv-auth-*)
    # - Responses: authorization, x-bsv-* (excl. x-bsv-auth-*) — content-type is NOT signed
    #
    # Both {.filter_request_headers} and {.filter_response_headers} return sorted
    # [key, value] pairs ready for payload serialisation.
    module AuthHeaders
      module_function

      # Common prefix for all BSV auth headers.
      AUTH_PREFIX = 'x-bsv-auth'

      # Prefix for all BSV custom headers (non-auth).
      BSV_PREFIX = 'x-bsv-'

      # Protocol version header.
      VERSION = 'x-bsv-auth-version'

      # Sender's identity public key (compressed hex).
      IDENTITY_KEY = 'x-bsv-auth-identity-key'

      # Sender's nonce.
      NONCE = 'x-bsv-auth-nonce'

      # Recipient's nonce (echoed back for mutual verification).
      YOUR_NONCE = 'x-bsv-auth-your-nonce'

      # Request ID for correlation (base64-encoded 32 bytes).
      REQUEST_ID = 'x-bsv-auth-request-id'

      # Message type string (e.g. 'general', 'initialRequest').
      MESSAGE_TYPE = 'x-bsv-auth-message-type'

      # ECDSA/Schnorr signature (hex-encoded).
      SIGNATURE = 'x-bsv-auth-signature'

      # Requested certificate set (JSON-encoded).
      REQUESTED_CERTIFICATES = 'x-bsv-auth-requested-certificates'

      # Payment protocol version.
      PAYMENT_VERSION = 'x-bsv-payment-version'

      # Number of satoshis required for payment.
      PAYMENT_SATOSHIS_REQUIRED = 'x-bsv-payment-satoshis-required'

      # BIP-32 derivation prefix for payment key.
      PAYMENT_DERIVATION_PREFIX = 'x-bsv-payment-derivation-prefix'

      # Raw payment transaction (hex or base64).
      PAYMENT = 'x-bsv-payment'

      # Filters request headers to the set that is signed in the payload.
      #
      # Includes (matching TS/Go SDK behaviour):
      # - +content-type+ — normalised by stripping "; charset=..." params
      # - +authorization+
      # - +x-bsv-*+ headers, excluding any that start with +x-bsv-auth+
      #
      # Raises +ArgumentError+ if any header does not fall into the above
      # categories (matching TS SDK strictness — an unsupported header that
      # the caller expects to be signed is a security concern).
      #
      # @param headers [Hash] header key/value pairs (keys need not be lowercased)
      # @return [Array<Array(String, String)>] sorted [key, value] pairs, keys lowercased
      # @raise [ArgumentError] if an unsupported header is present
      def filter_request_headers(headers)
        result = []
        headers.each do |k, v|
          key = k.to_s.downcase
          if key.start_with?(BSV_PREFIX)
            raise ArgumentError, "BSV auth headers are not allowed in the request payload: #{key}" if key.start_with?(AUTH_PREFIX)

            result << [key, v.to_s]
          elsif key == 'authorization'
            result << [key, v.to_s]
          elsif key == 'content-type'
            # Normalise: strip parameters like "; charset=utf-8"
            normalised = v.to_s.split(';').first.to_s.strip
            result << [key, normalised]
          else
            raise ArgumentError,
                  'Unsupported header in the simplified fetch implementation. ' \
                  "Only content-type, authorization, and x-bsv-* headers are supported. Got: #{key}"
          end
        end
        result.sort_by { |key, _| key }
      end

      # Filters response headers to the set that is signed in the payload.
      #
      # Includes (matching TS/Go SDK behaviour):
      # - +authorization+
      # - +x-bsv-*+ headers, excluding any that start with +x-bsv-auth+
      #
      # Note: +content-type+ is intentionally excluded from response signing
      # (matches both Go and TS SDK behaviour).
      #
      # @param headers [Hash] header key/value pairs
      # @return [Array<Array(String, String)>] sorted [key, value] pairs, keys lowercased
      def filter_response_headers(headers)
        result = []
        headers.each do |k, v|
          key = k.to_s.downcase
          if key.start_with?(BSV_PREFIX)
            next if key.start_with?(AUTH_PREFIX)

            result << [key, v.to_s]
          elsif key == 'authorization'
            result << [key, v.to_s]
          end
        end
        result.sort_by { |key, _| key }
      end

      # Extracts +x-bsv-auth-*+ headers from a hash and returns a structured hash
      # with symbolised keys derived from the header name suffix.
      #
      # For example, +x-bsv-auth-identity-key+ becomes +:identity_key+.
      #
      # @param headers [Hash] incoming headers hash (keys may be mixed case)
      # @return [Hash] symbolised auth header values; only present keys are included
      def extract_auth_headers(headers)
        prefix = "#{AUTH_PREFIX}-"
        result = {}
        headers.each do |k, v|
          key = k.to_s.downcase
          next unless key.start_with?(prefix)

          suffix = key[prefix.length..]
          symbol_key = suffix.tr('-', '_').to_sym
          result[symbol_key] = v
        end
        result
      end
    end
  end
end
