# frozen_string_literal: true

RSpec.describe BSV::Network::Protocols::ARC do
  subject(:arc) do
    described_class.new(
      base_url: 'https://arc.example.com',
      api_key: 'test-key',
      deployment_id: 'test-deployment',
      http_client: http_client
    )
  end

  # rubocop:disable RSpec/VerifiedDoubles
  let(:http_client) { double('HttpClient') } # rubocop:disable RSpec/VerifiedDoubles

  def stub_response(code, body)
    response = double('Net::HTTPResponse', code: code.to_s, body: body)
    allow(http_client).to receive(:request).and_return(response)
    response
  end
  # rubocop:enable RSpec/VerifiedDoubles

  def stub_json_response(code, data)
    stub_response(code, JSON.generate(data))
  end

  def make_tx(ef_hex: nil, hex: 'deadbeef')
    tx = instance_double(BSV::Transaction::Transaction)
    if ef_hex
      allow(tx).to receive(:to_ef_hex).and_return(ef_hex)
    else
      allow(tx).to receive(:to_ef_hex).and_raise(ArgumentError, 'source data missing')
    end
    allow(tx).to receive(:to_hex).and_return(hex)
    tx
  end

  describe '.commands' do
    it 'declares the expected 5 endpoints' do
      expect(described_class.commands).to eq(
        Set.new(%i[broadcast broadcast_many get_tx_status get_policy health])
      )
    end
  end

  describe '#call(:broadcast)' do
    context 'when EF format is available' do
      let(:tx) { make_tx(ef_hex: 'efhex123') }

      before do
        stub_json_response(200, { 'txid' => 'abc123', 'txStatus' => 'RECEIVED' })
      end

      it 'sends EF hex in the request body' do
        arc.call(:broadcast, tx)
        expect(http_client).to have_received(:request) do |_uri, req|
          body = JSON.parse(req.body)
          expect(body['rawTx']).to eq('efhex123')
        end
      end

      it 'returns Result::Success' do
        result = arc.call(:broadcast, tx)
        expect(result).to be_a(BSV::Network::Result::Success)
        expect(result.data[:txid]).to eq('abc123')
      end

      it 'includes arc_status in metadata' do
        result = arc.call(:broadcast, tx)
        expect(result.metadata[:arc_status]).to eq('RECEIVED')
      end
    end

    context 'when EF format raises ArgumentError (fallback to raw hex)' do
      let(:tx) { make_tx(ef_hex: nil, hex: 'rawhex456') }

      before do
        stub_json_response(200, { 'txid' => 'def456', 'txStatus' => 'RECEIVED' })
      end

      it 'falls back to raw hex' do
        arc.call(:broadcast, tx)
        expect(http_client).to have_received(:request) do |_uri, req|
          body = JSON.parse(req.body)
          expect(body['rawTx']).to eq('rawhex456')
        end
      end

      it 'returns Result::Success' do
        result = arc.call(:broadcast, tx)
        expect(result).to be_a(BSV::Network::Result::Success)
        expect(result.data[:txid]).to eq('def456')
      end
    end

    context 'when ARC returns a rejected status' do
      let(:tx) { make_tx(ef_hex: 'efhex') }

      described_class::REJECTED_STATUSES.each do |status|
        it "returns Result::Error for #{status}" do
          stub_json_response(200, { 'txid' => 'abc', 'txStatus' => status })
          result = arc.call(:broadcast, tx)
          expect(result).to be_a(BSV::Network::Result::Error)
          expect(result.metadata[:arc_status]).to eq(status)
        end
      end

      it 'is case-insensitive for rejected statuses' do
        stub_json_response(200, { 'txid' => 'abc', 'txStatus' => 'rejected' })
        result = arc.call(:broadcast, tx)
        expect(result).to be_a(BSV::Network::Result::Error)
        expect(result.metadata[:arc_status]).to eq('REJECTED')
      end
    end

    context 'when txStatus contains ORPHAN substring' do
      let(:tx) { make_tx(ef_hex: 'efhex') }

      it 'detects ORPHAN in txStatus' do
        stub_json_response(200, { 'txid' => 'abc', 'txStatus' => 'ORPHAN' })
        result = arc.call(:broadcast, tx)
        expect(result).to be_a(BSV::Network::Result::Error)
      end

      it 'detects ORPHAN substring in txStatus' do
        stub_json_response(200, { 'txid' => 'abc', 'txStatus' => 'SEEN_IN_ORPHAN_MEMPOOL' })
        result = arc.call(:broadcast, tx)
        expect(result).to be_a(BSV::Network::Result::Error)
      end

      it 'detects ORPHAN in extraInfo' do
        stub_json_response(200, { 'txid' => 'abc', 'txStatus' => 'RECEIVED', 'extraInfo' => 'orphan detected' })
        result = arc.call(:broadcast, tx)
        expect(result).to be_a(BSV::Network::Result::Error)
      end

      it 'is case-insensitive for ORPHAN detection in extraInfo' do
        stub_json_response(200, { 'txid' => 'abc', 'txStatus' => 'RECEIVED', 'extraInfo' => 'ORPHAN_MEMPOOL' })
        result = arc.call(:broadcast, tx)
        expect(result).to be_a(BSV::Network::Result::Error)
      end
    end

    context 'when ARC returns malformed 2xx (no txid)' do
      let(:tx) { make_tx(ef_hex: 'efhex') }

      it 'returns Result::Error for missing txid' do
        stub_json_response(200, { 'txStatus' => 'RECEIVED' })
        result = arc.call(:broadcast, tx)
        expect(result).to be_a(BSV::Network::Result::Error)
        expect(result.message).to include('malformed')
      end

      it 'returns Result::Error for null txid' do
        stub_json_response(200, { 'txid' => nil, 'txStatus' => 'RECEIVED' })
        result = arc.call(:broadcast, tx)
        expect(result).to be_a(BSV::Network::Result::Error)
      end

      it 'returns Result::Error for non-JSON body' do
        stub_response(200, 'not json at all')
        result = arc.call(:broadcast, tx)
        expect(result).to be_a(BSV::Network::Result::Error)
      end

      it 'returns Result::Error when JSON parses to a non-Hash (e.g. Array)' do
        stub_response(200, JSON.generate([{ 'txid' => 'abc' }]))
        result = arc.call(:broadcast, tx)
        expect(result).to be_a(BSV::Network::Result::Error)
      end
    end

    context 'when ARC returns non-2xx status' do
      let(:tx) { make_tx(ef_hex: 'efhex') }

      it 'returns Result::Error for 400' do
        stub_json_response(400, { 'detail' => 'bad request' })
        result = arc.call(:broadcast, tx)
        expect(result).to be_a(BSV::Network::Result::Error)
        expect(result.retryable?).to be(false)
      end

      it 'returns retryable Result::Error for 500' do
        stub_json_response(500, { 'detail' => 'server error' })
        result = arc.call(:broadcast, tx)
        expect(result).to be_a(BSV::Network::Result::Error)
        expect(result.retryable?).to be(true)
      end

      it 'returns retryable Result::Error for 429' do
        stub_json_response(429, { 'detail' => 'rate limited' })
        result = arc.call(:broadcast, tx)
        expect(result).to be_a(BSV::Network::Result::Error)
        expect(result.retryable?).to be(true)
      end
    end

    context 'with custom headers' do
      let(:tx) { make_tx(ef_hex: 'efhex') }

      before { stub_json_response(200, { 'txid' => 'abc', 'txStatus' => 'RECEIVED' }) }

      it 'sends XDeployment-ID header' do
        arc.call(:broadcast, tx)
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['XDeployment-ID']).to eq('test-deployment')
        end
      end

      it 'sends X-WaitFor header when specified' do
        arc.call(:broadcast, tx, wait_for: 'MINED')
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['X-WaitFor']).to eq('MINED')
        end
      end

      it 'does not send X-WaitFor when nil' do
        arc.call(:broadcast, tx)
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['X-WaitFor']).to be_nil
        end
      end

      it 'sends X-SkipFeeValidation header when truthy' do
        arc.call(:broadcast, tx, skip_fee_validation: true)
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['X-SkipFeeValidation']).to eq('true')
        end
      end

      it 'sends X-SkipScriptValidation header when truthy' do
        arc.call(:broadcast, tx, skip_script_validation: true)
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['X-SkipScriptValidation']).to eq('true')
        end
      end

      it 'sends X-SkipTxValidation header when truthy' do
        arc.call(:broadcast, tx, skip_tx_validation: true)
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['X-SkipTxValidation']).to eq('true')
        end
      end
    end

    context 'with callback configuration' do
      let(:arc_with_callbacks) do
        described_class.new(
          base_url: 'https://arc.example.com',
          deployment_id: 'test-deployment',
          callback_url: 'https://my-callback.example.com',
          callback_token: 'cb-token',
          http_client: http_client
        )
      end
      let(:tx) { make_tx(ef_hex: 'efhex') }

      before { stub_json_response(200, { 'txid' => 'abc', 'txStatus' => 'RECEIVED' }) }

      it 'sends X-CallbackUrl from constructor' do
        arc_with_callbacks.call(:broadcast, tx)
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['X-CallbackUrl']).to eq('https://my-callback.example.com')
        end
      end

      it 'sends X-CallbackToken from constructor' do
        arc_with_callbacks.call(:broadcast, tx)
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['X-CallbackToken']).to eq('cb-token')
        end
      end
    end
  end

  describe '#call(:broadcast_many)' do
    let(:tx_with_ef)     { make_tx(ef_hex: 'ef1', hex: 'raw1') }
    let(:tx_without_ef)  { make_tx(ef_hex: nil, hex: 'raw2') }

    context 'with an empty array' do
      it 'returns Result::Success with empty data without making HTTP calls' do
        allow(http_client).to receive(:request)
        result = arc.call(:broadcast_many, [])
        expect(result).to be_a(BSV::Network::Result::Success)
        expect(result.data).to eq([])
        expect(http_client).not_to have_received(:request)
      end
    end

    context 'with mixed success and failure responses' do
      before do
        stub_json_response(200, [
                             { 'txid' => 'tx1id', 'txStatus' => 'RECEIVED' },
                             { 'txid' => 'tx2id', 'txStatus' => 'REJECTED' }
                           ])
      end

      it 'returns Result::Success containing per-item results' do
        result = arc.call(:broadcast_many, [tx_with_ef, tx_without_ef])
        expect(result).to be_a(BSV::Network::Result::Success)
        expect(result.data.length).to eq(2)
      end

      it 'maps successful items to Result::Success' do
        result = arc.call(:broadcast_many, [tx_with_ef, tx_without_ef])
        expect(result.data[0]).to be_a(BSV::Network::Result::Success)
        expect(result.data[0].data[:txid]).to eq('tx1id')
      end

      it 'maps rejected items to Result::Error' do
        result = arc.call(:broadcast_many, [tx_with_ef, tx_without_ef])
        expect(result.data[1]).to be_a(BSV::Network::Result::Error)
        expect(result.data[1].metadata[:arc_status]).to eq('REJECTED')
      end
    end

    context 'when HTTP returns non-2xx' do
      before { stub_json_response(500, { 'detail' => 'server error' }) }

      it 'returns Result::Error for the whole batch' do
        result = arc.call(:broadcast_many, [tx_with_ef])
        expect(result).to be_a(BSV::Network::Result::Error)
        expect(result.retryable?).to be(true)
      end
    end

    context 'when response is not an array' do
      before { stub_json_response(200, { 'detail' => 'unexpected' }) }

      it 'returns Result::Error for malformed batch response' do
        result = arc.call(:broadcast_many, [tx_with_ef])
        expect(result).to be_a(BSV::Network::Result::Error)
        expect(result.message).to include('malformed batch')
      end
    end

    context 'when a batch item is not a Hash' do
      before { stub_response(200, JSON.generate(['not-a-hash', { 'txid' => 'abc', 'txStatus' => 'RECEIVED' }])) }

      it 'maps non-Hash items to Result::Error' do
        result = arc.call(:broadcast_many, [tx_with_ef, tx_without_ef])
        expect(result).to be_a(BSV::Network::Result::Success)
        expect(result.data[0]).to be_a(BSV::Network::Result::Error)
        expect(result.data[0].message).to include('malformed batch item')
      end

      it 'still maps valid Hash items to Result::Success' do
        result = arc.call(:broadcast_many, [tx_with_ef, tx_without_ef])
        expect(result.data[1]).to be_a(BSV::Network::Result::Success)
        expect(result.data[1].data[:txid]).to eq('abc')
      end
    end

    it 'uses EF hex for transactions that support it' do
      stub_json_response(200, [{ 'txid' => 'abc', 'txStatus' => 'RECEIVED' }])
      arc.call(:broadcast_many, [tx_with_ef])
      expect(http_client).to have_received(:request) do |_uri, req|
        body = JSON.parse(req.body)
        expect(body[0]['rawTx']).to eq('ef1')
      end
    end

    it 'falls back to raw hex for transactions without EF support' do
      stub_json_response(200, [{ 'txid' => 'abc', 'txStatus' => 'RECEIVED' }])
      arc.call(:broadcast_many, [tx_without_ef])
      expect(http_client).to have_received(:request) do |_uri, req|
        body = JSON.parse(req.body)
        expect(body[0]['rawTx']).to eq('raw2')
      end
    end
  end

  describe '#call(:get_tx_status)' do
    context 'when transaction exists' do
      before { stub_json_response(200, { 'txid' => 'abc123', 'txStatus' => 'MINED' }) }

      it 'returns Result::Success with parsed JSON data' do
        result = arc.call(:get_tx_status, 'abc123')
        expect(result).to be_a(BSV::Network::Result::Success)
        expect(result.data['txid']).to eq('abc123')
        expect(result.data['txStatus']).to eq('MINED')
      end
    end

    context 'when transaction is not found' do
      before { stub_response(404, 'Not found') }

      it 'returns Result::NotFound' do
        result = arc.call(:get_tx_status, 'unknowntxid')
        expect(result).to be_a(BSV::Network::Result::NotFound)
      end
    end

    context 'when server returns 500' do
      before { stub_response(500, 'Internal server error') }

      it 'returns retryable Result::Error' do
        result = arc.call(:get_tx_status, 'abc123')
        expect(result).to be_a(BSV::Network::Result::Error)
        expect(result.retryable?).to be(true)
      end
    end
  end

  describe '#call(:get_policy)' do
    before do
      stub_json_response(200, {
                           'policy' => { 'maxscriptsizepolicy' => 100_000, 'maxtxsizepolicy' => 10_000_000 }
                         })
    end

    it 'returns Result::Success with parsed JSON policy data' do
      result = arc.call(:get_policy)
      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['policy']).to be_a(Hash)
    end
  end

  describe '#call(:health)' do
    before { stub_json_response(200, { 'healthy' => true }) }

    it 'returns Result::Success' do
      result = arc.call(:health)
      expect(result).to be_a(BSV::Network::Result::Success)
      expect(result.data['healthy']).to be(true)
    end
  end

  describe 'constructor' do
    it 'assigns a random deployment_id when none is provided' do
      arc1 = described_class.new(base_url: 'https://arc.example.com', http_client: http_client)
      arc2 = described_class.new(base_url: 'https://arc.example.com', http_client: http_client)
      expect(arc1.instance_variable_get(:@deployment_id)).not_to eq(arc2.instance_variable_get(:@deployment_id))
    end

    it 'uses the provided deployment_id' do
      custom = described_class.new(
        base_url: 'https://arc.example.com',
        deployment_id: 'my-deployment',
        http_client: http_client
      )
      expect(custom.instance_variable_get(:@deployment_id)).to eq('my-deployment')
    end
  end
end
