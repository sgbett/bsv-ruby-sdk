# frozen_string_literal: true

module BSV
  module X402
    # Builds a {Proof} from a challenge and a completed payment transaction.
    #
    # The proof binds the payment to the original challenge and the specific
    # HTTP request that triggered the 402 response, preventing replay of the
    # same proof against a different request.
    #
    # Usage:
    #
    #   proof = BSV::X402::ProofBuilder.build(
    #     challenge:   challenge,
    #     transaction: tx,
    #     request:     {
    #       method:             'GET',
    #       path:               '/api/resource',
    #       query:              'page=1',
    #       req_headers_sha256: headers_hash,
    #       req_body_sha256:    body_hash
    #     }
    #   )
    #   header_value = proof.to_header  # => base64url string for X402-Proof
    class ProofBuilder
      # Build a {Proof} from a challenge and payment transaction.
      #
      # The +request+ hash keys may be symbols or strings. It must contain:
      #   +:method+ / +'method'+
      #   +:path+   / +'path'+
      #   +:query+  / +'query'+
      #   +:req_headers_sha256+ / +'req_headers_sha256'+
      #   +:req_body_sha256+    / +'req_body_sha256'+
      #
      # @param challenge [Challenge] the original challenge
      # @param transaction [BSV::Transaction::Transaction] the signed payment tx
      # @param request [Hash] the HTTP request being made
      # @return [Proof] the proof ready to be sent as the +X402-Proof+ header
      def self.build(challenge:, transaction:, request:)
        raw_bytes = transaction.to_binary
        txid_hex  = transaction.txid_hex
        rawtx_b64 = Encoding.base64_encode(raw_bytes)

        # Normalise request keys to strings for the proof sub-object.
        req = normalise_request(request)

        Proof.new(
          v: Proof::SUPPORTED_VERSION,
          scheme: Proof::SCHEME,
          challenge_sha256: challenge.sha256,
          request: {
            'method' => req[:method],
            'path' => req[:path],
            'query' => req[:query],
            'req_headers_sha256' => req[:req_headers_sha256],
            'req_body_sha256' => req[:req_body_sha256]
          },
          payment: {
            'txid' => txid_hex,
            'rawtx_b64' => rawtx_b64
          }
        )
      end

      # ------------------------------------------------------------------
      # Private helpers
      # ------------------------------------------------------------------

      # Normalise request hash to symbol keys, accepting either string or symbol
      # keys from the caller.
      #
      # @param req [Hash]
      # @return [Hash] symbol-keyed hash
      def self.normalise_request(req)
        {
          method: (req[:method] || req['method']).to_s,
          path: (req[:path] || req['path']).to_s,
          query: (req[:query] || req['query']).to_s,
          req_headers_sha256: (req[:req_headers_sha256] || req['req_headers_sha256']).to_s,
          req_body_sha256: (req[:req_body_sha256] || req['req_body_sha256']).to_s
        }
      end
      private_class_method :normalise_request
    end
  end
end
