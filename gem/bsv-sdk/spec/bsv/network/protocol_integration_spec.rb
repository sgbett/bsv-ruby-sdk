# frozen_string_literal: true

# rubocop:disable RSpec/DescribeClass

# rubocop:disable Style/OneClassPerFile

# Injectable HTTP client that records the last call and returns a canned response.
class IntegrationFakeHttpClient
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

# A concrete Protocol subclass used throughout the integration spec.
#
# Endpoints:
#   :get_item        GET  /items/{id}          — raw response
#   :create_item     POST /items               — raw response
#   :get_info        GET  /info                — JSON response
#   :get_count       GET  /count               — lambda response (body.to_i)
#   :on_item_change  subscription placeholder
#
# Escape hatch:
#   call_transform_item calls default_call(:get_item, ...) then wraps the data.
class TestIntegrationProtocol < BSV::Network::Protocol
  endpoint :get_item, :get, '/items/{id}'
  endpoint :create_item, :post, '/items'
  endpoint :get_info,   :get,  '/info',  response: :json
  endpoint :get_count,  :get,  '/count', response: lambda(&:to_i)

  subscription :on_item_change, '/ws/items'

  # Escape hatch: delegates to the default GET path then augments the result.
  def call_transform_item(*args, **kwargs)
    result = default_call(:get_item, *args, **kwargs)
    return result unless result.http_success?

    result.with(data: result.data.upcase)
  end
end

# rubocop:enable Style/OneClassPerFile

