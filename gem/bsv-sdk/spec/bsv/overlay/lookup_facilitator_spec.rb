# frozen_string_literal: true

# rubocop:disable RSpec/MultipleDescribes

require 'spec_helper'
require 'bsv-sdk'

RSpec.describe BSV::Overlay::LookupFacilitator do
  subject(:facilitator) { described_class.new }

  let(:question) { BSV::Overlay::LookupQuestion.new(service: 'ls_foo', query: { 'q' => 1 }) }

  describe '#lookup' do
    it 'raises NotImplementedError' do
      expect { facilitator.lookup('https://example.com', question) }
        .to raise_error(NotImplementedError, /lookup must be implemented/)
    end
  end
end

RSpec.describe BSV::Overlay::HTTPSLookupFacilitator do
  subject(:facilitator) { described_class.new(http_client: mock_http_client) }

  let(:question) { BSV::Overlay::LookupQuestion.new(service: 'ls_foo', query: { 'q' => 1 }) }

  let(:ok_body) do
    JSON.generate(
      'type' => 'output-list',
      'outputs' => [{ 'beef' => [], 'outputIndex' => 0 }]
    )
  end

  let(:mock_response) do
    instance_double(Net::HTTPResponse, code: '200', body: ok_body)
  end

  let(:mock_http_client) do
    dbl = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
    allow(dbl).to receive(:request).and_return(mock_response)
    dbl
  end

  describe 'HTTPS enforcement' do
    it 'raises ArgumentError for a plain HTTP URL' do
      expect { facilitator.lookup('http://example.com', question) }
        .to raise_error(ArgumentError, /https:/)
    end

    it 'permits plain HTTP when allow_http: true' do
      http_facilitator = described_class.new(allow_http: true, http_client: mock_http_client)
      expect { http_facilitator.lookup('http://example.com', question) }.not_to raise_error
    end

    it 'permits HTTPS URLs' do
      expect { facilitator.lookup('https://example.com', question) }.not_to raise_error
    end
  end

  describe '#lookup' do
    it 'POSTs to {url}/lookup' do
      facilitator.lookup('https://example.com', question)
      expect(mock_http_client).to have_received(:request) do |uri, req|
        expect(uri.to_s).to eq('https://example.com/lookup')
        expect(req).to be_a(Net::HTTP::Post)
      end
    end

    it 'sets Content-Type and X-Aggregation headers' do
      facilitator.lookup('https://example.com', question)
      expect(mock_http_client).to have_received(:request) do |_uri, req|
        expect(req['Content-Type']).to eq('application/json')
        expect(req['X-Aggregation']).to eq('yes')
      end
    end

    it 'sends service and query in the JSON body' do
      facilitator.lookup('https://example.com', question)
      expect(mock_http_client).to have_received(:request) do |_uri, req|
        body = JSON.parse(req.body)
        expect(body['service']).to eq('ls_foo')
        expect(body['query']).to eq({ 'q' => 1 })
      end
    end

    it 'returns a LookupAnswer with type and outputs' do
      answer = facilitator.lookup('https://example.com', question)
      expect(answer).to be_a(BSV::Overlay::LookupAnswer)
      expect(answer.type).to eq('output-list')
      expect(answer.outputs).to be_an(Array)
    end

    it 'raises on non-2xx response' do
      error_response = instance_double(Net::HTTPResponse, code: '503', body: 'Service Unavailable')
      allow(mock_http_client).to receive(:request).and_return(error_response)
      expect { facilitator.lookup('https://example.com', question) }
        .to raise_error(RuntimeError, /HTTP 503/)
    end

    it 'strips trailing slash from URL before appending /lookup' do
      facilitator.lookup('https://example.com/', question)
      expect(mock_http_client).to have_received(:request) do |uri, _req|
        expect(uri.to_s).to eq('https://example.com/lookup')
      end
    end
  end
end

# rubocop:enable RSpec/MultipleDescribes
