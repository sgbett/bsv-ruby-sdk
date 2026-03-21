# frozen_string_literal: true

module BSV
  module X402
    # Implements the ordered 9-step verification procedure from spec §7.
    #
    # Each step MUST execute in order (invariant V-1). The first failing step
    # causes an immediate return with a {VerificationResult} describing the
    # failure. No subsequent steps are executed after a failure.
    #
    # Usage:
    #
    #   result = BSV::X402::Verifier.verify(
    #     challenge: challenge,
    #     proof:     proof,
    #     request:   { method: 'GET', path: '/pay', query: '', headers_sha256: '...', body_sha256: '...' },
    #   )
    #   result.success? # => true / false
    #   result.step     # => nil or 1..9
    #   result.reason   # => nil or String
    #
    # The +request+ hash keys may be symbols or strings:
    #   +:method+ / +'method'+, +:path+ / +'path'+, +:query+ / +'query'+,
    #   +:headers_sha256+ / +'headers_sha256'+, +:body_sha256+ / +'body_sha256'+
    #
    # The +settlement_verifier+ is an optional callable (responds to +#call+).
    # It receives the raw transaction bytes and must return a truthy value for
    # mempool acceptance. It is only invoked when +challenge.require_mempool_accept+
    # is true.
    class Verifier
      # Runs the full 9-step verification procedure.
      #
      # @param challenge [Challenge] the original challenge
      # @param proof [Proof] the proof to verify
      # @param request [Hash] the actual inbound HTTP request info:
      #   { method:, path:, query:, headers_sha256:, body_sha256: }
      # @param settlement_verifier [#call, nil] optional callable for mempool check
      # @return [VerificationResult] success or failure with step number and reason
      def self.verify(challenge:, proof:, request:, settlement_verifier: nil)
        new(challenge, proof, request, settlement_verifier).verify
      end

      # @param challenge [Challenge]
      # @param proof [Proof]
      # @param request [Hash]
      # @param settlement_verifier [#call, nil]
      def initialize(challenge, proof, request, settlement_verifier)
        @challenge           = challenge
        @proof               = proof
        @request             = request
        @settlement_verifier = settlement_verifier
      end

      # Executes all 9 steps in order and returns the first failure or success.
      #
      # @return [VerificationResult]
      def verify
        result = step1_validate_proof_structure
        return result if result.failure?

        result = step2_validate_version_and_scheme
        return result if result.failure?

        result = step3_verify_challenge_sha256
        return result if result.failure?

        result = step4_validate_request_binding
        return result if result.failure?

        result = step5_check_expiry
        return result if result.failure?

        result, tx = step6_decode_and_verify_transaction
        return result if result.failure?

        result = step7_verify_nonce_spend(tx)
        return result if result.failure?

        result = step8_verify_payment_output(tx)
        return result if result.failure?

        step9_verify_mempool_acceptance(tx)
      end

      private

      # Step 1: Verify the proof is structurally present and complete.
      #
      # Proof parsing (via +Proof.from_header+) has already been done by the
      # caller, but a nil proof is still a valid failure here. The Proof
      # constructor already validates required fields, so a non-nil Proof
      # instance is structurally valid by construction.
      #
      # Failure → HTTP 400
      def step1_validate_proof_structure
        return fail(1, 'proof is nil') if @proof.nil?

        ok
      end

      # Step 2: Validate protocol version and scheme identifier.
      #
      # The proof must carry v=1 and scheme='bsv-tx-v1'. These are already
      # enforced by +Proof.new+, so this step is a defence-in-depth guard
      # for proofs constructed outside the normal path.
      #
      # Failure → HTTP 400
      def step2_validate_version_and_scheme
        unless @proof.v == BSV::X402::Proof::SUPPORTED_VERSION
          return fail(2, "proof.v must be #{BSV::X402::Proof::SUPPORTED_VERSION}, got #{@proof.v}")
        end

        return fail(2, "proof.scheme must be '#{BSV::X402::Proof::SCHEME}', got '#{@proof.scheme}'") unless @proof.scheme == BSV::X402::Proof::SCHEME

        ok
      end

      # Step 3: Recompute the challenge SHA-256 and compare to the proof's value.
      #
      # The proof's +challenge_sha256+ must exactly match the SHA-256 of the
      # canonical JSON of the challenge that was issued. A mismatch means the
      # client has a different challenge than the server, so the server must
      # issue a fresh challenge.
      #
      # Failure → HTTP 402
      def step3_verify_challenge_sha256
        expected = @challenge.sha256
        actual   = @proof.challenge_sha256

        return fail(3, 'proof.challenge_sha256 does not match the issued challenge') unless actual == expected

        ok
      end

      # Step 4: Validate that the proof's request-binding fields match both
      # the challenge and the actual inbound HTTP request.
      #
      # The binding prevents a proof from being replayed against a different
      # request. We check:
      # - method, path, query match both the challenge and the actual request
      # - req_headers_sha256 matches the challenge
      # - req_body_sha256 matches the challenge
      # - The actual request's headers/body hashes match the challenge values
      #
      # Failure → HTTP 400
      def step4_validate_request_binding
        proof_req = @proof.request
        chal      = @challenge
        actual    = normalise_request(@request)

        if proof_req['method'] != chal.method
          return fail(4, "proof.request.method '#{proof_req['method']}' does not match challenge method '#{chal.method}'")
        end

        if actual[:method] != chal.method
          return fail(4, "actual request method '#{actual[:method]}' does not match challenge method '#{chal.method}'")
        end

        return fail(4, "proof.request.path '#{proof_req['path']}' does not match challenge path '#{chal.path}'") if proof_req['path'] != chal.path

        return fail(4, "actual request path '#{actual[:path]}' does not match challenge path '#{chal.path}'") if actual[:path] != chal.path

        return fail(4, 'proof.request.query does not match challenge query') if proof_req['query'] != chal.query

        return fail(4, 'actual request query does not match challenge query') if actual[:query] != chal.query

        return fail(4, 'proof.request.req_headers_sha256 does not match challenge') if proof_req['req_headers_sha256'] != chal.req_headers_sha256

        return fail(4, 'actual request headers hash does not match challenge') if actual[:headers_sha256] != chal.req_headers_sha256

        return fail(4, 'proof.request.req_body_sha256 does not match challenge') if proof_req['req_body_sha256'] != chal.req_body_sha256

        return fail(4, 'actual request body hash does not match challenge') if actual[:body_sha256] != chal.req_body_sha256

        ok
      end

      # Step 5: Check that the challenge has not expired.
      #
      # Uses +Challenge#expired?+ with the current server time. No clock-skew
      # tolerance is applied (spec defines none).
      #
      # Failure → HTTP 402
      def step5_check_expiry
        return fail(5, 'challenge has expired') if @challenge.expired?

        ok
      end

      # Step 6: Decode the raw transaction and verify its txid.
      #
      # Decodes +proof.payment.rawtx_b64+ (standard base64, not base64url) and
      # parses it as a BSV transaction. Then confirms that +proof.payment.txid+
      # matches the double-SHA-256 of the decoded bytes in reversed byte order
      # (Bitcoin txid convention).
      #
      # Returns +[result, tx]+ — the transaction is nil on failure so callers
      # can pattern-match on result.failure? before using tx.
      #
      # Failure → HTTP 400
      def step6_decode_and_verify_transaction
        raw_bytes = @proof.decoded_tx
        tx = BSV::Transaction::Transaction.from_binary(raw_bytes)

        return [fail(6, 'proof.payment.txid does not match double-SHA-256 of the raw transaction'), nil] unless @proof.valid_txid?

        [ok, tx]
      rescue BSV::X402::EncodingError => e
        [fail(6, "failed to decode rawtx_b64: #{e.message}"), nil]
      rescue ArgumentError => e
        [fail(6, "failed to parse transaction: #{e.message}"), nil]
      end

      # Step 7: Verify that the transaction spends the nonce UTXO.
      #
      # The transaction must have at least one input whose outpoint matches the
      # challenge's nonce UTXO (same txid in display hex order and same vout).
      # Any input position is acceptable — we do not require the nonce at index 0.
      #
      # Failure → HTTP 402
      def step7_verify_nonce_spend(tx)
        nonce = @challenge.nonce_utxo
        # TransactionInput stores prev_tx_id in internal (wire) byte order.
        # txid_hex reverses it to display order for comparison.
        found = tx.inputs.any? do |input|
          input.txid_hex == nonce.txid && input.prev_tx_out_index == nonce.vout
        end

        return fail(7, "transaction does not spend nonce UTXO #{nonce.txid}:#{nonce.vout}") unless found

        ok
      end

      # Step 8: Verify that the transaction has a payment output satisfying both
      # the locking script and minimum amount requirements.
      #
      # A single output must have:
      # - locking script hex == challenge.payee_locking_script_hex
      # - satoshis >= challenge.amount_sats
      #
      # We do NOT sum across multiple matching outputs (spec §6.8 ambiguity →
      # reject). An output matching the script but below the required amount
      # is a separate, explicit rejection.
      #
      # Failure → HTTP 402
      def step8_verify_payment_output(tx)
        required_script = @challenge.payee_locking_script_hex
        required_sats   = @challenge.amount_sats

        script_match = tx.outputs.find { |o| o.locking_script.to_hex == required_script }

        return fail(8, "transaction has no output with payee locking script #{required_script}") unless script_match

        return fail(8, "payment output has #{script_match.satoshis} satoshis, need >= #{required_sats}") if script_match.satoshis < required_sats

        ok
      end

      # Step 9: Verify mempool acceptance (conditional).
      #
      # Only executed if +challenge.require_mempool_accept+ is true AND a
      # +settlement_verifier+ callable was provided. If either condition is absent
      # the step is skipped and success is returned.
      #
      # The +settlement_verifier+ is called with the raw transaction bytes. It
      # must return a truthy value for acceptance.
      #
      # Failure → HTTP 402
      def step9_verify_mempool_acceptance(_tx)
        return ok unless @challenge.require_mempool_accept
        return ok unless @settlement_verifier

        raw_bytes = @proof.decoded_tx
        accepted  = @settlement_verifier.call(raw_bytes)

        return fail(9, 'transaction was not accepted by the mempool') unless accepted

        ok
      end

      # ------------------------------------------------------------------
      # Helpers
      # ------------------------------------------------------------------

      # Normalises the caller-supplied request hash to a consistent symbol-keyed form.
      #
      # @param req [Hash] request hash (symbol or string keys)
      # @return [Hash] symbol-keyed hash with +:method+, +:path+, +:query+,
      #   +:headers_sha256+, +:body_sha256+
      def normalise_request(req)
        {
          method: (req[:method] || req['method']).to_s,
          path: (req[:path] || req['path']).to_s,
          query: (req[:query] || req['query']).to_s,
          headers_sha256: (req[:headers_sha256] || req['headers_sha256']).to_s,
          body_sha256: (req[:body_sha256] || req['body_sha256']).to_s
        }
      end

      # Returns a successful VerificationResult.
      def ok
        VerificationResult.success
      end

      # Returns a failure VerificationResult for the given step and reason.
      #
      # @param step [Integer] the step number (1–9)
      # @param reason [String] human-readable failure reason
      # @return [VerificationResult]
      def fail(step, reason)
        VerificationResult.failure(step: step, reason: reason)
      end
    end
  end
end
