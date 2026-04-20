# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'
require 'base64'
require 'json'
require_relative '../../support/paired_transport'

RSpec.describe 'BSV::Auth::AuthFetch' do
  # Deterministic keys for reproducibility
  let(:client_key)  { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(42)) }
  let(:server_key)  { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(43)) }
  let(:client_wallet) { BSV::Wallet::Client.new(client_key, storage: BSV::Wallet::MemoryStore.new) }
  let(:server_wallet) { BSV::Wallet::Client.new(server_key, storage: BSV::Wallet::MemoryStore.new) }

  let(:base_url) { 'https://api.example.com' }

  # -------------------------------------------------------------------------
  # Mock HTTP client factory
  # -------------------------------------------------------------------------
  #
  # Builds a fake http_client class that:
  #  - responds to .start(host, port, use_ssl:) { |h| ... }
  #  - on request, calls the provided response_factory lambda
  #
  def build_http_client(response_factory)
    Class.new do
      define_method(:start) do |_host, _port, use_ssl: false, &block| # rubocop:disable Lint/UnusedBlockArgument
        block.call(self)
      end

      define_method(:request) do |req|
        response_factory.call(req)
      end
    end.new
  end

  # Builds a fake Net::HTTPResponse-like object.
  def build_response(code:, body:, headers: {})
    resp = instance_double(Net::HTTPResponse, code: code.to_s, body: body)
    allow(resp).to receive(:each_header) do |&blk|
      headers.each { |k, v| blk.call(k.downcase, v) }
    end
    resp
  end

  # Builds a valid set of BSV auth response headers for a given request nonce.
  # The server peer signs the payload and provides its own auth headers.
  def auth_response_headers_for(request_nonce_b64, server_identity_key, nonce: 'abc123', your_nonce: 'xyz456')
    {
      BSV::Auth::AuthHeaders::VERSION => BSV::Auth::AUTH_VERSION,
      BSV::Auth::AuthHeaders::IDENTITY_KEY => server_identity_key,
      BSV::Auth::AuthHeaders::NONCE => nonce,
      BSV::Auth::AuthHeaders::YOUR_NONCE => your_nonce,
      BSV::Auth::AuthHeaders::REQUEST_ID => request_nonce_b64,
      BSV::Auth::AuthHeaders::SIGNATURE => 'aabbcc',
      BSV::Auth::AuthHeaders::MESSAGE_TYPE => BSV::Auth::MSG_GENERAL
    }
  end

  # -------------------------------------------------------------------------
  # AuthResponse value object
  # -------------------------------------------------------------------------

  describe 'BSV::Auth::AuthResponse' do
    subject(:response) do
      BSV::Auth::AuthResponse.new(
        status: 200,
        headers: { 'content-type' => 'application/json' },
        body: '{"ok":true}',
        identity_key: 'deadbeef'
      )
    end

    it 'exposes status' do
      expect(response.status).to eq(200)
    end

    it 'exposes headers' do
      expect(response.headers).to eq('content-type' => 'application/json')
    end

    it 'exposes body' do
      expect(response.body).to eq('{"ok":true}')
    end

    it 'exposes identity_key' do
      expect(response.identity_key).to eq('deadbeef')
    end
  end

  # -------------------------------------------------------------------------
  # Constructor
  # -------------------------------------------------------------------------

  describe '.new' do
    it 'accepts wallet keyword' do
      expect { BSV::Auth::AuthFetch.new(wallet: client_wallet) }.not_to raise_error
    end

    it 'accepts optional requested_certificates' do
      certs = { certifiers: [], types: {} }
      expect do
        BSV::Auth::AuthFetch.new(wallet: client_wallet, requested_certificates: certs)
      end.not_to raise_error
    end

    it 'accepts optional session_manager' do
      sm = BSV::Auth::SessionManager.new
      expect do
        BSV::Auth::AuthFetch.new(wallet: client_wallet, session_manager: sm)
      end.not_to raise_error
    end
  end

  # -------------------------------------------------------------------------
  # Header filtering
  # -------------------------------------------------------------------------

  describe '#fetch — header filtering' do
    subject(:client) { BSV::Auth::AuthFetch.new(wallet: client_wallet) }

    # Stub to_peer so the handshake does not attempt a real TCP connection.
    # Tests that reach to_peer hang in the response queue — raise Timeout to stop them.
    before do
      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) { raise Timeout::Error } # rubocop:disable RSpec/AnyInstance
    end

    it 'raises ArgumentError for disallowed headers before any network call' do
      expect do
        client.fetch("#{base_url}/resource", headers: { 'x-custom-header' => 'value' })
      end.to raise_error(ArgumentError, /Unsupported header/)
    end

    it 'raises ArgumentError for x-bsv-auth-* headers' do
      expect do
        client.fetch("#{base_url}/resource",
                     headers: { 'x-bsv-auth-nonce' => 'some-value' })
      end.to raise_error(ArgumentError, /BSV auth headers are not allowed/)
    end

    it 'allows x-bsv-* (non-auth) headers without raising ArgumentError' do
      expect do
        client.fetch("#{base_url}/resource", headers: { 'x-bsv-custom' => 'ok' })
      end.to raise_error(Timeout::Error)
    end

    it 'allows authorization header without raising ArgumentError' do
      expect do
        client.fetch("#{base_url}/resource", headers: { 'authorization' => 'Bearer token' })
      end.to raise_error(Timeout::Error)
    end

    it 'allows content-type header without raising ArgumentError' do
      expect do
        client.fetch("#{base_url}/resource", headers: { 'content-type' => 'application/json' })
      end.to raise_error(Timeout::Error)
    end
  end

  # -------------------------------------------------------------------------
  # Content-type normalisation
  # -------------------------------------------------------------------------

  describe '#fetch — content-type normalisation' do
    before do
      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) { raise Timeout::Error } # rubocop:disable RSpec/AnyInstance
    end

    it 'strips charset parameter from content-type before signing' do
      headers_captured = nil
      allow(BSV::Auth::AuthPayload).to receive(:serialize_request) do |**kwargs|
        headers_captured = kwargs[:headers]
        "\x00" * 32
      end

      client = BSV::Auth::AuthFetch.new(wallet: client_wallet)
      begin
        client.fetch("#{base_url}/data",
                     method: 'POST',
                     headers: { 'content-type' => 'application/json; charset=utf-8' })
      rescue Timeout::Error
        # expected — we only care about the captured headers
      end

      expect(headers_captured).to include(['content-type', 'application/json'])
    end
  end

  # -------------------------------------------------------------------------
  # Body normalisation
  # -------------------------------------------------------------------------

  describe '#fetch — body normalisation' do
    let(:client) { BSV::Auth::AuthFetch.new(wallet: client_wallet) }

    before do
      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) { raise Timeout::Error } # rubocop:disable RSpec/AnyInstance
    end

    it 'serialises a Hash body to JSON and sets content-type to application/json' do
      headers_captured = nil
      body_captured    = nil
      allow(BSV::Auth::AuthPayload).to receive(:serialize_request) do |**kwargs|
        headers_captured = kwargs[:headers]
        body_captured    = kwargs[:body]
        "\x00" * 32
      end

      begin
        client.fetch("#{base_url}/post", method: 'POST', body: { name: 'alice', value: 42 })
      rescue Timeout::Error
        # expected
      end

      expect(body_captured).to eq(JSON.generate({ name: 'alice', value: 42 }))
      expect(headers_captured).to include(['content-type', 'application/json'])
    end

    it 'passes a String body through unchanged' do
      body_captured = nil
      allow(BSV::Auth::AuthPayload).to receive(:serialize_request) do |**kwargs|
        body_captured = kwargs[:body]
        "\x00" * 32
      end

      begin
        client.fetch("#{base_url}/post", method: 'POST', body: 'raw string body')
      rescue Timeout::Error
        # expected
      end

      expect(body_captured).to eq('raw string body')
    end

    it 'does not override an explicit content-type when the body is a Hash' do
      headers_captured = nil
      allow(BSV::Auth::AuthPayload).to receive(:serialize_request) do |**kwargs|
        headers_captured = kwargs[:headers]
        "\x00" * 32
      end

      begin
        client.fetch("#{base_url}/post",
                     method: 'POST',
                     headers: { 'content-type' => 'application/json' },
                     body: { key: 'val' })
      rescue Timeout::Error
        # expected
      end

      ct_count = headers_captured.count { |k, _| k == 'content-type' }
      expect(ct_count).to eq(1)
    end
  end

  # -------------------------------------------------------------------------
  # Peer caching
  # -------------------------------------------------------------------------

  describe '#fetch — peer caching' do
    let(:client) { BSV::Auth::AuthFetch.new(wallet: client_wallet) }

    before do
      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) { raise Timeout::Error } # rubocop:disable RSpec/AnyInstance
    end

    it 'reuses the same Peer for two requests to the same base URL' do
      peers_created = []
      original_new  = BSV::Auth::Peer.method(:new)

      allow(BSV::Auth::Peer).to receive(:new) do |**kwargs|
        peer = original_new.call(**kwargs)
        peers_created << peer
        peer
      end

      2.times do
        client.fetch("#{base_url}/resource")
      rescue Timeout::Error
        # expected
      end

      expect(peers_created.length).to eq(1)
    end

    it 'creates different Peers for different base URLs' do
      peers_created = []
      original_new  = BSV::Auth::Peer.method(:new)

      allow(BSV::Auth::Peer).to receive(:new) do |**kwargs|
        peer = original_new.call(**kwargs)
        peers_created << peer
        peer
      end

      %w[https://api.example.com https://other.example.com].each do |url|
        client.fetch("#{url}/resource")
      rescue Timeout::Error
        # expected
      end

      expect(peers_created.length).to eq(2)
    end
  end

  # -------------------------------------------------------------------------
  # URL parsing
  # -------------------------------------------------------------------------

  describe '#fetch — URL parsing' do
    let(:client) { BSV::Auth::AuthFetch.new(wallet: client_wallet) }

    before do
      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) { raise Timeout::Error } # rubocop:disable RSpec/AnyInstance
    end

    it 'omits default port 443 from HTTPS base URL' do
      original_transport_new = BSV::Auth::SimplifiedFetchTransport.method(:new)
      bases_seen = []

      allow(BSV::Auth::SimplifiedFetchTransport).to receive(:new) do |base, **opts|
        bases_seen << base
        original_transport_new.call(base, **opts)
      end

      begin
        client.fetch('https://api.example.com:443/path')
      rescue Timeout::Error
        # expected
      end

      expect(bases_seen.first).to eq('https://api.example.com')
    end

    it 'includes non-default port in base URL' do
      original_transport_new = BSV::Auth::SimplifiedFetchTransport.method(:new)
      bases_seen = []

      allow(BSV::Auth::SimplifiedFetchTransport).to receive(:new) do |base, **opts|
        bases_seen << base
        original_transport_new.call(base, **opts)
      end

      begin
        client.fetch('https://api.example.com:8443/path')
      rescue Timeout::Error
        # expected
      end

      expect(bases_seen.first).to eq('https://api.example.com:8443')
    end
  end

  # -------------------------------------------------------------------------
  # Stale session recovery
  # -------------------------------------------------------------------------

  describe '#fetch — stale session recovery' do
    it 'retries with a fresh peer when AuthError includes "Session not found"' do
      call_count = 0
      BSV::Auth::Peer.instance_method(:to_peer)

      # First call raises "Session not found"; second call raises Timeout to stop
      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) do |_peer, *_args| # rubocop:disable RSpec/AnyInstance
        call_count += 1
        raise BSV::Auth::AuthError, 'Session not found for nonce: abc' if call_count == 1

        raise Timeout::Error
      end

      # Two different peer instances should be created (original + retry)
      peers_created = 0
      original_new  = BSV::Auth::Peer.method(:new)
      allow(BSV::Auth::Peer).to receive(:new) do |**kwargs|
        peers_created += 1
        original_new.call(**kwargs)
      end

      client = BSV::Auth::AuthFetch.new(wallet: client_wallet)
      expect do
        client.fetch("#{base_url}/resource", timeout: 0.001)
      end.to raise_error(Timeout::Error)

      expect(call_count).to eq(2)
      expect(peers_created).to eq(2)
    end

    it 'does not retry for non-stale AuthErrors' do
      call_count = 0
      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) do # rubocop:disable RSpec/AnyInstance
        call_count += 1
        raise BSV::Auth::AuthError, 'Handshake timed out'
      end

      client = BSV::Auth::AuthFetch.new(wallet: client_wallet)
      expect do
        client.fetch("#{base_url}/resource", timeout: 5)
      end.to raise_error(BSV::Auth::AuthError, /Handshake timed out/)

      expect(call_count).to eq(1)
    end
  end

  # -------------------------------------------------------------------------
  # Request nonce matching
  # -------------------------------------------------------------------------

  describe '#fetch — response nonce matching' do
    it 'ignores a general message whose first 32 bytes do not match the request nonce' do
      # Build a server-side peer that echoes back a payload with the WRONG nonce
      client = BSV::Auth::AuthFetch.new(wallet: client_wallet)

      wrong_nonce   = SecureRandom.random_bytes(32)
      response_sent = false

      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) do |peer, _payload| # rubocop:disable RSpec/AnyInstance
        # Fire a general-message callback with wrong nonce — should NOT satisfy the queue
        response_sent = true
        wrong_payload = (wrong_nonce + ("\x00" * 4)).bytes
        peer.send(:fire_callbacks, :general_message, 'server-key', wrong_payload)
      end

      expect do
        client.fetch("#{base_url}/resource", timeout: 0.05)
      end.to raise_error(Timeout::Error)

      expect(response_sent).to be(true)
    end
  end

  # -------------------------------------------------------------------------
  # Timeout
  # -------------------------------------------------------------------------

  describe '#fetch — timeout' do
    it 'raises Timeout::Error when no response arrives within the timeout' do
      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) # rubocop:disable RSpec/AnyInstance

      client = BSV::Auth::AuthFetch.new(wallet: client_wallet)
      expect do
        client.fetch("#{base_url}/resource", timeout: 0.01)
      end.to raise_error(Timeout::Error, /AuthFetch timed out/)
    end
  end

  # -------------------------------------------------------------------------
  # Successful response deserialization
  # -------------------------------------------------------------------------

  describe '#fetch — successful response' do
    it 'returns AuthResponse with status, headers, body, and identity_key' do
      client          = BSV::Auth::AuthFetch.new(wallet: client_wallet)
      server_pub_key  = server_key.public_key.to_hex
      captured_nonce  = nil

      allow(BSV::Auth::AuthPayload).to receive(:serialize_request).and_wrap_original do |original, **kwargs|
        captured_nonce = kwargs[:request_nonce]
        original.call(**kwargs)
      end

      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) do |peer, _payload| # rubocop:disable RSpec/AnyInstance
        # Build a valid serialised response with the matching nonce
        response_binary = BSV::Auth::AuthPayload.serialize_response(
          request_id: captured_nonce,
          status: 200,
          headers: [%w[x-bsv-custom hello]],
          body: 'response body'
        )

        peer.send(:fire_callbacks, :general_message, server_pub_key, response_binary.bytes)
      end

      response = client.fetch("#{base_url}/resource")

      expect(response.status).to eq(200)
      expect(response.headers).to eq('x-bsv-custom' => 'hello')
      expect(response.body).to eq('response body')
      expect(response.identity_key).to eq(server_pub_key)
    end
  end

  # -------------------------------------------------------------------------
  # nil body default for POST with JSON content-type
  # -------------------------------------------------------------------------

  describe '#fetch — nil body default for POST + JSON' do
    before do
      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) { raise Timeout::Error } # rubocop:disable RSpec/AnyInstance
    end

    it 'passes body as nil to AuthPayload (which applies the {} default internally)' do
      body_captured = :not_set
      allow(BSV::Auth::AuthPayload).to receive(:serialize_request) do |**kwargs|
        body_captured = kwargs[:body]
        "\x00" * 32
      end

      client = BSV::Auth::AuthFetch.new(wallet: client_wallet)
      begin
        client.fetch("#{base_url}/post",
                     method: 'POST',
                     headers: { 'content-type' => 'application/json' })
      rescue Timeout::Error
        # expected
      end

      # AuthFetch passes nil body through; AuthPayload.serialize_request applies {} default
      expect(body_captured).to be_nil
    end
  end

  # -------------------------------------------------------------------------
  # Thread safety
  # -------------------------------------------------------------------------

  describe '#fetch — thread safety' do
    it 'does not corrupt @peers when multiple threads access the same base URL concurrently' do
      client = BSV::Auth::AuthFetch.new(wallet: client_wallet)

      # All threads will time out; we just want no race-condition errors
      threads = 5.times.map do
        Thread.new do
          client.fetch("#{base_url}/resource", timeout: 0.01)
        rescue Timeout::Error
          # expected
        rescue StandardError
          # any other error is captured by Thread — thread will report it
        end
      end

      threads.each(&:join)

      # Only one peer should exist for this base URL after all threads finish
      peers_hash = client.instance_variable_get(:@peers)
      expect(peers_hash.keys.length).to eq(1)
    end
  end
end
