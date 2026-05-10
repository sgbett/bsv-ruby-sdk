# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::Protocols::Chaintracks do
  let(:mock_http) do
    Class.new do
      attr_reader :last_uri, :last_request

      def initialize(code, body)
        @code = code.to_i
        @body = body
      end

      def request(uri, req)
        @last_uri     = uri
        @last_request = req
        FakeHttpResponse.fake_http_response(@code, @body)
      end
    end
  end

  def make_instance(code, body, api_key: nil)
    http = mock_http.new(code, body)
    instance = described_class.new(base_url: 'https://arcade.gorillapool.io', api_key: api_key, http_client: http)
    [instance, http]
  end

  describe '.commands' do
    it 'returns the correct set of commands' do
      expect(described_class.commands).to eq(Set[:get_block_header, :current_height])
    end
  end

  describe ':get_block_header' do
    let(:header_body) do
      { 'hash' => 'abc123', 'height' => 800_000, 'merkleroot' => 'def456' }.to_json
    end

    it 'returns parsed JSON on success' do
      instance, _http = make_instance(200, header_body)
      result = instance.call(:get_block_header, height: 800_000)

      expect(result).to be_success
      expect(result.data).to eq({ 'hash' => 'abc123', 'height' => 800_000, 'merkleroot' => 'def456' })
    end

    it 'builds the correct URL' do
      instance, http = make_instance(200, header_body)
      instance.call(:get_block_header, height: 800_000)

      expect(http.last_uri.to_s).to eq('https://arcade.gorillapool.io/chaintracks/v2/header/height/800000')
    end

    it 'returns not_found on 404' do
      instance, _http = make_instance(404, 'not found')
      result = instance.call(:get_block_header, height: 9_999_999)

      expect(result).to be_not_found
      expect(result.not_found?).to be(true)
    end

    it 'accepts height as a positional argument' do
      instance, http = make_instance(200, header_body)
      instance.call(:get_block_header, 800_000)

      expect(http.last_uri.to_s).to eq('https://arcade.gorillapool.io/chaintracks/v2/header/height/800000')
    end
  end

  describe ':current_height' do
    let(:tip_body) { { 'height' => 825_000, 'hash' => 'tipblockhash' }.to_json }

    it 'extracts the height integer from the tip JSON' do
      instance, _http = make_instance(200, tip_body)
      result = instance.call(:current_height)

      expect(result).to be_success
      expect(result.data).to eq(825_000)
    end

    it 'returns an Integer, not a String or Hash' do
      instance, _http = make_instance(200, tip_body)
      result = instance.call(:current_height)

      expect(result.data).to be_an(Integer)
    end

    it 'returns not_found on 404' do
      instance, _http = make_instance(404, 'not found')
      result = instance.call(:current_height)

      expect(result).to be_not_found
    end

    it 'returns error with retryable true on 5xx' do
      instance, _http = make_instance(503, 'service unavailable')
      result = instance.call(:current_height)

      expect(result).to be_error
      expect(result.retryable?).to be(true)
    end
  end

  describe 'base_url' do
    let(:tip_body) { { 'height' => 800_000 }.to_json }

    it 'raises ArgumentError when base_url: is omitted' do
      expect { described_class.new(http_client: mock_http.new(200, tip_body)) }
        .to raise_error(ArgumentError)
    end

    it 'uses the supplied base URL' do
      http = mock_http.new(200, tip_body)
      instance = described_class.new(base_url: 'https://my.chaintracks.example', http_client: http)
      expect(instance.base_url).to eq('https://my.chaintracks.example')
    end

    it 'uses the supplied base URL when building request URLs' do
      http = mock_http.new(200, tip_body)
      instance = described_class.new(base_url: 'https://my.chaintracks.example', http_client: http)
      instance.call(:current_height)
      expect(http.last_uri.to_s).to start_with('https://my.chaintracks.example')
    end
  end

  describe 'authentication' do
    let(:tip_body) { { 'height' => 800_000 }.to_json }

    it 'sends Authorization: Bearer header when api_key is set' do
      instance, http = make_instance(200, tip_body, api_key: 'my-api-key')
      instance.call(:current_height)

      expect(http.last_request['Authorization']).to eq('Bearer my-api-key')
    end

    it 'omits Authorization header when api_key is nil' do
      instance, http = make_instance(200, tip_body)
      instance.call(:current_height)

      expect(http.last_request['Authorization']).to be_nil
    end
  end
end