RSpec.describe 'BSV::Network::Protocol — integration' do
  let(:ok_response)       { fake_http_response(200, 'item_body') }
  let(:created_response)  { fake_http_response(201, 'created') }
  let(:json_response)     { fake_http_response(200, '{"version":"1.0"}') }
  let(:count_response)    { fake_http_response(200, '42') }
  let(:not_found_resp)    { fake_http_response(404, 'not found') }
  let(:server_error_resp) { fake_http_response(500, 'internal error') }
  let(:auth_error_resp)   { fake_http_response(401, 'unauthorised') }

  def make_client(response, api_key: nil)
    http = IntegrationFakeHttpClient.new(response)
    instance = TestIntegrationProtocol.new(
      base_url: 'https://api.example.com',
      api_key: api_key,
      http_client: http
    )
    [instance, http]
  end

  # ---------------------------------------------------------------------------
  # Autoload resolution
  # ---------------------------------------------------------------------------

  describe 'autoload resolution' do
    it 'BSV::Network::Protocol is accessible without explicit require' do
      expect(BSV::Network::Protocol).to be_a(Class)
    end

    it 'BSV::Network::Protocols is accessible without explicit require' do
      expect(BSV::Network::Protocols).to be_a(Module)
    end

    it 'BSV::Network::ProtocolResponse is accessible without explicit require' do
      expect(BSV::Network::ProtocolResponse).to be_a(Class)
    end
  end

  # ---------------------------------------------------------------------------
  # GET endpoint — full round-trip
  # ---------------------------------------------------------------------------

  describe 'GET endpoint round-trip' do
    it 'call(:get_item, id) issues GET to /items/{id} and returns successful ProtocolResponse' do
      instance, http = make_client(ok_response)
      result = instance.call(:get_item, 'abc')

      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).to be_http_success
      expect(result.data).to eq('item_body')
      expect(http.last_uri.to_s).to eq('https://api.example.com/items/abc')
    end

    it 'uses an HTTP GET request' do
      instance, http = make_client(ok_response)
      instance.call(:get_item, 'abc')
      expect(http.last_request).to be_a(Net::HTTP::Get)
    end
  end

  # ---------------------------------------------------------------------------
  # POST endpoint — full round-trip
  # ---------------------------------------------------------------------------

  describe 'POST endpoint round-trip' do
    it 'call(:create_item, body:) issues POST and returns successful ProtocolResponse' do
      instance, http = make_client(created_response)
      result = instance.call(:create_item, body: '{"name":"test"}')

      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).to be_http_success
      expect(result.data).to eq('created')
      expect(http.last_request).to be_a(Net::HTTP::Post)
      expect(http.last_request.body).to eq('{"name":"test"}')
    end
  end

  # ---------------------------------------------------------------------------
  # JSON response handler
  # ---------------------------------------------------------------------------

  describe 'JSON response handler' do
    it 'call(:get_info) parses JSON body into a Hash' do
      instance, _http = make_client(json_response)
      result = instance.call(:get_info)

      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).to be_http_success
      expect(result.data).to eq({ 'version' => '1.0' })
    end
  end

  # ---------------------------------------------------------------------------
  # Lambda response handler
  # ---------------------------------------------------------------------------

  describe 'lambda response handler' do
    it 'call(:get_count) applies the lambda to the body' do
      instance, _http = make_client(count_response)
      result = instance.call(:get_count)

      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).to be_http_success
      expect(result.data).to eq(42)
    end
  end

  # ---------------------------------------------------------------------------
  # Escape hatch
  # ---------------------------------------------------------------------------

  describe 'escape hatch with default_call' do
    it 'call(:transform_item, id) delegates to default_call then post-processes' do
      instance, http = make_client(ok_response)
      result = instance.call(:transform_item, 'abc')

      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).to be_http_success
      expect(result.data).to eq('ITEM_BODY')
      # The underlying HTTP call still targets the correct URL
      expect(http.last_uri.to_s).to eq('https://api.example.com/items/abc')
    end
  end

  # ---------------------------------------------------------------------------
  # Subscription — NotImplementedError
  # ---------------------------------------------------------------------------

  describe 'subscription call' do
    it 'call(:on_item_change) raises NotImplementedError' do
      instance, _http = make_client(ok_response)
      expect { instance.call(:on_item_change) }
        .to raise_error(NotImplementedError, /subscription/)
    end
  end

  # ---------------------------------------------------------------------------
  # Unknown command
  # ---------------------------------------------------------------------------

  describe 'unknown command' do
    it 'call(:unknown) raises ArgumentError' do
      instance, _http = make_client(ok_response)
      expect { instance.call(:unknown) }
        .to raise_error(ArgumentError)
    end
  end

  # ---------------------------------------------------------------------------
  # HTTP error status codes
  # ---------------------------------------------------------------------------

  describe 'HTTP 404' do
    it 'returns not_found ProtocolResponse' do
      instance, _http = make_client(not_found_resp)
      result = instance.call(:get_item, 'missing')
      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).to be_http_not_found
    end
  end

  describe 'HTTP 500' do
    it 'returns retryable error ProtocolResponse' do
      instance, _http = make_client(server_error_resp)
      result = instance.call(:get_item, 'id')
      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).not_to be_http_success
      expect(result.retryable?).to be(true)
    end
  end

  describe 'HTTP 401' do
    it 'returns non-retryable error ProtocolResponse' do
      instance, _http = make_client(auth_error_resp)
      result = instance.call(:get_item, 'id')
      expect(result).to be_a(BSV::Network::ProtocolResponse)
      expect(result).not_to be_http_success
      expect(result.retryable?).to be(false)
    end
  end

  # ---------------------------------------------------------------------------
  # API key in Authorization header
  # ---------------------------------------------------------------------------

  describe 'Authorization header' do
    it 'includes Bearer token when api_key is set' do
      instance, http = make_client(ok_response, api_key: 'my-api-key')
      instance.call(:get_item, 'id')
      expect(http.last_request['Authorization']).to eq('Bearer my-api-key')
    end

    it 'omits Authorization header when api_key is nil' do
      instance, http = make_client(ok_response)
      instance.call(:get_item, 'id')
      expect(http.last_request['Authorization']).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # .commands
  # ---------------------------------------------------------------------------

  describe '.commands' do
    it 'returns a Set of all endpoint command names' do
      expected = Set[:get_item, :create_item, :get_info, :get_count]
      expect(TestIntegrationProtocol.commands).to eq(expected)
    end

    it 'does not include subscription names' do
      expect(TestIntegrationProtocol.commands).not_to include(:on_item_change)
    end
  end

  # ---------------------------------------------------------------------------
  # Subclass isolation
  # ---------------------------------------------------------------------------

  describe 'subclass isolation' do
    let(:sibling_protocol) do
      Class.new(BSV::Network::Protocol) do
        endpoint :sibling_only, :get, '/sibling'
      end
    end

    it 'two protocol classes do not share endpoints' do
      expect(TestIntegrationProtocol.commands).not_to include(:sibling_only)
      expect(sibling_protocol.commands).not_to include(:get_item)
    end
  end
end

# rubocop:enable RSpec/DescribeClass
