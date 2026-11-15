# frozen_string_literal: true

require 'pp'
require 'socket'

# Fake injectable HTTP client — records the last request, returns a canned response.
class ProtocolSpecFakeHttpClient
  attr_reader :last_uri, :last_request

  def initialize(response)
    @response = response
  end

  def request(uri, req)
    @last_uri     = uri
    @last_request = req
    @response
  end
end

require 'logger'

RSpec.describe 'BSV::Network::Protocol' do
  let(:base_protocol) do
    Class.new(BSV::Network::Protocol) do
      endpoint :get_tx,    :get,  '/v1/tx/{txid}'
      endpoint :broadcast, :post, '/v1/tx', response: :json
    end
  end

  let(:test_protocol_class) do
    Class.new(BSV::Network::Protocol) do
      endpoint :get_tx,    :get,  '/v1/tx/{txid}'
      endpoint :get_out,   :get,  '/v1/tx/{txid}/out/{vout}/hex'
      endpoint :broadcast, :post, '/v1/tx',    response: :json
      endpoint :get_info,  :get,  '/v1/info',  response: :json
      endpoint :get_raw,   :get,  '/v1/raw',   response: :raw
      endpoint :get_list,  :get,  '/v1/list',  response: :json_array
      endpoint :custom,    :get,  '/v1/custom', response: ->(body) { body.upcase } # rubocop:disable Style/SymbolProc
      subscription :on_tx, '/ws/tx'
    end
  end

  let(:ok_response)         { fake_http_response(200, 'raw_body') }
  let(:json_response)       { fake_http_response(200, '{"txid":"abc"}') }
  let(:array_response)      { fake_http_response(200, '[{"txid":"abc"}]') }
  let(:wrapped_array_resp)  { fake_http_response(200, '{"result":[{"txid":"abc"}],"error":""}') }
  let(:hash_no_result_resp) { fake_http_response(200, '{"address":"1abc","error":""}') }
  let(:not_found_response)  { fake_http_response(404, 'not found') }
  let(:too_many_response)   { fake_http_response(429, 'rate limited') }
  let(:server_error_resp)   { fake_http_response(500, 'server error') }
  let(:bad_request_resp)    { fake_http_response(400, 'bad request') }
  let(:bad_json_response)   { fake_http_response(200, 'not-json{') }

  def make_instance(response, api_key: nil)
    http = ProtocolSpecFakeHttpClient.new(response)
    test_protocol_class.new(base_url: 'https://api.example.com', api_key: api_key, http_client: http)
  end

  describe 'endpoint DSL' do
    it 'registers endpoints on the class' do
      eps = base_protocol.endpoints
      expect(eps[:get_tx]).to eq({ method: :get, path: '/v1/tx/{txid}', response: :raw })
      expect(eps[:broadcast]).to eq({ method: :post, path: '/v1/tx', response: :json })
    end

    it 'returns a frozen copy from .endpoints' do
      expect(base_protocol.endpoints).to be_frozen
    end
  end

  describe '.commands' do
    it 'returns a Set of declared command names' do
      expect(base_protocol.commands).to be_a(Set)
      expect(base_protocol.commands).to eq(Set[:get_tx, :broadcast])
    end

    it 'returns an empty Set when no endpoints are declared' do
      empty = Class.new(BSV::Network::Protocol)
      expect(empty.commands).to be_empty
    end
  end

  describe 'subclass isolation' do
    let(:child_protocol) do
      Class.new(base_protocol) do
        endpoint :health, :get, '/v1/health'
      end
    end

    it 'inherits parent endpoints' do
      expect(child_protocol.commands).to include(:get_tx, :broadcast)
    end

    it 'includes its own additional endpoints' do
      expect(child_protocol.commands).to include(:health)
    end

    it 'does not add child endpoints to the parent' do
      child_protocol # trigger class creation
      expect(base_protocol.commands).not_to include(:health)
    end

    it 'allows the child to override a parent endpoint' do
      override = Class.new(base_protocol) do
        endpoint :get_tx, :post, '/v2/tx/{txid}', response: :json
      end
      expect(override.endpoints[:get_tx]).to eq({ method: :post, path: '/v2/tx/{txid}', response: :json })
      expect(base_protocol.endpoints[:get_tx]).to eq({ method: :get, path: '/v1/tx/{txid}', response: :raw })
    end

    it 'sibling subclasses do not share endpoints' do
      sibling_a = Class.new(base_protocol) do
        endpoint :only_in_a, :get, '/only-a'
      end
      sibling_b = Class.new(base_protocol) do
        endpoint :only_in_b, :get, '/only-b'
      end
      expect(sibling_a.commands).not_to include(:only_in_b)
      expect(sibling_b.commands).not_to include(:only_in_a)
    end
  end

  describe 'subscription DSL' do
    let(:sub_protocol) do
      Class.new(BSV::Network::Protocol) do
        subscription :on_tx, '/ws/tx', event: 'tx'
      end
    end

    it 'stores the subscription definition without error' do
      expect(sub_protocol.subscriptions[:on_tx]).to eq({ path: '/ws/tx', event: 'tx' })
    end

    it 'returns a frozen copy from .subscriptions' do
      expect(sub_protocol.subscriptions).to be_frozen
    end

    it 'subscription does not appear in commands' do
      expect(sub_protocol.commands).not_to include(:on_tx)
    end
  end

  describe '#initialize' do
    let(:klass) { Class.new(BSV::Network::Protocol) }

    it 'stores base_url, api_key, network, and http_client' do
      client = Object.new
      p = klass.new(base_url: 'https://example.com', api_key: 'key123', network: 'main', http_client: client)
      expect(p.base_url).to eq('https://example.com')
      expect(p.api_key).to eq('key123')
      expect(p.network).to eq('main')
      expect(p.http_client).to be(client)
    end

    it 'interpolates {network} in base_url' do
      p = klass.new(base_url: 'https://api.example.com/v1/bsv/{network}', network: 'main')
      expect(p.base_url).to eq('https://api.example.com/v1/bsv/main')
    end

    it 'accepts a Symbol for network and converts it to string in the URL' do
      p = klass.new(base_url: 'https://api.example.com/{network}', network: :test)
      expect(p.base_url).to eq('https://api.example.com/test')
    end

    it 'strips trailing slash from base_url' do
      p = klass.new(base_url: 'https://example.com/')
      expect(p.base_url).to eq('https://example.com')
    end

    it 'strips trailing slash after network interpolation' do
      p = klass.new(base_url: 'https://example.com/{network}/', network: 'main')
      expect(p.base_url).to eq('https://example.com/main')
    end

    it 'raises ArgumentError when {network} is present but network: is not provided' do
      expect do
        klass.new(base_url: 'https://api.example.com/v1/bsv/{network}')
      end.to raise_error(ArgumentError, /network/)
    end

    it 'allows nil api_key and http_client' do
      p = klass.new(base_url: 'https://example.com')
      expect(p.api_key).to be_nil
      expect(p.http_client).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # HTTP dispatch
  # ---------------------------------------------------------------------------

  describe '#call — escape hatch dispatch' do
    it 'delegates to call_<name> when defined' do
      klass = Class.new(test_protocol_class) do
        def call_broadcast(*_args, **_kwargs)
          BSV::Network::ProtocolResponse.new(nil, data: 'escape_hatch', http_success: true)
        end
      end
      http     = ProtocolSpecFakeHttpClient.new(ok_response)
      instance = klass.new(base_url: 'https://api.example.com', http_client: http)
      result   = instance.call(:broadcast)
      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).to be_http_success
      expect(result.data).to eq('escape_hatch')
    end

    it 'forwards args and kwargs to the escape hatch' do
      received = {}
      klass = Class.new(test_protocol_class) do
        define_method(:call_get_tx) do |*args, **kwargs|
          received[:args]   = args
          received[:kwargs] = kwargs
          BSV::Network::ProtocolResponse.new(nil, http_success: true)
        end
      end
      http     = ProtocolSpecFakeHttpClient.new(ok_response)
      instance = klass.new(base_url: 'https://api.example.com', http_client: http)
      instance.call(:get_tx, 'abc123', extra: 'val')
      expect(received[:args]).to eq(['abc123'])
      expect(received[:kwargs]).to eq({ extra: 'val' })
    end

    it 'accepts escape hatch command as String' do
      klass = Class.new(test_protocol_class) do
        def call_get_tx(*_args, **_kwargs)
          BSV::Network::ProtocolResponse.new(nil, data: 'string_command', http_success: true)
        end
      end
      http     = ProtocolSpecFakeHttpClient.new(ok_response)
      instance = klass.new(base_url: 'https://api.example.com', http_client: http)
      expect(instance.call('get_tx', 'abc').data).to eq('string_command')
    end

    it 'raises NotImplementedError for subscription calls' do
      expect { make_instance(ok_response).call(:on_tx) }
        .to raise_error(NotImplementedError, /subscription/)
    end
  end

  describe '#call — falls through to HTTP' do
    it 'calls default_call when no escape hatch is defined' do
      result = make_instance(ok_response).call(:get_raw)
      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).to be_http_success
      expect(result.data).to eq('raw_body')
    end

    it 'raises ArgumentError for unknown command' do
      expect { make_instance(ok_response).call(:nonexistent) }
        .to raise_error(ArgumentError, /unknown command/)
    end
  end

  describe '#default_call — URL interpolation' do
    it 'interpolates a single positional arg' do
      http     = ProtocolSpecFakeHttpClient.new(ok_response)
      instance = test_protocol_class.new(base_url: 'https://api.example.com', http_client: http)
      instance.default_call(:get_tx, 'abc123')
      expect(http.last_uri.to_s).to eq('https://api.example.com/v1/tx/abc123')
    end

    it 'logs the origin and path of the request, never userinfo or query' do
      output = StringIO.new
      logger = Logger.new(output, level: Logger::DEBUG, formatter: ->(_severity, _time, _prog, msg) { "#{msg}\n" })
      allow(BSV).to receive(:logger).and_return(logger)
      http     = ProtocolSpecFakeHttpClient.new(ok_response)
      instance = test_protocol_class.new(base_url: 'https://user:secret@api.example.com/base?token=abc', http_client: http)
      instance.default_call(:get_tx, 'abc123')
      expect(output.string.lines.map(&:chomp)).to include('[Protocol] GET https://api.example.com/v1/tx/abc123')
      expect(output.string).not_to match(/secret|token/)
    end

    it 'never logs an error body, which may reflect the API key or be invalid UTF-8' do
      output = StringIO.new
      logger = Logger.new(output, level: Logger::DEBUG, formatter: ->(_severity, _time, _prog, msg) { "#{msg}\n" })
      allow(BSV).to receive(:logger).and_return(logger)
      body     = "{\"error\":\"bad key: Bearer SEKRET\"} caf\xC3".b
      instance = test_protocol_class.new(base_url: 'https://api.example.com', api_key: 'SEKRET',
                                         http_client: ProtocolSpecFakeHttpClient.new(fake_http_response('401', body)))
      result = instance.default_call(:get_tx, 'abc123')
      expect(result).not_to be_http_success
      expect(output.string).to include('[Protocol] HTTP 401 → http_success=false')
      expect(output.string).not_to include('SEKRET')
    end

    it 'interpolates multiple positional args in template order' do
      http     = ProtocolSpecFakeHttpClient.new(ok_response)
      instance = test_protocol_class.new(base_url: 'https://api.example.com', http_client: http)
      instance.default_call(:get_out, 'abc123', 0)
      expect(http.last_uri.to_s).to eq('https://api.example.com/v1/tx/abc123/out/0/hex')
    end

    it 'interpolates named kwargs' do
      http     = ProtocolSpecFakeHttpClient.new(ok_response)
      instance = test_protocol_class.new(base_url: 'https://api.example.com', http_client: http)
      instance.default_call(:get_tx, txid: 'xyz789')
      expect(http.last_uri.to_s).to eq('https://api.example.com/v1/tx/xyz789')
    end

    it 'named kwargs take precedence over positional args' do
      http     = ProtocolSpecFakeHttpClient.new(ok_response)
      instance = test_protocol_class.new(base_url: 'https://api.example.com', http_client: http)
      instance.default_call(:get_tx, 'positional', txid: 'named')
      expect(http.last_uri.to_s).to eq('https://api.example.com/v1/tx/named')
    end

    it 'raises ArgumentError when a required placeholder is missing' do
      expect { make_instance(ok_response).default_call(:get_tx) }
        .to raise_error(ArgumentError, /missing path parameter/)
    end

    it 'raises ArgumentError for unknown command' do
      expect { make_instance(ok_response).default_call(:no_such_cmd) }
        .to raise_error(ArgumentError, /unknown command/)
    end

    it 'bypasses any escape hatch method' do
      klass = Class.new(test_protocol_class) do
        def call_get_raw(*_args, **_kwargs)
          BSV::Network::ProtocolResponse.new(nil, data: 'escape', http_success: true)
        end
      end
      http     = ProtocolSpecFakeHttpClient.new(ok_response)
      instance = klass.new(base_url: 'https://api.example.com', http_client: http)
      expect(instance.default_call(:get_raw).data).to eq('raw_body')
    end
  end

  describe '#default_call — response handlers' do
    it ':raw returns body as a String' do
      result = make_instance(ok_response).default_call(:get_raw)
      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).to be_http_success
      expect(result.data).to eq('raw_body')
    end

    it ':json parses body to Hash' do
      result = make_instance(json_response).default_call(:get_info)
      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).to be_http_success
      expect(result.data).to eq({ 'txid' => 'abc' })
    end

    it ':json_array parses body to Array' do
      result = make_instance(array_response).default_call(:get_list)
      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).to be_http_success
      expect(result.data).to be_an(Array)
      expect(result.data.first).to eq({ 'txid' => 'abc' })
    end

    it ':json_array unwraps Hash with result key' do
      result = make_instance(wrapped_array_resp).default_call(:get_list)
      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).to be_http_success
      expect(result.data).to be_an(Array)
      expect(result.data.first).to eq({ 'txid' => 'abc' })
    end

    it ':json_array rejects Hash without result key' do
      result = make_instance(hash_no_result_resp).default_call(:get_list)
      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).not_to be_http_success
      expect(result.message).to include('expected Array, got Hash')
    end

    it 'custom lambda is called with body' do
      result = make_instance(ok_response).default_call(:custom)
      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).to be_http_success
      expect(result.data).to eq('RAW_BODY')
    end

    it 'JSON parse failure returns error ProtocolResponse' do
      result = make_instance(bad_json_response).default_call(:get_info)
      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).not_to be_http_success
      expect(result.message).to include('JSON/response error')
      expect(result.retryable?).to be(false)
    end
  end

  describe '#default_call — HTTP status mapping' do
    it '2xx returns successful ProtocolResponse' do
      result = make_instance(ok_response).default_call(:get_raw)
      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).to be_http_success
    end

    it '404 returns not_found ProtocolResponse' do
      result = make_instance(not_found_response).default_call(:get_raw)
      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).to be_http_not_found
    end

    it '429 returns retryable error ProtocolResponse' do
      result = make_instance(too_many_response).default_call(:get_raw)
      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).not_to be_http_success
      expect(result.retryable?).to be(true)
    end

    it '5xx returns retryable error ProtocolResponse' do
      result = make_instance(server_error_resp).default_call(:get_raw)
      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).not_to be_http_success
      expect(result.retryable?).to be(true)
    end

    it 'other 4xx returns non-retryable error ProtocolResponse' do
      result = make_instance(bad_request_resp).default_call(:get_raw)
      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).not_to be_http_success
      expect(result.retryable?).to be(false)
    end

    it 'error message contains response body' do
      expect(make_instance(bad_request_resp).default_call(:get_raw).message).to eq('bad request')
    end

    it 'response code is the HTTP status code string' do
      result = make_instance(not_found_response).default_call(:get_raw)
      expect(result.code).to eq('404')
    end
  end

  describe '#default_call — POST with body' do
    it 'sends body: kwarg as request body' do
      http     = ProtocolSpecFakeHttpClient.new(json_response)
      instance = test_protocol_class.new(base_url: 'https://api.example.com', http_client: http)
      instance.default_call(:broadcast, body: '{"rawTx":"deadbeef"}')
      expect(http.last_request.body).to eq('{"rawTx":"deadbeef"}')
    end

    it 'does not include body: in path interpolation' do
      http     = ProtocolSpecFakeHttpClient.new(json_response)
      instance = test_protocol_class.new(base_url: 'https://api.example.com', http_client: http)
      instance.default_call(:broadcast, body: 'data')
      expect(http.last_uri.to_s).to eq('https://api.example.com/v1/tx')
    end
  end

  describe '#default_call — Authorization header' do
    it 'sends Authorization: Bearer header when api_key is set (legacy shorthand)' do
      http     = ProtocolSpecFakeHttpClient.new(ok_response)
      instance = test_protocol_class.new(
        base_url: 'https://api.example.com',
        api_key: 'secret-key',
        http_client: http
      )
      instance.default_call(:get_raw)
      expect(http.last_request['Authorization']).to eq('Bearer secret-key')
    end

    it 'omits Authorization header when api_key is nil' do
      http     = ProtocolSpecFakeHttpClient.new(ok_response)
      instance = test_protocol_class.new(base_url: 'https://api.example.com', http_client: http)
      instance.default_call(:get_raw)
      expect(http.last_request['Authorization']).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Generic auth dispatch
  # ---------------------------------------------------------------------------

  def make_auth_instance(auth_opts)
    http = ProtocolSpecFakeHttpClient.new(ok_response)
    instance = test_protocol_class.new(base_url: 'https://api.example.com', http_client: http, **auth_opts)
    [instance, http]
  end

  describe '#default_call — generic auth dispatch' do
    it 'auth: { bearer: token } sends Authorization: Bearer token' do
      instance, http = make_auth_instance(auth: { bearer: 'my-token' })
      instance.default_call(:get_raw)
      expect(http.last_request['Authorization']).to eq('Bearer my-token')
    end

    it 'auth: { api_key: key } sends Authorization: key (no Bearer prefix)' do
      instance, http = make_auth_instance(auth: { api_key: 'raw-key' })
      instance.default_call(:get_raw)
      expect(http.last_request['Authorization']).to eq('raw-key')
    end

    it 'auth: { api_key: key, header: X-Custom } sends X-Custom: key' do
      instance, http = make_auth_instance(auth: { api_key: 'raw-key', header: 'X-Custom' })
      instance.default_call(:get_raw)
      expect(http.last_request['X-Custom']).to eq('raw-key')
      expect(http.last_request['Authorization']).to be_nil
    end

    it 'auth: :none sends no Authorization header' do
      instance, http = make_auth_instance(auth: :none)
      instance.default_call(:get_raw)
      expect(http.last_request['Authorization']).to be_nil
    end

    it 'no auth options sends no Authorization header' do
      instance, http = make_auth_instance({})
      instance.default_call(:get_raw)
      expect(http.last_request['Authorization']).to be_nil
    end

    it 'auth: takes precedence over api_key: when both are provided' do
      http = ProtocolSpecFakeHttpClient.new(ok_response)
      instance = test_protocol_class.new(
        base_url: 'https://api.example.com',
        api_key: 'legacy-key',
        auth: { bearer: 'auth-token' },
        http_client: http
      )
      instance.default_call(:get_raw)
      expect(http.last_request['Authorization']).to eq('Bearer auth-token')
    end

    it 'auth: { bearer: empty } sends Authorization: Bearer with empty value' do
      instance, http = make_auth_instance(auth: { bearer: '' })
      instance.default_call(:get_raw)
      expect(http.last_request['Authorization']).to eq('Bearer ')
    end
  end

  # ---------------------------------------------------------------------------
  # Transport-level error handling — closes #807 (T4).
  #
  # The base #default_call catches the common HTTP transport errors that can
  # surface from Net::HTTP or its injectable substitute (Net::HTTP.start, a
  # ProtocolSpecFakeHttpClient, etc.). Each is converted to a structured
  # ProtocolResponse with http_success: false and a descriptive error_message
  # rather than propagated to the protocol caller as a raw exception.
  # ---------------------------------------------------------------------------

  describe 'transport-level error handling' do
    # Fake client whose #request raises the supplied exception instead of
    # returning an HTTP response.
    let(:raising_client) do
      Class.new do
        def initialize(error)
          @error = error
        end

        def request(_uri, _request)
          raise @error
        end
      end
    end

    def call_with_error(error)
      instance = test_protocol_class.new(
        base_url: 'https://api.example.com',
        http_client: raising_client.new(error)
      )
      instance.default_call(:get_raw)
    end

    [
      [SocketError.new('Failed to resolve hostname'),                'DNS / unreachable host'],
      [Errno::ECONNREFUSED.new,                                      'connection refused'],
      [Errno::ETIMEDOUT.new,                                         'connect timed out'],
      [Errno::EHOSTUNREACH.new,                                      'host unreachable'],
      [Errno::ENETUNREACH.new,                                       'network unreachable'],
      [Net::OpenTimeout.new('execution expired'),                    'open timeout'],
      [Net::ReadTimeout.new('execution expired'),                    'read timeout'],
      [Net::HTTPBadResponse.new('wrong status line'),                'bad HTTP response'],
      [Net::HTTPHeaderSyntaxError.new('bad header'),                 'malformed HTTP header'],
      [OpenSSL::SSL::SSLError.new('certificate verify failed'),      'SSL error']
    ].each do |error, label|
      context "when the transport raises #{error.class}" do
        let(:result) { call_with_error(error) }

        it "returns a ProtocolResponse with http_success: false (#{label})" do
          expect(result).to be_a(BSV::Network::ProtocolResponse)
          expect(result.http_success?).to be(false)
        end

        it "captures the exception class in error_message (#{label})" do
          expect(result.error_message).to include('transport error:').and include(error.class.name)
        end

        it "leaves body / code / content_type nil-safe (#{label})" do
          expect(result.body).to be_nil
          expect(result.code).to be_nil
          expect(result.content_type).to be_nil
        end
      end
    end

    # Anything outside the catch list still propagates — the base class
    # only handles transport-shaped exceptions, not programmer errors.
    it 'does not swallow non-transport exceptions (RuntimeError propagates)' do
      instance = test_protocol_class.new(
        base_url: 'https://api.example.com',
        http_client: raising_client.new(RuntimeError.new('boom'))
      )
      expect { instance.default_call(:get_raw) }.to raise_error(RuntimeError, 'boom')
    end
  end

  describe 'transport errors across dispatch paths' do
    let(:escape_hatch_class) do
      Class.new(BSV::Network::Protocol) do
        endpoint :get_raw, :get, '/v1/raw'

        def call_hatch(*)
          execute(URI("#{base_url}/v1/hatch"), Net::HTTP::Get.new('/v1/hatch'))
          BSV::Network::ProtocolResponse.new(nil, data: 'unreachable')
        end

        def call_invalid(*)
          raise ArgumentError, 'bad input'
        end

        def call_delegating(*)
          default_call(:get_raw)
        end
      end
    end

    let(:raising_client) do
      Class.new do
        def initialize(error)
          @error = error
        end

        def request(_uri, _request)
          raise @error
        end
      end
    end

    def build_with_error(error)
      escape_hatch_class.new(base_url: 'https://api.example.com', http_client: raising_client.new(error))
    end

    [
      Net::OpenTimeout.new('execution expired'),
      Net::ReadTimeout.new('Net::ReadTimeout'),
      Net::WriteTimeout.new('Net::WriteTimeout'),
      Errno::ECONNREFUSED.new,
      Errno::ECONNRESET.new,
      Errno::EPIPE.new,
      EOFError.new('end of file reached'),
      SocketError.new('getaddrinfo failed'),
      OpenSSL::SSL::SSLError.new('certificate verify failed')
    ].each do |error|
      context "when the transport raises #{error.class}" do
        it 'returns a failed response from a default_call command' do
          result = build_with_error(error).call(:get_raw)
          expect(result.http_success?).to be(false)
          expect(result.error_message).to start_with("transport error: #{error.class}: ")
        end

        it 'returns a failed response from an escape hatch that calls execute' do
          result = build_with_error(error).call(:hatch)
          expect(result.http_success?).to be(false)
          expect(result.error_message).to start_with("transport error: #{error.class}: ")
        end

        it 'returns a failed response from an escape hatch that delegates to default_call' do
          result = build_with_error(error).call(:delegating)
          expect(result.http_success?).to be(false)
          expect(result.error_message).to start_with("transport error: #{error.class}: ")
        end

        it 'flags whether the request may have reached the service' do
          message = build_with_error(error).call(:get_raw).error_message
          not_sent = [SocketError, Net::OpenTimeout, Errno::ECONNREFUSED].any? { |klass| error.is_a?(klass) }
          if not_sent
            expect(message).not_to include('may have reached')
          else
            expect(message).to end_with('(the request may have reached the service)')
          end
        end
      end
    end

    [
      Errno::EHOSTUNREACH.new,
      Errno::ENETUNREACH.new,
      Net::HTTPBadResponse.new('wrong status line'),
      Net::HTTPHeaderSyntaxError.new('bad header'),
      Errno::ETIMEDOUT.new
    ].each do |error|
      it "says the request may have reached the service for #{error.class}" do
        message = build_with_error(error).call(:get_raw).error_message
        expect(message).to end_with('(the request may have reached the service)')
      end
    end

    it 'strips control characters from the transport error text' do
      error = Net::HTTPBadResponse.new("wrong chunk size line: \e[K\r[WRN] x")
      message = build_with_error(error).call(:get_raw).error_message
      expect(message).to eq('transport error: Net::HTTPBadResponse: wrong chunk size line: [K [WRN] x ' \
                            '(the request may have reached the service)')
      expect(message).not_to match(/[[:cntrl:]]/)
    end

    it 'falls back to the class name when the error text is blank' do
      message = build_with_error(EOFError.new("\r\n")).call(:get_raw).error_message
      expect(message).to start_with('transport error: EOFError: EOFError')
    end

    it 'lets ArgumentError from an escape hatch propagate' do
      instance = build_with_error(EOFError.new)
      expect { instance.call(:invalid) }.to raise_error(ArgumentError, 'bad input')
    end
  end

  describe 'HTTP timeouts' do
    let(:escape_hatch_class) do
      Class.new(BSV::Network::Protocol) do
        endpoint :get_raw, :get, '/v1/raw'

        def call_hatch(*)
          response = execute(URI("#{base_url}/v1/hatch"), Net::HTTP::Get.new('/v1/hatch'))
          BSV::Network::ProtocolResponse.new(response, data: response.body)
        end
      end
    end

    let(:expected_options) do
      hash_including(open_timeout: 10, read_timeout: 30, write_timeout: 30, max_retries: 0, use_ssl: true)
    end

    it 'passes named timeouts and disables retries for a default_call command' do
      recorder = stub_net_http('api.example.com' => ->(_req) { [200, 'ok'] })
      escape_hatch_class.new(base_url: 'https://api.example.com').call(:get_raw)
      expect(recorder.start_options).to contain_exactly(expected_options)
    end

    it 'passes the same options for an escape hatch that calls execute directly' do
      recorder = stub_net_http('api.example.com' => ->(_req) { [200, 'ok'] })
      escape_hatch_class.new(base_url: 'https://api.example.com').call(:hatch)
      expect(recorder.start_options).to contain_exactly(expected_options)
    end

    context 'with a server that accepts but never replies' do
      let(:server) { TCPServer.new('127.0.0.1', 0) }
      let(:accepted) { [] }
      let!(:acceptor) do
        Thread.new do
          loop { accepted << server.accept }
        rescue IOError
          nil
        end
      end

      after do
        server.close
        acceptor.join(1)
        accepted.each(&:close)
      end

      it 'returns a failed response after one read timeout without retrying' do
        stub_const('BSV::Network::Protocol::READ_TIMEOUT', 0.2)
        instance = escape_hatch_class.new(base_url: "http://127.0.0.1:#{server.addr[1]}")

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = instance.call(:get_raw)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

        expect(result.http_success?).to be(false)
        expect(result.error_message).to include('Net::ReadTimeout')
        expect(elapsed).to be < 0.4
        expect(accepted.size).to eq(1)
      end
    end
  end

  describe 'credential-free inspection' do
    let(:secrets) { %w[SEKRET pw tok apikey] }

    def renderings(object)
      [object.inspect, object.to_s, PP.pp(object, +''), [object].inspect]
    end

    {
      'legacy api_key' => { base_url: 'https://host.example', api_key: 'SEKRET' },
      'bearer auth' => { base_url: 'https://host.example', auth: { bearer: 'SEKRET' } },
      'header api_key auth' => { base_url: 'https://host.example', auth: { api_key: 'SEKRET', header: 'X-Api' } },
      'userinfo, path and query in the URL' => { base_url: 'https://user:pw@host.example/tok?apikey=q' }
    }.each do |label, options|
      it "never reveals secrets for #{label}" do
        instance = base_protocol.new(**options)
        renderings(instance).each do |text|
          secrets.each { |secret| expect(text).not_to include(secret) }
          expect(text).to include('host.example')
        end
      end
    end

    it 'shows the class, origin and auth status' do
      instance = test_protocol_class.new(base_url: 'https://api.example.com:8443/v1', api_key: 'SEKRET')
      expect(instance.inspect).to eq(
        "#<#{test_protocol_class} origin=\"https://api.example.com:8443\" auth=authenticated>"
      )
    end

    it 'omits the default port' do
      instance = test_protocol_class.new(base_url: 'https://api.example.com:443')
      expect(instance.inspect).to eq("#<#{test_protocol_class} origin=\"https://api.example.com\" auth=unauthenticated>")
    end

    it 'does not raise for an unparseable base URL' do
      instance = test_protocol_class.new(base_url: 'not a url')
      expect(instance.inspect).to include('(unparseable)')
    end

    describe '#authenticated?' do
      it 'is true for the legacy api_key' do
        expect(base_protocol.new(base_url: 'https://h.example', api_key: 'k').authenticated?).to be(true)
      end

      it 'is true for bearer auth' do
        expect(base_protocol.new(base_url: 'https://h.example', auth: { bearer: 'k' }).authenticated?).to be(true)
      end

      it 'is true for api_key auth' do
        expect(base_protocol.new(base_url: 'https://h.example', auth: { api_key: 'k' }).authenticated?).to be(true)
      end

      it 'is false with no auth, an empty api_key or auth: :none' do
        expect(base_protocol.new(base_url: 'https://h.example').authenticated?).to be(false)
        expect(base_protocol.new(base_url: 'https://h.example', api_key: '').authenticated?).to be(false)
        expect(base_protocol.new(base_url: 'https://h.example', auth: :none).authenticated?).to be(false)
      end
    end

    protocol_classes = BSV::Network::Protocols.constants.filter_map do |name|
      klass = BSV::Network::Protocols.const_get(name)
      [name, klass] if klass.is_a?(Class) && klass < BSV::Network::Protocol
    end

    protocol_classes.each do |name, klass|
      it "never reveals secrets for #{name}" do
        accepted = klass.instance_method(:initialize).parameters.map(&:last)
        options = { base_url: 'https://host.example/path', api_key: 'SEKRET' }
        options[:callback_token] = 'SEKRET' if accepted.include?(:callback_token)
        options[:callback_url] = 'https://hook.example/tok' if accepted.include?(:callback_url)
        options[:deployment_id] = 'SEKRET' if accepted.include?(:deployment_id)
        instance = klass.new(**options)

        renderings(instance).each do |text|
          expect(text).not_to include('SEKRET')
          expect(text).not_to include('tok')
        end
      end
    end
  end
end
