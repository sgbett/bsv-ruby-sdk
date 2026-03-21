# frozen_string_literal: true

require 'json'
require 'rack'

module BSV
  module X402
    # Rack middleware that enforces x402 payment requirements on protected routes.
    #
    # == Usage
    #
    #   use BSV::X402::Middleware do |x402|
    #     x402.protect '/api/v1/premium', amount_sats: 100
    #     x402.protect '/api/v1/data/*',  amount_sats: 50
    #   end
    #
    # Or with a proc:
    #
    #   use BSV::X402::Middleware,
    #       protect: ->(env) { env['PATH_INFO'].start_with?('/api/premium') }
    #
    # == Request flow
    #
    # 1. If the route is unprotected, pass the request through to the inner app.
    # 2. If the +X402-Proof+ header is absent, generate a {Challenge}, persist it
    #    in the challenge store, and return 402 with the +X402-Challenge+ header.
    # 3. If the header is present but malformed, return 400.
    # 4. Look up the original challenge from the store using the proof's
    #    +challenge_sha256+ field. If not found, return 402 (fresh challenge).
    # 5. Verify the proof against the stored challenge.
    # 6. On success, pass through to the inner app.
    # 7. On verification failure, return the appropriate status (400 or 402).
    #
    # == Invariants
    #
    # - The middleware MUST NOT hold private keys or sign transactions (A-2).
    # - Route matching is first-match-wins.
    # - Exactly one +X402-Challenge+ header is set in 402 responses.
    # - Challenges are persisted in +config.challenge_store+ (defaults to an
    #   in-process {MemoryChallengeStore}). Replace with a distributed store for
    #   multi-process deployments.
    #
    # == Configuration
    #
    # Global configuration is read from +BSV::X402.configuration+. Individual
    # routes may override +:amount_sats+ and +:bound_headers+.
    #
    # The optional +:on_payment_verified+ callback (a callable) is invoked after
    # successful verification, before the request is passed to the inner app.
    # It receives the Rack env and the {VerificationResult}.
    class Middleware
      # @param app     [#call] the inner Rack application
      # @param options [Hash]  middleware options
      # @option options [#call] :protect proc-based protection (receives Rack env, returns Boolean)
      # @option options [Configuration] :config overrides the global +BSV::X402.configuration+
      # @option options [#call] :on_payment_verified callback fired on successful verification
      # @yield [RouteMap] optional DSL block for registering protected routes
      def initialize(app, options = {})
        @app          = app
        @config       = options.fetch(:config, BSV::X402.configuration)
        @protect_proc = options[:protect]
        @route_map    = RouteMap.new
        @on_verified  = options[:on_payment_verified] || @config.on_payment_verified

        yield(@route_map) if block_given?
      end

      # Entry point for the Rack call chain.
      #
      # @param env [Hash] Rack environment
      # @return [Array(Integer, Hash, #each)] Rack response triple
      def call(env)
        return @app.call(env) unless protected?(env)

        proof_header = env['HTTP_X402_PROOF']

        return issue_challenge(env) unless proof_header

        handle_proof(env, proof_header)
      end

      private

      # Returns +true+ if the request should be gated by x402.
      #
      # Checks the proc-based guard first (if configured), then the route map.
      #
      # @param env [Hash]
      # @return [Boolean]
      def protected?(env)
        return @protect_proc.call(env) if @protect_proc

        @route_map.protected?(env['PATH_INFO'].to_s)
      end

      # Generates a fresh challenge, stores it, and returns a 402 response.
      #
      # @param env [Hash]
      # @return [Array]
      def issue_challenge(env)
        route_options = route_options_for(env)
        challenge     = ChallengeGenerator.generate(env: env, config: @config, route_options: route_options)

        @config.challenge_store.store(challenge.sha256, challenge)

        header_value = challenge.to_header

        body = JSON.generate(
          'error' => 'Payment Required',
          'scheme' => challenge.scheme,
          'amount_sats' => challenge.amount_sats
        )

        [402, {
          'content-type' => 'application/json',
          'x402-challenge' => header_value
        }, [body]]
      rescue ValidationError => e
        error_response(500, "challenge generation failed: #{e.message}")
      end

      # Parses and verifies the proof header, then passes through or rejects.
      #
      # @param env          [Hash]
      # @param proof_header [String] raw value of the +X402-Proof+ header
      # @return [Array]
      def handle_proof(env, proof_header)
        proof     = Proof.from_header(proof_header)
        challenge = lookup_challenge(proof.challenge_sha256)

        return issue_challenge(env) unless challenge

        request_info = build_request_info(env)
        result = Verifier.verify(
          challenge: challenge,
          proof: proof,
          request: request_info,
          settlement_verifier: @config.settlement_verifier
        )

        if result.success?
          @on_verified&.call(env, result)
          @app.call(env)
        else
          verification_failure_response(result)
        end
      rescue EncodingError => e
        error_response(400, "invalid X402-Proof header: #{e.message}")
      rescue ValidationError => e
        error_response(400, "invalid proof structure: #{e.message}")
      end

      # Looks up a previously issued challenge from the store.
      #
      # Returns +nil+ if the challenge is not found (unknown or expired from store).
      #
      # @param sha256 [String] hex SHA-256 digest from the proof
      # @return [Challenge, nil]
      def lookup_challenge(sha256)
        @config.challenge_store.fetch(sha256)
      end

      # Builds the normalised request info hash expected by {Verifier}.
      #
      # @param env [Hash]
      # @return [Hash]
      def build_request_info(env)
        request = Rack::Request.new(env)

        headers_hash = ChallengeGenerator.send(:compute_headers_hash, env, @config.bound_headers)
        body_hash    = ChallengeGenerator.send(:compute_body_hash, request)

        {
          method: env['REQUEST_METHOD'].to_s,
          path: env['PATH_INFO'].to_s,
          query: (env['QUERY_STRING'] || '').to_s,
          headers_sha256: headers_hash,
          body_sha256: body_hash
        }
      end

      # Returns per-route option overrides for the matched route, or an empty hash.
      #
      # @param env [Hash]
      # @return [Hash]
      def route_options_for(env)
        return {} if @protect_proc

        route = @route_map.match(env['PATH_INFO'].to_s)
        route ? route.options : {}
      end

      # Returns a 400/402 JSON response describing the verification failure.
      #
      # @param result [VerificationResult]
      # @return [Array]
      def verification_failure_response(result)
        body = JSON.generate('error' => result.reason, 'step' => result.step)
        [result.http_status, { 'content-type' => 'application/json' }, [body]]
      end

      # Returns a plain JSON error response.
      #
      # @param status  [Integer] HTTP status code
      # @param message [String]
      # @return [Array]
      def error_response(status, message)
        body = JSON.generate({ 'error' => message })
        [status, { 'content-type' => 'application/json' }, [body]]
      end
    end
  end
end
