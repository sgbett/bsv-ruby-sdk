# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'rack'
require 'rack/mock_request'
require 'base64'
require 'json'
require 'stringio'

RSpec.describe 'BSV::Auth::AuthMiddleware' do
  # Deterministic keys for reproducibility.
  subject(:middleware) do
    BSV::Auth::AuthMiddleware.new(downstream_app, wallet: server_wallet)
  end

  let(:server_key) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(20)) }
  let(:client_key) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(21)) }

  let(:server_wallet) { BSV::Wallet::Client.new(server_key, storage: BSV::Wallet::MemoryStore.new) }
  let(:client_wallet) { BSV::Wallet::Client.new(client_key, storage: BSV::Wallet::MemoryStore.new) }

  # Simple downstream app that echoes its request body.
  let(:downstream_app) do
    lambda do |env|
      body = env['rack.input'].read
      [200, { 'content-type' => 'application/json' }, [body.empty? ? '{"ok":true}' : body]]
    end
  end

  # Helper: build a Rack env hash for a simple request.
  def rack_env(method: 'GET', path: '/', query: '', body: '', headers: {})
    input = StringIO.new(body)
    env = {
      'REQUEST_METHOD' => method,
      'PATH_INFO' => path,
      'QUERY_STRING' => query,
      'rack.input' => input,
      'rack.errors' => StringIO.new
    }
    headers.each do |k, v|
      rack_key = "HTTP_#{k.upcase.tr('-', '_')}"
      env[rack_key] = v
    end
    env
  end

  # --------------------------------------------------------------------------
  # Pass-through
  # --------------------------------------------------------------------------

  describe 'pass-through (no auth headers)' do
    it 'calls the downstream app unchanged' do
      env = rack_env(method: 'GET', path: '/api/data')
      status, _, body = middleware.call(env)

      expect(status).to eq(200)
      expect(body.join).to eq('{"ok":true}')
    end

    it 'does not add auth headers to the response' do
      env = rack_env(method: 'GET', path: '/api/data')
      _, headers, = middleware.call(env)

      expect(headers.keys.map(&:downcase)).not_to include(a_string_starting_with('x-bsv-auth'))
    end

    it 'passes through POST requests without auth headers' do
      env = rack_env(method: 'POST', path: '/data', body: '{"payload":1}')
      status, _, body = middleware.call(env)

      expect(status).to eq(200)
      expect(body.join).to eq('{"payload":1}')
    end
  end

  # --------------------------------------------------------------------------
  # /.well-known/auth handshake
  # --------------------------------------------------------------------------

  describe 'POST /.well-known/auth' do
    # Performs a full BRC-31 handshake through the middleware.
    # Returns [status, parsed_json_response].
    def post_to_auth_endpoint(body_hash)
      body_json = JSON.generate(body_hash)
      env = rack_env(method: 'POST', path: '/.well-known/auth', body: body_json)
      status, headers, response_body = middleware.call(env)
      [status, JSON.parse(response_body.join), headers]
    end

    context 'with a valid initialRequest' do
      # Build an initialRequest as a client Peer would produce.
      let(:client_session_manager) { BSV::Auth::SessionManager.new }
      let(:client_bridge) { build_client_bridge }

      # We build a client peer whose transport does NOT auto-deliver (we control delivery).
      let(:client_peer) do
        BSV::Auth::Peer.new(
          wallet: client_wallet,
          transport: client_bridge,
          session_manager: client_session_manager
        )
      end

      def build_client_bridge
        bridge        = Object.new
        outbox        = Queue.new
        inbox_cb_ref  = [nil]

        bridge.extend(BSV::Auth::Transport)
        bridge.define_singleton_method(:send)    { |msg| outbox.push(msg) }
        bridge.define_singleton_method(:on_data) { |&blk| inbox_cb_ref[0] = blk }
        bridge.define_singleton_method(:deliver) { |msg| inbox_cb_ref[0]&.call(msg) }
        bridge.define_singleton_method(:pop_sent) do
          outbox.pop(true)
        rescue ThreadError
          nil
        end

        bridge
      end

      it 'returns 200 with an initialResponse JSON body' do
        # Force client peer to be created
        client_peer

        # Extract the initialRequest the client wants to send
        request_msg = client_peer.send(:create_initial_request)
        camel_msg   = request_msg.transform_keys { |k| k.to_s.gsub(/_([a-z])/) { Regexp.last_match(1).upcase } }

        status, body, = post_to_auth_endpoint(camel_msg)

        expect(status).to eq(200)
        expect(body['messageType']).to eq('initialResponse')
        expect(body['version']).to eq('0.1')
        expect(body).to have_key('identityKey')
        expect(body).to have_key('initialNonce')
        expect(body).to have_key('yourNonce')
        expect(body).to have_key('signature')
      end

      it 'sets the identityKey to the server identity key in the response' do
        client_peer

        request_msg = client_peer.send(:create_initial_request)
        camel_msg   = request_msg.transform_keys { |k| k.to_s.gsub(/_([a-z])/) { Regexp.last_match(1).upcase } }

        _, body, = post_to_auth_endpoint(camel_msg)

        expect(body['identityKey']).to eq(server_key.public_key.to_hex)
      end

      it 'creates a session for the client in the server session manager' do
        client_peer

        request_msg = client_peer.send(:create_initial_request)
        camel_msg   = request_msg.transform_keys { |k| k.to_s.gsub(/_([a-z])/) { Regexp.last_match(1).upcase } }

        post_to_auth_endpoint(camel_msg)

        expect(middleware.instance_variable_get(:@session_manager).session?(client_key.public_key.to_hex)).to be(true)
      end
    end

    context 'with an empty body' do
      it 'returns 400' do
        env = rack_env(method: 'POST', path: '/.well-known/auth', body: '')
        status, = middleware.call(env)
        expect(status).to eq(400)
      end
    end

    context 'with invalid JSON' do
      it 'returns 400' do
        env = rack_env(method: 'POST', path: '/.well-known/auth', body: 'not json')
        status, = middleware.call(env)
        expect(status).to eq(400)
      end
    end

    context 'with a GET to /.well-known/auth' do
      it 'passes through to the downstream app (not intercepted)' do
        env = rack_env(method: 'GET', path: '/.well-known/auth')
        status, = middleware.call(env)
        # downstream returns 200
        expect(status).to eq(200)
      end
    end
  end

  # --------------------------------------------------------------------------
  # Authenticated requests
  # --------------------------------------------------------------------------

  describe 'authenticated request (x-bsv-auth-* headers)' do
    # Performs a full handshake so that the server has a session for the client,
    # and the client has a session for the server.  Returns [client_peer, session_nonce].
    def perform_handshake
      middleware.instance_variable_get(:@session_manager)
      client_sm = BSV::Auth::SessionManager.new

      # We need a client peer that uses our server's session manager to route
      # responses back properly.  We implement the handshake manually:
      #
      # 1. Client creates initialRequest
      # 2. POST to /.well-known/auth → server processes → initialResponse
      # 3. Client processes initialResponse → session established on both sides

      # Step 1: client creates request
      # We create a disposable client peer with a capturing transport.
      sent_messages = []
      received_callback = nil

      client_transport = Object.new
      client_transport.extend(BSV::Auth::Transport)
      client_transport.define_singleton_method(:send)    { |msg| sent_messages << msg }
      client_transport.define_singleton_method(:on_data) { |&blk| received_callback = blk }

      client_peer = BSV::Auth::Peer.new(
        wallet: client_wallet,
        transport: client_transport,
        session_manager: client_sm
      )

      request_msg = client_peer.send(:create_initial_request)
      camel_msg   = snake_to_camel_hash(request_msg)

      # Step 2: POST to middleware
      body_json = JSON.generate(camel_msg)
      env = rack_env(method: 'POST', path: '/.well-known/auth', body: body_json)
      _, _, resp_body = middleware.call(env)

      response_json = JSON.parse(resp_body.join)
      response_sym  = camel_to_snake_hash(response_json)

      # Step 3: client processes initialResponse
      # Manually call handle_incoming_message since our transport is passive
      client_peer.send(:handle_incoming_message, response_sym)

      # Return the client peer and the server session nonce
      # The server session nonce is "yourNonce" echoed back (our initial_nonce)
      [client_peer, client_sm, request_msg[:initial_nonce]]
    end

    def snake_to_camel_hash(hash)
      hash.transform_keys { |k| k.to_s.gsub(/_([a-z])/) { Regexp.last_match(1).upcase } }
    end

    def camel_to_snake_hash(hash)
      hash.transform_keys do |k|
        str = k.to_s
        str.gsub(/([A-Z])/) { "_#{Regexp.last_match(1).downcase}" }.sub(/^_/, '').to_sym
      end
    end

    # Builds a signed general-message Rack env for the client to send.
    def build_auth_request_env(client_peer:, server_session_nonce:, method: 'GET', path: '/api/data', query: '', body: '') # rubocop:disable Metrics/ParameterLists
      request_id_bin = SecureRandom.random_bytes(32)
      request_id_b64 = Base64.strict_encode64(request_id_bin)

      content_type = body.empty? ? nil : 'application/json'
      filtered_headers = content_type ? [['content-type', content_type]] : []

      payload_bin = BSV::Auth::AuthPayload.serialize_request(
        request_nonce: request_id_bin,
        method: method,
        path: path,
        query: query.empty? ? nil : query,
        headers: filtered_headers,
        body: body.empty? ? nil : body
      )

      # Look up the client session for the server
      client_session = client_peer.session_manager.get_session(server_key.public_key.to_hex)
      raise 'No client session for server' unless client_session

      client_nonce = Base64.strict_encode64(SecureRandom.random_bytes(32))
      key_id = "#{client_nonce} #{client_session.peer_nonce}"

      sig_result = client_wallet.create_signature({
                                                    data: payload_bin.bytes,
                                                    protocol_id: BSV::Auth::Peer::AUTH_PROTOCOL,
                                                    key_id: key_id,
                                                    counterparty: server_key.public_key.to_hex
                                                  })

      sig_hex = sig_result[:signature].pack('C*').unpack1('H*')

      headers = {
        'x-bsv-auth-version' => '0.1',
        'x-bsv-auth-identity-key' => client_key.public_key.to_hex,
        'x-bsv-auth-nonce' => client_nonce,
        'x-bsv-auth-your-nonce' => server_session_nonce,
        'x-bsv-auth-signature' => sig_hex,
        'x-bsv-auth-request-id' => request_id_b64
      }
      headers['content-type'] = content_type if content_type

      rack_env(method: method, path: path, query: query, body: body, headers: headers)
    end

    context 'with a valid authenticated GET' do
      it 'returns 200 with x-bsv-auth-* response headers' do
        client_peer, = perform_handshake
        server_session_nonce = middleware.instance_variable_get(:@session_manager)
                                         .get_session(client_key.public_key.to_hex)
                                         .session_nonce

        env = build_auth_request_env(
          client_peer: client_peer,
          method: 'GET',
          path: '/api/data',
          server_session_nonce: server_session_nonce
        )

        status, headers, = middleware.call(env)

        expect(status).to eq(200)
        expect(headers).to have_key(BSV::Auth::AuthHeaders::VERSION)
        expect(headers).to have_key(BSV::Auth::AuthHeaders::IDENTITY_KEY)
        expect(headers).to have_key(BSV::Auth::AuthHeaders::NONCE)
        expect(headers).to have_key(BSV::Auth::AuthHeaders::YOUR_NONCE)
        expect(headers).to have_key(BSV::Auth::AuthHeaders::SIGNATURE)
        expect(headers).to have_key(BSV::Auth::AuthHeaders::REQUEST_ID)
      end

      it 'sets the response identity-key to the server identity key' do
        client_peer, = perform_handshake
        server_session_nonce = middleware.instance_variable_get(:@session_manager)
                                         .get_session(client_key.public_key.to_hex)
                                         .session_nonce

        env = build_auth_request_env(
          client_peer: client_peer,
          method: 'GET',
          path: '/api/data',
          server_session_nonce: server_session_nonce
        )

        _, headers, = middleware.call(env)

        expect(headers[BSV::Auth::AuthHeaders::IDENTITY_KEY]).to eq(server_key.public_key.to_hex)
      end

      it 'returns the client session nonce as your-nonce in the response' do
        client_peer, = perform_handshake
        server_session_nonce = middleware.instance_variable_get(:@session_manager)
                                         .get_session(client_key.public_key.to_hex)
                                         .session_nonce

        # The client's session nonce is the nonce the client created during the handshake.
        # The server returns this in your-nonce so the client can verify it and look up the session.
        client_session_nonce = client_peer.session_manager
                                          .get_session(server_key.public_key.to_hex)
                                          .session_nonce

        request_id_bin = SecureRandom.random_bytes(32)
        request_id_b64 = Base64.strict_encode64(request_id_bin)
        client_nonce   = Base64.strict_encode64(SecureRandom.random_bytes(32))

        client_session = client_peer.session_manager.get_session(server_key.public_key.to_hex)
        key_id = "#{client_nonce} #{client_session.peer_nonce}"

        payload_bin = BSV::Auth::AuthPayload.serialize_request(
          request_nonce: request_id_bin,
          method: 'GET', path: '/api/data', query: nil, headers: [], body: nil
        )

        sig_result = client_wallet.create_signature({
                                                      data: payload_bin.bytes,
                                                      protocol_id: BSV::Auth::Peer::AUTH_PROTOCOL,
                                                      key_id: key_id,
                                                      counterparty: server_key.public_key.to_hex
                                                    })

        sig_hex = sig_result[:signature].pack('C*').unpack1('H*')

        env = rack_env(method: 'GET', path: '/api/data', headers: {
                         'x-bsv-auth-version' => '0.1',
                         'x-bsv-auth-identity-key' => client_key.public_key.to_hex,
                         'x-bsv-auth-nonce' => client_nonce,
                         'x-bsv-auth-your-nonce' => server_session_nonce,
                         'x-bsv-auth-signature' => sig_hex,
                         'x-bsv-auth-request-id' => request_id_b64
                       })

        _, headers, = middleware.call(env)

        expect(headers[BSV::Auth::AuthHeaders::YOUR_NONCE]).to eq(client_session_nonce)
      end
    end

    context 'with a valid authenticated POST with body' do
      it 'allows the downstream app to read the body' do
        client_peer, = perform_handshake
        server_session_nonce = middleware.instance_variable_get(:@session_manager)
                                         .get_session(client_key.public_key.to_hex)
                                         .session_nonce

        env = build_auth_request_env(
          client_peer: client_peer,
          method: 'POST',
          path: '/api/data',
          body: '{"hello":"world"}',
          server_session_nonce: server_session_nonce
        )

        status, _, body = middleware.call(env)

        expect(status).to eq(200)
        expect(body.join).to eq('{"hello":"world"}')
      end
    end

    context 'with an invalid signature' do
      it 'returns 401' do
        perform_handshake
        server_session_nonce = middleware.instance_variable_get(:@session_manager)
                                         .get_session(client_key.public_key.to_hex)
                                         .session_nonce

        request_id_b64 = Base64.strict_encode64(SecureRandom.random_bytes(32))
        client_nonce   = Base64.strict_encode64(SecureRandom.random_bytes(32))
        bad_sig        = 'ff' * 71

        env = rack_env(method: 'GET', path: '/api/data', headers: {
                         'x-bsv-auth-version' => '0.1',
                         'x-bsv-auth-identity-key' => client_key.public_key.to_hex,
                         'x-bsv-auth-nonce' => client_nonce,
                         'x-bsv-auth-your-nonce' => server_session_nonce,
                         'x-bsv-auth-signature' => bad_sig,
                         'x-bsv-auth-request-id' => request_id_b64
                       })

        status, = middleware.call(env)
        expect(status).to eq(401)
      end
    end

    context 'with missing required auth headers' do
      it 'returns 401 when signature header is missing' do
        env = rack_env(method: 'GET', path: '/api/data', headers: {
                         'x-bsv-auth-version' => '0.1',
                         'x-bsv-auth-identity-key' => client_key.public_key.to_hex,
                         'x-bsv-auth-nonce' => Base64.strict_encode64(SecureRandom.random_bytes(32)),
                         'x-bsv-auth-your-nonce' => Base64.strict_encode64(SecureRandom.random_bytes(32))
                         # signature and request_id omitted
                       })

        status, = middleware.call(env)
        expect(status).to eq(401)
      end
    end

    context 'with a session lookup failure' do
      it 'returns 401 when your_nonce does not match any session' do
        # No handshake performed — unknown nonce
        unknown_nonce  = Base64.strict_encode64(SecureRandom.random_bytes(32))
        request_id_b64 = Base64.strict_encode64(SecureRandom.random_bytes(32))
        client_nonce   = Base64.strict_encode64(SecureRandom.random_bytes(32))

        # Build a plausible-looking (but unverifiable) signature payload
        payload_bin = BSV::Auth::AuthPayload.serialize_request(
          request_nonce: Base64.strict_decode64(request_id_b64),
          method: 'GET', path: '/api/data', query: nil, headers: [], body: nil
        )

        sig_result = client_wallet.create_signature({
                                                      data: payload_bin.bytes,
                                                      protocol_id: BSV::Auth::Peer::AUTH_PROTOCOL,
                                                      key_id: "#{client_nonce} #{unknown_nonce}",
                                                      counterparty: server_key.public_key.to_hex
                                                    })
        sig_hex = sig_result[:signature].pack('C*').unpack1('H*')

        env = rack_env(method: 'GET', path: '/api/data', headers: {
                         'x-bsv-auth-version' => '0.1',
                         'x-bsv-auth-identity-key' => client_key.public_key.to_hex,
                         'x-bsv-auth-nonce' => client_nonce,
                         'x-bsv-auth-your-nonce' => unknown_nonce,
                         'x-bsv-auth-signature' => sig_hex,
                         'x-bsv-auth-request-id' => request_id_b64
                       })

        status, = middleware.call(env)
        expect(status).to eq(401)
      end
    end
  end

  # --------------------------------------------------------------------------
  # Body rewind
  # --------------------------------------------------------------------------

  describe 'body rewind after auth verification' do
    it 'allows the downstream app to read the body after middleware verification' do
      # We need a real handshake first
      client_sm = BSV::Auth::SessionManager.new
      sent_msgs = []
      received_cb = nil

      t = Object.new
      t.extend(BSV::Auth::Transport)
      t.define_singleton_method(:send)    { |msg| sent_msgs << msg }
      t.define_singleton_method(:on_data) { |&blk| received_cb = blk }

      cp = BSV::Auth::Peer.new(wallet: client_wallet, transport: t, session_manager: client_sm)
      req_msg  = cp.send(:create_initial_request)
      camel    = req_msg.transform_keys { |k| k.to_s.gsub(/_([a-z])/) { Regexp.last_match(1).upcase } }
      body_json = JSON.generate(camel)
      env = rack_env(method: 'POST', path: '/.well-known/auth', body: body_json)
      _, _, resp_body = middleware.call(env)
      resp_sym = JSON.parse(resp_body.join).transform_keys do |k|
        k.to_s.gsub(/([A-Z])/) { "_#{Regexp.last_match(1).downcase}" }.sub(/^_/, '').to_sym
      end
      cp.send(:handle_incoming_message, resp_sym)

      server_session = middleware.instance_variable_get(:@session_manager)
                                 .get_session(client_key.public_key.to_hex)
      server_session_nonce = server_session.session_nonce
      client_session = client_sm.get_session(server_key.public_key.to_hex)

      request_id_bin = SecureRandom.random_bytes(32)
      request_id_b64 = Base64.strict_encode64(request_id_bin)
      client_nonce   = Base64.strict_encode64(SecureRandom.random_bytes(32))

      post_body = '{"data":"rewind-test"}'
      payload_bin = BSV::Auth::AuthPayload.serialize_request(
        request_nonce: request_id_bin,
        method: 'POST', path: '/echo', query: nil,
        headers: [['content-type', 'application/json']],
        body: post_body
      )
      key_id = "#{client_nonce} #{client_session.peer_nonce}"
      sig_result = client_wallet.create_signature({
                                                    data: payload_bin.bytes,
                                                    protocol_id: BSV::Auth::Peer::AUTH_PROTOCOL,
                                                    key_id: key_id,
                                                    counterparty: server_key.public_key.to_hex
                                                  })
      sig_hex = sig_result[:signature].pack('C*').unpack1('H*')

      env = rack_env(method: 'POST', path: '/echo', body: post_body, headers: {
                       'content-type' => 'application/json',
                       'x-bsv-auth-version' => '0.1',
                       'x-bsv-auth-identity-key' => client_key.public_key.to_hex,
                       'x-bsv-auth-nonce' => client_nonce,
                       'x-bsv-auth-your-nonce' => server_session_nonce,
                       'x-bsv-auth-signature' => sig_hex,
                       'x-bsv-auth-request-id' => request_id_b64
                     })

      status, _, response_body = middleware.call(env)

      expect(status).to eq(200)
      expect(response_body.join).to eq(post_body)
    end
  end
end
