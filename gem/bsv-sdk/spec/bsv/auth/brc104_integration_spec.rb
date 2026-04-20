# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'json'
require 'base64'
require 'stringio'

# End-to-end integration tests for BRC-104 HTTP authenticated transport.
#
# Exercises the full AuthFetch client <-> AuthMiddleware server stack in-process,
# with no real TCP connection.  A RackHttpClient intercepts Net::HTTP calls from
# SimplifiedFetchTransport and routes them through AuthMiddleware via a Rack env
# constructed from the Net::HTTP request object.
#
# This validates:
#   - The handshake pathway (POST /.well-known/auth)
#   - Authenticated general requests (x-bsv-auth-* headers)
#   - Session reuse across multiple requests
#   - POST bodies are delivered to the downstream application unchanged
#   - Multiple independent clients connecting to the same server
#   - Invalid signatures are rejected with 401
#   - Unauthenticated requests pass through to the downstream application

RSpec.describe 'BRC-104 AuthFetch <-> AuthMiddleware integration' do # rubocop:disable RSpec/DescribeClass
  # Deterministic keys — small integers for fast secp256k1 arithmetic.
  let(:client_key)   { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(50)) }
  let(:server_key)   { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(51)) }
  let(:client2_key)  { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(52)) }
  let(:certifier_key) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(53)) }

  let(:client_wallet)    { BSV::Wallet::Client.new(client_key, storage: BSV::Wallet::MemoryStore.new) }
  let(:server_wallet)    { BSV::Wallet::Client.new(server_key, storage: BSV::Wallet::MemoryStore.new) }
  let(:client2_wallet)   { BSV::Wallet::Client.new(client2_key, storage: BSV::Wallet::MemoryStore.new) }
  let(:certifier_wallet) { BSV::Wallet::Client.new(certifier_key, storage: BSV::Wallet::MemoryStore.new) }

  # -------------------------------------------------------------------------
  # Simple downstream Rack app
  # -------------------------------------------------------------------------
  # Routes:
  #   GET  /protected -> 200 "secret data"
  #   POST /echo      -> 200 echoes the request body as JSON: {method:, body:}
  #   GET  /payment   -> 402 with payment headers
  #   *               -> 200 "ok"

  let(:downstream_app) do
    lambda do |env|
      req_body = env['rack.input']&.read || ''
      case env['PATH_INFO']
      when '/protected'
        [200, { 'content-type' => 'text/plain' }, ['secret data']]
      when '/echo'
        payload = JSON.generate('method' => env['REQUEST_METHOD'], 'body' => req_body)
        [200, { 'content-type' => 'application/json' }, [payload]]
      when '/payment'
        [402, {
          'content-type' => 'text/plain',
          'x-bsv-payment-version' => '1.0',
          'x-bsv-auth-identity-key' => server_key.public_key.to_hex,
          'x-bsv-payment-satoshis-required' => '100',
          'x-bsv-payment-derivation-prefix' => 'pay-prefix'
        }, ['payment required']]
      else
        [200, { 'content-type' => 'text/plain' }, ['ok']]
      end
    end
  end

  # -------------------------------------------------------------------------
  # AuthMiddleware instance (shared unless overridden in a context)
  # -------------------------------------------------------------------------

  let(:middleware) { BSV::Auth::AuthMiddleware.new(downstream_app, wallet: server_wallet) }

  # -------------------------------------------------------------------------
  # RackHttpClient — routes Net::HTTP requests through a Rack app
  #
  # SimplifiedFetchTransport calls:
  #   http_client.start(host, port, use_ssl:) { |h| h.request(net_http_req) }
  #
  # We intercept this and build a Rack env from the Net::HTTP request object,
  # then call the middleware directly.
  # -------------------------------------------------------------------------

  # Builds a RackHttpClient instance that routes all requests through +rack_app+.
  def build_rack_http_client(rack_app)
    app = rack_app

    client = Object.new

    # Rack response adapter — mimics Net::HTTPResponse interface.
    resp_klass = Class.new do
      attr_reader :code, :body

      def initialize(status, headers, body_str)
        @code    = status.to_s
        @body    = body_str
        @headers = headers
      end

      def each_header(&block)
        @headers.each(&block)
      end
    end

    client.define_singleton_method(:start) do |_host, _port, use_ssl: false, &block| # rubocop:disable Lint/UnusedBlockArgument
      handler = Object.new
      handler.define_singleton_method(:request) do |net_req|
        # Translate the Net::HTTP request into a Rack env hash.
        path_and_query = net_req.path
        path_parts     = path_and_query.split('?', 2)
        rack_path      = path_parts[0]
        query_string   = path_parts[1] || ''

        body_str = net_req.body || ''
        env = {
          'REQUEST_METHOD' => net_req.class.name.split('::').last.upcase,
          'PATH_INFO' => rack_path,
          'QUERY_STRING' => query_string,
          'rack.input' => StringIO.new(body_str),
          'rack.errors' => StringIO.new
        }

        # Copy all headers from the Net::HTTP request into Rack env.
        net_req.each_header do |k, v|
          rack_key = "HTTP_#{k.upcase.tr('-', '_')}"
          env[rack_key] = v
        end

        # Content-Type gets its own Rack key as well.
        if (ct = net_req['content-type'])
          env['CONTENT_TYPE'] = ct
          env['HTTP_CONTENT_TYPE'] = ct
        end

        status, resp_headers, resp_body = app.call(env)
        body_string = Array(resp_body).join

        flat_headers = {}
        resp_headers.each { |k, v| flat_headers[k.downcase] = v }

        resp_klass.new(status, flat_headers, body_string)
      end

      block.call(handler)
    end

    client
  end

  # Builds an AuthFetch that routes all HTTP through the given rack_app.
  def build_auth_fetch(wallet, rack_app, **opts)
    client = BSV::Auth::AuthFetch.new(wallet: wallet, **opts)

    # Intercept SimplifiedFetchTransport construction so we can inject the client.
    original_new = BSV::Auth::SimplifiedFetchTransport.method(:new)
    rack_http    = build_rack_http_client(rack_app)

    allow(BSV::Auth::SimplifiedFetchTransport).to receive(:new) do |base_url, **transport_opts|
      original_new.call(base_url, http_client: rack_http, **transport_opts)
    end

    client
  end

  # =========================================================================
  # Scenario 1: Full lifecycle — handshake + authenticated GET
  # =========================================================================

  describe 'Scenario 1: full lifecycle — handshake + authenticated GET' do
    it 'returns 200 with the expected body after automatic handshake' do
      auth_fetch = build_auth_fetch(client_wallet, middleware)

      response = auth_fetch.fetch('http://example.com/protected')

      expect(response.status).to eq(200)
      expect(response.body).to eq('secret data')
    end

    it 'sets the server identity key on the response' do
      auth_fetch = build_auth_fetch(client_wallet, middleware)

      response = auth_fetch.fetch('http://example.com/protected')

      expect(response.identity_key).to eq(server_key.public_key.to_hex)
    end
  end

  # =========================================================================
  # Scenario 2: Authenticated POST with JSON body
  # =========================================================================

  describe 'Scenario 2: authenticated POST with JSON body' do
    it 'delivers the body to the downstream app and echoes it back' do
      auth_fetch = build_auth_fetch(client_wallet, middleware)

      response = auth_fetch.fetch(
        'http://example.com/echo',
        method: 'POST',
        body: { 'hello' => 'world' }
      )

      expect(response.status).to eq(200)
      parsed = JSON.parse(response.body)
      expect(parsed['method']).to eq('POST')
      expect(JSON.parse(parsed['body'])).to eq('hello' => 'world')
    end
  end

  # =========================================================================
  # Scenario 3: Session reuse across multiple requests
  # =========================================================================

  describe 'Scenario 3: session reuse across multiple requests' do
    it 'reuses the same session for subsequent requests (no re-handshake)' do
      auth_fetch = build_auth_fetch(client_wallet, middleware)

      handshake_count = 0
      original_handle = BSV::Auth::AuthMiddleware.instance_method(:handle_auth_endpoint)

      allow_any_instance_of(BSV::Auth::AuthMiddleware).to receive(:handle_auth_endpoint) do |mw, env| # rubocop:disable RSpec/AnyInstance
        handshake_count += 1
        original_handle.bind(mw).call(env)
      end

      auth_fetch.fetch('http://example.com/protected')
      auth_fetch.fetch('http://example.com/protected')

      # Only one handshake should have occurred.
      expect(handshake_count).to eq(1)
    end

    it 'returns correct responses for all requests in the sequence' do
      auth_fetch = build_auth_fetch(client_wallet, middleware)

      r1 = auth_fetch.fetch('http://example.com/protected')
      r2 = auth_fetch.fetch('http://example.com/protected')

      expect(r1.status).to eq(200)
      expect(r2.status).to eq(200)
      expect(r1.body).to eq('secret data')
      expect(r2.body).to eq('secret data')
    end
  end

  # =========================================================================
  # Scenario 4: Certificate exchange post-handshake
  #
  # Exercises the BRC-104 certificate request/response flow over HTTP.
  # The server's AuthMiddleware peer requests certificates from the client
  # after the handshake is established.  Because the certificate exchange
  # happens via a separate HTTP POST to /.well-known/auth (not during the
  # initial request), this avoids nested synchronous HTTP call deadlocks.
  # =========================================================================

  describe 'Scenario 4: certificate exchange (server requests, client responds)' do
    let(:cert_type) { Base64.strict_encode64("\x04" * 32) }

    def issue_verifiable_certificate(subject_wallet:, certifier_wallet:, verifier_hex:, cert_type:, fields:)
      master_cert = BSV::Auth::MasterCertificate.issue_certificate_for_subject(
        certifier_wallet,
        subject_wallet.get_public_key({ identity_key: true })[:public_key],
        fields,
        cert_type
      )

      keyring = BSV::Auth::MasterCertificate.create_keyring_for_verifier(
        subject_wallet,
        certifier: master_cert.certifier,
        verifier: verifier_hex,
        fields: master_cert.fields,
        fields_to_reveal: fields.keys,
        master_keyring: master_cert.master_keyring,
        serial_number: master_cert.serial_number
      )

      BSV::Auth::VerifiableCertificate.from_certificate(master_cert, keyring)
    end

    it 'client wallet provides certificates when server requests them via requestedCertificates header' do
      certifier_hex = certifier_wallet.get_public_key({ identity_key: true })[:public_key]

      # Server requests certificates from the client in its initialResponse.
      server_sm = BSV::Auth::SessionManager.new
      mw = BSV::Auth::AuthMiddleware.new(
        downstream_app,
        wallet: server_wallet,
        session_manager: server_sm,
        certificates_to_request: {
          certifiers: [certifier_hex],
          types: { cert_type => ['name'] }
        }
      )

      # The client AuthFetch will receive a certificateRequest during the handshake.
      # We intercept Peer creation to register on_certificate_request before it fires.
      certs_sent_by_client = nil
      original_peer_new = BSV::Auth::Peer.method(:new)
      allow(BSV::Auth::Peer).to receive(:new) do |**kwargs|
        peer = original_peer_new.call(**kwargs)
        if kwargs[:wallet].equal?(client_wallet)
          peer.on_certificate_request do |requester_key, _requested|
            vc = issue_verifiable_certificate(
              subject_wallet: client_wallet,
              certifier_wallet: certifier_wallet,
              verifier_hex: requester_key,
              cert_type: cert_type,
              fields: { 'name' => 'Client' }
            )
            certs_sent_by_client = [vc]
            # Send the cert response in a separate thread to avoid deadlocking the
            # synchronous HTTP call chain.  The handshake will complete once this
            # POST to /.well-known/auth reaches the server.
            Thread.new { peer.send_certificate_response(requester_key, [vc]) }
          end
        end
        peer
      end

      rack_http = build_rack_http_client(mw)
      original_transport_new = BSV::Auth::SimplifiedFetchTransport.method(:new)
      allow(BSV::Auth::SimplifiedFetchTransport).to receive(:new) do |base_url, **opts|
        original_transport_new.call(base_url, http_client: rack_http, **opts)
      end

      auth_fetch = BSV::Auth::AuthFetch.new(wallet: client_wallet)
      response = auth_fetch.fetch('http://example.com/protected')

      expect(response.status).to eq(200)
      expect(certs_sent_by_client).not_to be_nil
    end
  end

  # =========================================================================
  # Scenario 5: Pass-through (no auth headers)
  # =========================================================================

  describe 'Scenario 5: pass-through request without auth headers' do
    it 'reaches the downstream app and returns its response directly' do
      # Call the middleware directly without going through AuthFetch.
      env = {
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => '/protected',
        'QUERY_STRING' => '',
        'rack.input' => StringIO.new(''),
        'rack.errors' => StringIO.new
      }

      status, _headers, body = middleware.call(env)

      expect(status).to eq(200)
      expect(body.join).to eq('secret data')
    end

    it 'does not add auth headers to pass-through responses' do
      env = {
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => '/protected',
        'QUERY_STRING' => '',
        'rack.input' => StringIO.new(''),
        'rack.errors' => StringIO.new
      }

      _status, headers, = middleware.call(env)

      expect(headers.keys.map(&:downcase)).not_to include(a_string_starting_with('x-bsv-auth'))
    end
  end

  # =========================================================================
  # Scenario 6: Invalid signature — server returns 401
  # =========================================================================

  describe 'Scenario 6: invalid signature returns 401' do
    it 'returns 401 when the request signature has been tampered' do
      # Perform the handshake legitimately first.
      server_sm = BSV::Auth::SessionManager.new
      mw        = BSV::Auth::AuthMiddleware.new(downstream_app, wallet: server_wallet,
                                                                session_manager: server_sm)
      auth_fetch = build_auth_fetch(client_wallet, mw)

      # First request triggers the handshake successfully.
      auth_fetch.fetch('http://example.com/protected')

      # Now send a request with a deliberately bad signature directly to the middleware.
      auth_fetch.instance_variable_get(:@peers)
                .values.first
                .session_manager
                .get_session(server_key.public_key.to_hex)

      server_session = server_sm.get_session(client_key.public_key.to_hex)
      server_nonce   = server_session.session_nonce

      request_id_b64 = Base64.strict_encode64(SecureRandom.random_bytes(32))
      client_nonce   = Base64.strict_encode64(SecureRandom.random_bytes(32))
      bad_sig        = 'ff' * 72

      env = {
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => '/protected',
        'QUERY_STRING' => '',
        'rack.input' => StringIO.new(''),
        'rack.errors' => StringIO.new,
        'HTTP_X_BSV_AUTH_VERSION' => '0.1',
        'HTTP_X_BSV_AUTH_IDENTITY_KEY' => client_key.public_key.to_hex,
        'HTTP_X_BSV_AUTH_NONCE' => client_nonce,
        'HTTP_X_BSV_AUTH_YOUR_NONCE' => server_nonce,
        'HTTP_X_BSV_AUTH_SIGNATURE' => bad_sig,
        'HTTP_X_BSV_AUTH_REQUEST_ID' => request_id_b64
      }

      status, = mw.call(env)
      expect(status).to eq(401)
    end
  end

  # =========================================================================
  # Scenario 7: Multiple clients connecting to the same server
  # =========================================================================

  describe 'Scenario 7: multiple clients connect to the same server independently' do
    it 'both clients authenticate and receive correct responses' do
      mw = middleware

      # Both clients share the same downstream middleware instance.
      fetch1 = build_auth_fetch(client_wallet, mw)

      # Reset the transport stub so the second client uses its own rack client.
      RSpec::Mocks.space.proxy_for(BSV::Auth::SimplifiedFetchTransport)&.reset

      fetch2 = build_auth_fetch(client2_wallet, mw)

      r1 = fetch1.fetch('http://example.com/protected')
      r2 = fetch2.fetch('http://example.com/protected')

      expect(r1.status).to eq(200)
      expect(r2.status).to eq(200)
      expect(r1.body).to eq('secret data')
      expect(r2.body).to eq('secret data')
    end

    it 'each client has an independent session in the server session manager' do
      server_sm = BSV::Auth::SessionManager.new
      mw = BSV::Auth::AuthMiddleware.new(downstream_app, wallet: server_wallet,
                                                         session_manager: server_sm)

      fetch1 = build_auth_fetch(client_wallet, mw)

      RSpec::Mocks.space.proxy_for(BSV::Auth::SimplifiedFetchTransport)&.reset

      fetch2 = build_auth_fetch(client2_wallet, mw)

      fetch1.fetch('http://example.com/protected')
      fetch2.fetch('http://example.com/protected')

      expect(server_sm.session?(client_key.public_key.to_hex)).to be(true)
      expect(server_sm.session?(client2_key.public_key.to_hex)).to be(true)
    end
  end

  # =========================================================================
  # Scenario 8: Binary / non-JSON response body
  # =========================================================================

  describe 'Scenario 8: binary response body is returned correctly' do
    let(:binary_app) do
      lambda do |env|
        case env['PATH_INFO']
        when '/blob'
          [200, { 'content-type' => 'application/octet-stream' }, ["\x00\x01\x02\x03\xFF"]]
        else
          [200, { 'content-type' => 'text/plain' }, ['ok']]
        end
      end
    end

    it 'returns the raw binary body unchanged' do
      mw         = BSV::Auth::AuthMiddleware.new(binary_app, wallet: server_wallet)
      auth_fetch = build_auth_fetch(client_wallet, mw)

      response = auth_fetch.fetch('http://example.com/blob')

      expect(response.status).to eq(200)
      expect(response.body.b).to eq("\x00\x01\x02\x03\xFF".b)
    end
  end

  # =========================================================================
  # Scenario 9: Stale session recovery (server restarts, client retries)
  # =========================================================================

  describe 'Scenario 9: stale session recovery after server restart' do
    it 'creates a fresh peer and succeeds when the first attempt raises Session not found' do
      # Simulate what happens when a server restarts: the client has an old peer cached,
      # then the peer raises "Session not found". AuthFetch should clear the cache and retry.
      call_count = 0

      auth_fetch = build_auth_fetch(client_wallet, middleware)

      original_to_peer = BSV::Auth::Peer.instance_method(:to_peer)
      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) do |peer, *args| # rubocop:disable RSpec/AnyInstance
        call_count += 1
        raise BSV::Auth::AuthError, 'Session not found for nonce: stale' if call_count == 1

        original_to_peer.bind(peer).call(*args)
      end

      # The first call fails with "Session not found", triggering a retry that succeeds.
      response = auth_fetch.fetch('http://example.com/protected')
      expect(response.status).to eq(200)
    end
  end
end
