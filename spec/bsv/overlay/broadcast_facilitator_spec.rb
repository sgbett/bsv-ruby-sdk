# frozen_string_literal: true

# rubocop:disable RSpec/MultipleDescribes

require 'spec_helper'
require 'bsv-sdk'

RSpec.describe BSV::Overlay::BroadcastFacilitator do
  subject(:facilitator) { described_class.new }

  let(:tagged_beef) do
    BSV::Overlay::TaggedBEEF.new(beef: "\x00\x01\x02", topics: ['tm_foo'])
  end

  describe '#send_beef' do
    it 'raises NotImplementedError' do
      expect { facilitator.send_beef('https://example.com', tagged_beef) }
        .to raise_error(NotImplementedError, /send_beef must be implemented/)
    end
  end
end

RSpec.describe BSV::Overlay::HTTPSBroadcastFacilitator do
  subject(:facilitator) { described_class.new(http_client: mock_http_client) }

  let(:tagged_beef) do
    BSV::Overlay::TaggedBEEF.new(beef: "\x01\x02\x03", topics: %w[tm_foo tm_bar])
  end

  let(:steak_body) do
    JSON.generate(
      'tm_foo' => {
        'outputsToAdmit' => [0],
        'coinsToRetain' => [],
        'coinsRemoved' => nil
      },
      'tm_bar' => {
        'outputsToAdmit' => [],
        'coinsToRetain' => [1],
        'coinsRemoved' => nil
      }
    )
  end

  let(:mock_response) do
    instance_double(Net::HTTPResponse, code: '200', body: steak_body)
  end

  let(:mock_http_client) do
    dbl = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
    allow(dbl).to receive(:request).and_return(mock_response)
    dbl
  end

  describe 'HTTPS enforcement' do
    it 'raises ArgumentError for a plain HTTP URL' do
      expect { facilitator.send_beef('http://example.com', tagged_beef) }
        .to raise_error(ArgumentError, /https:/)
    end

    it 'permits plain HTTP when allow_http: true' do
      http_facilitator = described_class.new(allow_http: true, http_client: mock_http_client)
      expect { http_facilitator.send_beef('http://example.com', tagged_beef) }.not_to raise_error
    end

    it 'permits HTTPS URLs' do
      expect { facilitator.send_beef('https://example.com', tagged_beef) }.not_to raise_error
    end
  end

  describe '#send_beef' do
    it 'POSTs to {url}/submit' do
      facilitator.send_beef('https://example.com', tagged_beef)
      expect(mock_http_client).to have_received(:request) do |uri, req|
        expect(uri.to_s).to eq('https://example.com/submit')
        expect(req).to be_a(Net::HTTP::Post)
      end
    end

    it 'strips trailing slash before appending /submit' do
      facilitator.send_beef('https://example.com/', tagged_beef)
      expect(mock_http_client).to have_received(:request) do |uri, _req|
        expect(uri.to_s).to eq('https://example.com/submit')
      end
    end

    it 'sets Content-Type to application/octet-stream' do
      facilitator.send_beef('https://example.com', tagged_beef)
      expect(mock_http_client).to have_received(:request) do |_uri, req|
        expect(req['Content-Type']).to eq('application/octet-stream')
      end
    end

    it 'sets X-Topics to JSON-encoded topics array' do
      facilitator.send_beef('https://example.com', tagged_beef)
      expect(mock_http_client).to have_received(:request) do |_uri, req|
        expect(JSON.parse(req['X-Topics'])).to eq(%w[tm_foo tm_bar])
      end
    end

    it 'sends raw BEEF bytes as the request body' do
      facilitator.send_beef('https://example.com', tagged_beef)
      expect(mock_http_client).to have_received(:request) do |_uri, req|
        expect(req.body).to eq("\x01\x02\x03")
      end
    end

    it 'returns a hash of topic => AdmittanceInstructions' do
      result = facilitator.send_beef('https://example.com', tagged_beef)
      expect(result).to be_a(Hash)
      expect(result.keys).to contain_exactly('tm_foo', 'tm_bar')
      expect(result['tm_foo']).to be_a(BSV::Overlay::AdmittanceInstructions)
      expect(result['tm_foo'].outputs_to_admit).to eq([0])
      expect(result['tm_bar'].coins_to_retain).to eq([1])
    end

    it 'returns nil for a non-2xx response' do
      error_response = instance_double(Net::HTTPResponse, code: '500', body: 'Server Error')
      allow(mock_http_client).to receive(:request).and_return(error_response)
      result = facilitator.send_beef('https://example.com', tagged_beef)
      expect(result).to be_nil
    end

    it 'returns nil for an unparseable response body' do
      bad_response = instance_double(Net::HTTPResponse, code: '200', body: 'not json')
      allow(mock_http_client).to receive(:request).and_return(bad_response)
      result = facilitator.send_beef('https://example.com', tagged_beef)
      expect(result).to be_nil
    end
  end
end

# rubocop:enable RSpec/MultipleDescribes
