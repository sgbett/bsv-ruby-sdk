# frozen_string_literal: true

# Minimal fake response used in place of Net::HTTPResponse.
ProtocolSpecFakeResponse = Struct.new(:code, :body)

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

  let(:ok_response)        { ProtocolSpecFakeResponse.new('200', 'raw_body') }
  let(:json_response)      { ProtocolSpecFakeResponse.new('200', '{"txid":"abc"}') }
  let(:array_response)     { ProtocolSpecFakeResponse.new('200', '[{"txid":"abc"}]') }
  let(:not_found_response) { ProtocolSpecFakeResponse.new('404', 'not found') }
  let(:too_many_response)  { ProtocolSpecFakeResponse.new('429', 'rate limited') }
  let(:server_error_resp)  { ProtocolSpecFakeResponse.new('500', 'server error') }
  let(:bad_request_resp)   { ProtocolSpecFakeResponse.new('400', 'bad request') }
  let(:bad_json_response)  { ProtocolSpecFakeResponse.new('200', 'not-json{') }

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
  # HTTP dispatch (Task 3)
  # ---------------------------------------------------------------------------

  describe '#call — escape hatch dispatch' do
    it 'delegates to call_<name> when defined' do
      klass = Class.new(test_protocol_class) do
        def call_broadcast(*_args, **_kwargs)
          BSV::Network::Result::Success.new(data: 'escape_hatch')
        end
      end
      http     = ProtocolSpecFakeHttpClient.new(ok_response)
      instance = klass.new(base_url: 'https://api.example.com', http_client: http)
      result   = instance.call(:broadcast)
      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq('escape_hatch')
    end

    it 'forwards args and kwargs to the escape hatch' do
      received = {}
      klass = Class.new(test_protocol_class) do
        define_method(:call_get_tx) do |*args, **kwargs|
          received[:args]   = args
          received[:kwargs] = kwargs
          BSV::Network::Result::Success.new(data: nil)
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
          BSV::Network::Result::Success.new(data: 'string_command')
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
      expect(result).to be_a(BSV::Network::Result::Success)
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
          BSV::Network::Result::Success.new(data: 'escape')
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
      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq('raw_body')
    end

    it ':json parses body to Hash' do
      result = make_instance(json_response).default_call(:get_info)
      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq({ 'txid' => 'abc' })
    end

    it ':json_array parses body to Array' do
      result = make_instance(array_response).default_call(:get_list)
      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to be_an(Array)
      expect(result.data.first).to eq({ 'txid' => 'abc' })
    end

    it 'custom lambda is called with body' do
      result = make_instance(ok_response).default_call(:custom)
      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data).to eq('RAW_BODY')
    end

    it 'JSON parse failure returns Result::Error' do
      result = make_instance(bad_json_response).default_call(:get_info)
      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.message).to match(%r{JSON/response error})
      expect(result.retryable?).to be(false)
    end
  end

  describe '#default_call — HTTP status mapping' do
    it '2xx returns Result::Success' do
      expect(make_instance(ok_response).default_call(:get_raw))
        .to be_a(BSV::Network::Result::Success)
    end

    it '404 returns Result::NotFound' do
      expect(make_instance(not_found_response).default_call(:get_raw))
        .to be_a(BSV::Network::Result::NotFound)
    end

    it '429 returns Result::Error with retryable: true' do
      result = make_instance(too_many_response).default_call(:get_raw)
      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end

    it '5xx returns Result::Error with retryable: true' do
      result = make_instance(server_error_resp).default_call(:get_raw)
      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(true)
    end

    it 'other 4xx returns Result::Error with retryable: false' do
      result = make_instance(bad_request_resp).default_call(:get_raw)
      expect(result).to be_a(BSV::Network::Result::Error)
      expect(result.retryable?).to be(false)
    end

    it 'Error message contains response body' do
      expect(make_instance(bad_request_resp).default_call(:get_raw).message).to eq('bad request')
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
    it 'sends Authorization: Bearer header when api_key is set' do
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
end
