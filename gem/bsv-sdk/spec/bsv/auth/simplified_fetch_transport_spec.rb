# frozen_string_literal: true

require 'spec_helper'
require 'base64'

RSpec.describe 'BSV::Auth::SimplifiedFetchTransport' do
  subject(:transport) { BSV::Auth::SimplifiedFetchTransport.new(base_url, http_client: mock_http_client) }

  let(:base_url) { 'https://api.example.com' }

  # A canned Net::HTTP response object.
  # We build a lightweight double matching Net::HTTP::HTTPResponse interface.
  let(:mock_response) do
    instance_double(
      Net::HTTPResponse,
      code: '200',
      body: '',
      each_header: nil
    )
  end

  # Configurable fake HTTP client (replaces Net::HTTP).
  # Captures the most-recent request for assertions, returns mock_response.
  let(:mock_http_client) do
    client_class = Class.new do
      attr_reader :last_request, :last_host, :last_port, :last_use_ssl

      def configure(response_factory)
        @response_factory = response_factory
      end

      def start(host, port, use_ssl: false)
        @last_host    = host
        @last_port    = port
        @last_use_ssl = use_ssl
        yield self
      end

      def request(req)
        @last_request = req
        @response_factory.call(req)
      end
    end.new

    client_class.configure(->(_req) { mock_response })
    client_class
  end

  # -------------------------------------------------------------------------
  # Helpers to build minimal binary payloads
  # -------------------------------------------------------------------------
  let(:request_nonce_bin) { ("\xAB" * 32).b }

  def build_serialised_payload(method: 'GET', path: '/api/data', query: nil, headers: [], body: nil)
    BSV::Auth::AuthPayload.serialize_request(
      request_nonce: request_nonce_bin,
      method: method,
      path: path,
      query: query,
      headers: headers,
      body: body
    )
  end

  def binary_to_array(bin)
    bin.bytes
  end

  def make_response_with_headers(headers_hash, body: '', code: '200')
    resp = instance_double(Net::HTTPResponse, code: code, body: body)
    allow(resp).to receive(:each_header) do |&block|
      headers_hash.each { |k, v| block.call(k.downcase, v) }
    end
    resp
  end

  # -------------------------------------------------------------------------
  # on_data
  # -------------------------------------------------------------------------
  describe '#on_data' do
    it 'stores the callback' do
      called_with = nil
      transport.on_data { |msg| called_with = msg }
      # Trigger via a non-general message send to test indirectly
      # (direct state inspection not needed — the behaviour test below covers it)
      expect(called_with).to be_nil # not called yet
    end
  end

  # -------------------------------------------------------------------------
  # Guard: send before on_data
  # -------------------------------------------------------------------------
  describe '#send without on_data registered' do
    it 'raises an error' do
      message = { version: '0.1', message_type: 'initialRequest', identity_key: 'aabbcc',
                  initial_nonce: 'nonce123', requested_certificates: {} }
      expect { transport.send(message) }.to raise_error(/on_data callback was registered/)
    end
  end

  # -------------------------------------------------------------------------
  # Non-general messages: POST JSON to /.well-known/auth
  # -------------------------------------------------------------------------
  describe '#send for non-general messages' do
    let(:camel_response) do
      { 'version' => '0.1',
        'messageType' => 'initialResponse',
        'identityKey' => 'aabbccdd',
        'initialNonce' => 'server_nonce',
        'yourNonce' => 'client_nonce' }
    end

    before do
      response_body_json = JSON.generate(camel_response)
      resp = instance_double(Net::HTTPResponse, code: '200', body: response_body_json)
      allow(resp).to receive(:each_header)
      mock_http_client.configure(->(_req) { resp })
    end

    it 'POSTs to /.well-known/auth' do
      received = nil
      transport.on_data { |msg| received = msg }

      message = {
        version: '0.1',
        message_type: 'initialRequest',
        identity_key: 'aabbcc',
        initial_nonce: 'my_nonce',
        requested_certificates: {}
      }
      transport.send(message)

      req = mock_http_client.last_request
      expect(req.path).to eq('/.well-known/auth')
      expect(req.method).to eq('POST')
    end

    it 'sends camelCase JSON body' do
      transport.on_data { |_msg| }

      message = {
        version: '0.1',
        message_type: 'initialRequest',
        identity_key: 'aabbcc',
        initial_nonce: 'my_nonce',
        requested_certificates: { certifiers: [] }
      }
      transport.send(message)

      parsed_body = JSON.parse(mock_http_client.last_request.body)
      expect(parsed_body).to include(
        'messageType' => 'initialRequest',
        'identityKey' => 'aabbcc',
        'initialNonce' => 'my_nonce',
        'requestedCertificates' => { 'certifiers' => [] }
      )
      # snake_case keys must NOT appear
      expect(parsed_body.keys).not_to include('message_type', 'identity_key')
    end

    it 'converts camelCase response to snake_case symbols in the callback' do
      received = nil
      transport.on_data { |msg| received = msg }

      message = { version: '0.1', message_type: 'initialRequest',
                  identity_key: 'aabbcc', initial_nonce: 'my_nonce',
                  requested_certificates: {} }
      transport.send(message)

      expect(received).to include(
        version: '0.1',
        message_type: 'initialResponse',
        identity_key: 'aabbccdd',
        initial_nonce: 'server_nonce',
        your_nonce: 'client_nonce'
      )
    end

    it 'sets Content-Type header to application/json' do
      transport.on_data { |_msg| }

      message = { version: '0.1', message_type: 'initialRequest',
                  identity_key: 'key', initial_nonce: 'n',
                  requested_certificates: {} }
      transport.send(message)

      expect(mock_http_client.last_request['content-type']).to eq('application/json')
    end

    it 'raises on non-2xx response' do
      err_resp = instance_double(Net::HTTPResponse, code: '403', body: 'Forbidden')
      allow(err_resp).to receive(:each_header)
      mock_http_client.configure(->(_req) { err_resp })

      transport.on_data { |_msg| }

      message = { version: '0.1', message_type: 'initialRequest',
                  identity_key: 'key', initial_nonce: 'n',
                  requested_certificates: {} }
      expect { transport.send(message) }.to raise_error(/HTTP 403/)
    end

    it 'uses HTTPS when base URL scheme is https' do
      transport.on_data { |_msg| }

      message = { version: '0.1', message_type: 'initialRequest',
                  identity_key: 'key', initial_nonce: 'n',
                  requested_certificates: {} }
      transport.send(message)

      expect(mock_http_client.last_use_ssl).to be true
    end
  end

  # -------------------------------------------------------------------------
  # General messages: reconstruct HTTP request from binary payload
  # -------------------------------------------------------------------------
  describe '#send for general messages' do
    let(:sig_bytes)       { [0xDE, 0xAD, 0xBE, 0xEF] }
    let(:sig_hex)         { 'deadbeef' }
    let(:request_id_b64)  { Base64.strict_encode64(request_nonce_bin) }

    let(:general_message) do
      payload_bin = build_serialised_payload(method: 'GET', path: '/api/resource', query: nil)
      {
        version: '0.1',
        message_type: 'general',
        identity_key: 'pubkey_hex',
        nonce: 'client_nonce',
        your_nonce: 'server_nonce',
        payload: binary_to_array(payload_bin),
        signature: sig_bytes
      }
    end

    let(:auth_response_headers) do
      {
        'x-bsv-auth-version' => '0.1',
        'x-bsv-auth-identity-key' => 'server_pubkey',
        'x-bsv-auth-signature' => 'cafebabe',
        'x-bsv-auth-nonce' => 'resp_nonce',
        'x-bsv-auth-your-nonce' => 'client_nonce'
      }
    end

    before do
      resp = make_response_with_headers(auth_response_headers, body: '{"ok":true}', code: '200')
      mock_http_client.configure(->(_req) { resp })
    end

    it 'sends GET to the correct path on the base URL' do
      transport.on_data { |_msg| }
      transport.send(general_message)

      req = mock_http_client.last_request
      expect(req.path).to eq('/api/resource')
      expect(req.method).to eq('GET')
    end

    it 'appends x-bsv-auth-version header' do
      transport.on_data { |_msg| }
      transport.send(general_message)

      expect(mock_http_client.last_request['x-bsv-auth-version']).to eq('0.1')
    end

    it 'appends x-bsv-auth-identity-key header' do
      transport.on_data { |_msg| }
      transport.send(general_message)

      expect(mock_http_client.last_request['x-bsv-auth-identity-key']).to eq('pubkey_hex')
    end

    it 'appends x-bsv-auth-nonce header' do
      transport.on_data { |_msg| }
      transport.send(general_message)

      expect(mock_http_client.last_request['x-bsv-auth-nonce']).to eq('client_nonce')
    end

    it 'appends x-bsv-auth-your-nonce header' do
      transport.on_data { |_msg| }
      transport.send(general_message)

      expect(mock_http_client.last_request['x-bsv-auth-your-nonce']).to eq('server_nonce')
    end

    it 'hex-encodes the signature into x-bsv-auth-signature' do
      transport.on_data { |_msg| }
      transport.send(general_message)

      expect(mock_http_client.last_request['x-bsv-auth-signature']).to eq(sig_hex)
    end

    it 'base64-encodes the request_id into x-bsv-auth-request-id' do
      transport.on_data { |_msg| }
      transport.send(general_message)

      expect(mock_http_client.last_request['x-bsv-auth-request-id']).to eq(request_id_b64)
    end

    it 'fires on_data callback with a response AuthMessage' do
      received = nil
      transport.on_data { |msg| received = msg }
      transport.send(general_message)

      expect(received).to include(
        version: '0.1',
        message_type: 'general',
        identity_key: 'server_pubkey'
      )
    end

    it 'hex-decodes the response signature back to a byte array' do
      received = nil
      transport.on_data { |msg| received = msg }
      transport.send(general_message)

      expect(received[:signature]).to eq([0xCA, 0xFE, 0xBA, 0xBE])
    end

    it 'sets message_type to certificateRequest when response header says so' do
      headers = auth_response_headers.merge('x-bsv-auth-message-type' => 'certificateRequest')
      resp    = make_response_with_headers(headers, body: '', code: '200')
      mock_http_client.configure(->(_req) { resp })

      received = nil
      transport.on_data { |msg| received = msg }
      transport.send(general_message)

      expect(received[:message_type]).to eq('certificateRequest')
    end

    it 'defaults message_type to general when response header is absent' do
      received = nil
      transport.on_data { |msg| received = msg }
      transport.send(general_message)

      expect(received[:message_type]).to eq('general')
    end

    it 'parses requested_certificates header as JSON when present' do
      certs_json = '{"certifiers":["abc"],"types":{}}'
      headers    = auth_response_headers.merge('x-bsv-auth-requested-certificates' => certs_json)
      resp       = make_response_with_headers(headers, body: '', code: '200')
      mock_http_client.configure(->(_req) { resp })

      received = nil
      transport.on_data { |msg| received = msg }
      transport.send(general_message)

      expect(received[:requested_certificates]).to eq({ 'certifiers' => ['abc'], 'types' => {} })
    end

    it 'raises when required auth headers are missing from the general response' do
      incomplete = auth_response_headers.except('x-bsv-auth-signature')
      resp       = make_response_with_headers(incomplete, body: 'oops', code: '200')
      mock_http_client.configure(->(_req) { resp })

      transport.on_data { |_msg| }
      expect { transport.send(general_message) }.to raise_error(/missing headers.*x-bsv-auth-signature/i)
    end

    it 'raises on network error with URL context' do
      mock_http_client.configure(->(_req) { raise SocketError, 'getaddrinfo: Name or service not known' })

      transport.on_data { |_msg| }
      expect { transport.send(general_message) }.to raise_error(/Network error.*api\.example\.com/)
    end

    it 'includes query string in the request path when present' do
      payload_bin = build_serialised_payload(method: 'GET', path: '/search', query: '?q=hello')
      msg = general_message.merge(payload: binary_to_array(payload_bin))

      transport.on_data { |_msg| }
      transport.send(msg)

      expect(mock_http_client.last_request.path).to eq('/search?q=hello')
    end

    it 'passes non-auth request headers from the payload' do
      headers_in  = [['content-type', 'application/json']]
      payload_bin = build_serialised_payload(
        method: 'POST', path: '/items', query: nil,
        headers: headers_in, body: '{"x":1}'
      )
      msg = general_message.merge(payload: binary_to_array(payload_bin))

      transport.on_data { |_msg| }
      transport.send(msg)

      expect(mock_http_client.last_request['content-type']).to eq('application/json')
    end
  end

  # -------------------------------------------------------------------------
  # Signature hex encoding round-trip
  # -------------------------------------------------------------------------
  describe 'signature hex encoding round-trip' do
    it 'converts Array<Integer> bytes to hex and back' do
      sig_bytes = (0..255).to_a
      transport_instance = BSV::Auth::SimplifiedFetchTransport.new(base_url)

      hex_encoded  = transport_instance.__send__(:signature_to_hex, sig_bytes)
      back_to_arr  = transport_instance.__send__(:hex_to_array, hex_encoded)

      expect(back_to_arr).to eq(sig_bytes)
    end

    it 'handles a string signature unchanged (already hex)' do
      hex_str = 'deadbeef'
      transport_instance = BSV::Auth::SimplifiedFetchTransport.new(base_url)

      result = transport_instance.__send__(:signature_to_hex, hex_str)
      expect(result).to eq('deadbeef')
    end
  end

  # -------------------------------------------------------------------------
  # Request ID base64 encoding round-trip
  # -------------------------------------------------------------------------
  describe 'request ID base64 encoding' do
    it 'base64-encodes the 32-byte request nonce' do
      nonce_bin = ("\xDE\xAD\xBE\xEF" * 8).b
      expected  = Base64.strict_encode64(nonce_bin)

      # Verify the header value set on the request
      payload_bin = BSV::Auth::AuthPayload.serialize_request(
        request_nonce: nonce_bin,
        method: 'GET',
        path: '/x',
        query: nil,
        headers: [],
        body: nil
      )

      auth_resp_headers = {
        'x-bsv-auth-version' => '0.1',
        'x-bsv-auth-identity-key' => 'pk',
        'x-bsv-auth-signature' => 'aa'
      }
      resp = make_response_with_headers(auth_resp_headers, body: '', code: '200')
      mock_http_client.configure(->(_req) { resp })

      transport.on_data { |_msg| }
      msg = {
        version: '0.1', message_type: 'general', identity_key: 'pk',
        nonce: 'n', your_nonce: 'y', signature: [0xAA],
        payload: payload_bin.bytes
      }
      transport.send(msg)

      expect(mock_http_client.last_request['x-bsv-auth-request-id']).to eq(expected)
    end
  end

  # -------------------------------------------------------------------------
  # Base URL path construction
  # -------------------------------------------------------------------------
  describe 'base URL path construction' do
    it 'strips trailing slash from base URL' do
      t = BSV::Auth::SimplifiedFetchTransport.new('https://example.com/', http_client: mock_http_client)

      resp = instance_double(Net::HTTPResponse, code: '200',
                                                body: JSON.generate({ 'messageType' => 'initialResponse', 'version' => '0.1' }))
      allow(resp).to receive(:each_header)
      mock_http_client.configure(->(_req) { resp })

      t.on_data { |_msg| }
      t.send(version: '0.1', message_type: 'initialRequest', identity_key: 'k',
             initial_nonce: 'n', requested_certificates: {})

      expect(mock_http_client.last_host).to eq('example.com')
    end

    it 'handles HTTP (non-SSL) base URLs' do
      t = BSV::Auth::SimplifiedFetchTransport.new('http://internal.example.com', http_client: mock_http_client)

      resp = instance_double(Net::HTTPResponse, code: '200',
                                                body: JSON.generate({ 'messageType' => 'initialResponse', 'version' => '0.1' }))
      allow(resp).to receive(:each_header)
      mock_http_client.configure(->(_req) { resp })

      t.on_data { |_msg| }
      t.send(version: '0.1', message_type: 'initialRequest', identity_key: 'k',
             initial_nonce: 'n', requested_certificates: {})

      expect(mock_http_client.last_use_ssl).to be false
    end
  end
end
