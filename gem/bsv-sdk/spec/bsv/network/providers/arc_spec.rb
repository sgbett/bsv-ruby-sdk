# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::Providers::ARC do
  # Minimal HTTP client stub — stores the last request and returns a configurable response.
  let(:mock_http) do
    Class.new do
      attr_reader :last_uri, :last_request

      def initialize(code, body)
        @code = code
        @body = body
      end

      def request(uri, req)
        @last_uri = uri
        @last_request = req
        Struct.new(:code, :body).new(@code.to_s, @body)
      end
    end
  end

  # Transaction double with EF hex support.
  let(:tx) do
    instance_double(
      BSV::Transaction::Transaction,
      to_ef_hex: '010000000000ef0000',
      to_hex: '01000000'
    )
  end

  # Transaction double that cannot produce EF form.
  let(:tx_no_source) do
    dbl = instance_double(BSV::Transaction::Transaction, to_hex: '01000000')
    allow(dbl).to receive(:to_ef_hex).and_raise(ArgumentError, 'inputs must have source_satoshis for EF')
    dbl
  end

  let(:tx2) do
    instance_double(
      BSV::Transaction::Transaction,
      to_ef_hex: '020000000000ef0000',
      to_hex: '02000000'
    )
  end

  let(:success_body) do
    {
      'txid' => 'abc123',
      'txStatus' => 'SEEN_ON_NETWORK',
      'title' => 'Added to mempool',
      'extraInfo' => '',
      'blockHash' => '',
      'blockHeight' => 0,
      'timestamp' => '2025-01-01T00:00:00Z'
    }.to_json
  end

  def new_arc(**opts)
    http = opts.delete(:http_client)
    described_class.new(url: 'https://arc.example.com', http_client: http, **opts)
  end

  # ---------------------------------------------------------------------------
  # :broadcast
  # ---------------------------------------------------------------------------

  describe '#call(:broadcast)' do
    it 'returns a success result with txid, status, and extra_info' do
      http = mock_http.new(200, success_body)
      arc = new_arc(http_client: http)

      result = arc.call(:broadcast, tx)

      expect(result).to be_success
      expect(result.data[:txid]).to eq('abc123')
      expect(result.data[:status]).to eq('SEEN_ON_NETWORK')
      expect(result.data[:extra_info]).to eq('')
    end

    it 'sends JSON body with Extended Format hex' do
      http = mock_http.new(200, success_body)
      arc = new_arc(http_client: http)

      arc.call(:broadcast, tx)

      expect(http.last_request['Content-Type']).to eq('application/json')
      body = JSON.parse(http.last_request.body)
      expect(body).to eq('rawTx' => '010000000000ef0000')
    end

    it 'falls back to plain hex when EF encoding is unavailable' do
      http = mock_http.new(200, success_body)
      arc = new_arc(http_client: http)

      arc.call(:broadcast, tx_no_source)

      body = JSON.parse(http.last_request.body)
      expect(body).to eq('rawTx' => '01000000')
    end

    it 'posts to /v1/tx' do
      http = mock_http.new(200, success_body)
      arc = new_arc(http_client: http)

      arc.call(:broadcast, tx)

      expect(http.last_uri.to_s).to eq('https://arc.example.com/v1/tx')
    end

    it 'sets the XDeployment-ID header with a default random value' do
      http = mock_http.new(200, success_body)
      arc = new_arc(http_client: http)

      arc.call(:broadcast, tx)

      expect(http.last_request['XDeployment-ID']).to start_with('bsv-ruby-sdk-')
    end

    it 'uses an explicit deployment_id when configured' do
      http = mock_http.new(200, success_body)
      arc = new_arc(deployment_id: 'my-deployment', http_client: http)

      arc.call(:broadcast, tx)

      expect(http.last_request['XDeployment-ID']).to eq('my-deployment')
    end

    it 'sets X-WaitFor header when wait_for: is provided' do
      http = mock_http.new(200, success_body)
      arc = new_arc(http_client: http)

      arc.call(:broadcast, tx, wait_for: 'SEEN_ON_NETWORK')

      expect(http.last_request['X-WaitFor']).to eq('SEEN_ON_NETWORK')
    end

    it 'sets X-SkipFeeValidation header when skip_fee_validation: true' do
      http = mock_http.new(200, success_body)
      arc = new_arc(http_client: http)

      arc.call(:broadcast, tx, skip_fee_validation: true)

      expect(http.last_request['X-SkipFeeValidation']).to eq('true')
    end

    it 'sets X-SkipScriptValidation header when skip_script_validation: true' do
      http = mock_http.new(200, success_body)
      arc = new_arc(http_client: http)

      arc.call(:broadcast, tx, skip_script_validation: true)

      expect(http.last_request['X-SkipScriptValidation']).to eq('true')
    end

    it 'omits skip-validation headers when not set' do
      http = mock_http.new(200, success_body)
      arc = new_arc(http_client: http)

      arc.call(:broadcast, tx)

      expect(http.last_request['X-SkipFeeValidation']).to be_nil
      expect(http.last_request['X-SkipScriptValidation']).to be_nil
    end

    it 'returns a non-retryable error when txStatus is REJECTED' do
      body = { 'txid' => 'abc123', 'txStatus' => 'REJECTED', 'title' => 'Transaction rejected' }.to_json
      http = mock_http.new(200, body)
      arc = new_arc(http_client: http)

      result = arc.call(:broadcast, tx)

      expect(result).to be_error
      expect(result.retryable?).to be false
      expect(result.message).to eq('Transaction rejected')
    end

    it 'returns a non-retryable error when txStatus is DOUBLE_SPEND_ATTEMPTED' do
      body = { 'txid' => 'abc123', 'txStatus' => 'DOUBLE_SPEND_ATTEMPTED', 'title' => 'Double spend' }.to_json
      http = mock_http.new(200, body)
      arc = new_arc(http_client: http)

      result = arc.call(:broadcast, tx)

      expect(result).to be_error
      expect(result.retryable?).to be false
    end

    %w[INVALID MALFORMED MINED_IN_STALE_BLOCK].each do |status|
      it "returns a non-retryable error when txStatus is #{status}" do
        body = { 'txid' => 'abc123', 'txStatus' => status, 'title' => status }.to_json
        http = mock_http.new(200, body)
        arc = new_arc(http_client: http)

        result = arc.call(:broadcast, tx)

        expect(result).to be_error
        expect(result.retryable?).to be false
      end
    end

    it 'returns a non-retryable error when txStatus contains ORPHAN' do
      body = { 'txid' => 'abc123', 'txStatus' => 'ORPHAN_MISSING_PARENT', 'title' => 'Orphan' }.to_json
      http = mock_http.new(200, body)
      arc = new_arc(http_client: http)

      result = arc.call(:broadcast, tx)

      expect(result).to be_error
      expect(result.retryable?).to be false
    end

    it 'returns a non-retryable error when extraInfo contains orphan marker' do
      body = { 'txid' => 'abc123', 'txStatus' => 'SEEN_ON_NETWORK', 'extraInfo' => 'transaction is an ORPHAN' }.to_json
      http = mock_http.new(200, body)
      arc = new_arc(http_client: http)

      result = arc.call(:broadcast, tx)

      expect(result).to be_error
      expect(result.retryable?).to be false
    end

    it 'returns a retryable error on HTTP 500' do
      body = { 'title' => 'Internal error', 'detail' => 'server fault' }.to_json
      http = mock_http.new(500, body)
      arc = new_arc(http_client: http)

      result = arc.call(:broadcast, tx)

      expect(result).to be_error
      expect(result.retryable?).to be true
      expect(result.message).to eq('server fault')
    end

    it 'returns a retryable error on HTTP 429' do
      body = { 'detail' => 'rate limited' }.to_json
      http = mock_http.new(429, body)
      arc = new_arc(http_client: http)

      result = arc.call(:broadcast, tx)

      expect(result).to be_error
      expect(result.retryable?).to be true
    end

    it 'returns a non-retryable error on HTTP 400' do
      body = { 'detail' => 'malformed tx' }.to_json
      http = mock_http.new(400, body)
      arc = new_arc(http_client: http)

      result = arc.call(:broadcast, tx)

      expect(result).to be_error
      expect(result.retryable?).to be false
      expect(result.message).to eq('malformed tx')
    end

    it 'returns a non-retryable error for 2xx response missing txid' do
      body = { 'txStatus' => 'SEEN_ON_NETWORK' }.to_json
      http = mock_http.new(200, body)
      arc = new_arc(http_client: http)

      result = arc.call(:broadcast, tx)

      expect(result).to be_error
      expect(result.retryable?).to be false
      expect(result.message).to match(/malformed/)
    end

    it 'returns a non-retryable error for non-JSON 2xx response' do
      http = mock_http.new(200, 'plain text from proxy')
      arc = new_arc(http_client: http)

      result = arc.call(:broadcast, tx)

      expect(result).to be_error
      expect(result.retryable?).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # :broadcast_many
  # ---------------------------------------------------------------------------

  describe '#call(:broadcast_many)' do
    let(:batch_success) do
      [JSON.parse(success_body), JSON.parse(success_body).merge('txid' => 'def456')].to_json
    end

    it 'returns success wrapping an array of results' do
      http = mock_http.new(200, batch_success)
      arc = new_arc(http_client: http)

      result = arc.call(:broadcast_many, [tx, tx2])

      expect(result).to be_success
      expect(result.data.length).to eq(2)
      expect(result.data[0][:txid]).to eq('abc123')
      expect(result.data[1][:txid]).to eq('def456')
    end

    it 'posts to /v1/txs with a JSON array body' do
      http = mock_http.new(200, batch_success)
      arc = new_arc(http_client: http)

      arc.call(:broadcast_many, [tx, tx2])

      expect(http.last_uri.to_s).to eq('https://arc.example.com/v1/txs')
      body = JSON.parse(http.last_request.body)
      expect(body).to eq([{ 'rawTx' => '010000000000ef0000' }, { 'rawTx' => '020000000000ef0000' }])
    end

    it 'returns success([]) without an HTTP request when given an empty array' do
      http = mock_http.new(200, '[]')
      arc = new_arc(http_client: http)

      result = arc.call(:broadcast_many, [])

      expect(result).to be_success
      expect(result.data).to eq([])
      expect(http.last_request).to be_nil
    end

    it 'returns a mixed array when some transactions are rejected' do
      rejected = {
        'txid' => 'def456',
        'txStatus' => 'REJECTED',
        'title' => 'Transaction rejected',
        'detail' => 'inputs already spent'
      }
      batch = [JSON.parse(success_body), rejected].to_json
      http = mock_http.new(200, batch)
      arc = new_arc(http_client: http)

      result = arc.call(:broadcast_many, [tx, tx2])

      expect(result).to be_success
      items = result.data
      expect(items[0][:txid]).to eq('abc123')
      expect(items[1]).to be_a(BSV::Network::Result::Error)
      expect(items[1].message).to eq('inputs already spent')
      expect(items[1].retryable?).to be false
    end

    it 'returns error items for batch entries missing txid' do
      body = [{ 'txStatus' => 'SEEN_ON_NETWORK' }].to_json
      http = mock_http.new(200, body)
      arc = new_arc(http_client: http)

      result = arc.call(:broadcast_many, [tx])

      expect(result).to be_success
      expect(result.data[0]).to be_a(BSV::Network::Result::Error)
      expect(result.data[0].message).to match(/malformed/)
    end

    it 'uses EF hex for each transaction when available' do
      http = mock_http.new(200, [JSON.parse(success_body)].to_json)
      arc = new_arc(http_client: http)

      arc.call(:broadcast_many, [tx])

      body = JSON.parse(http.last_request.body)
      expect(body[0]['rawTx']).to eq('010000000000ef0000')
    end

    it 'falls back to plain hex per transaction when EF is unavailable' do
      batch = [JSON.parse(success_body), JSON.parse(success_body).merge('txid' => 'def456')].to_json
      http = mock_http.new(200, batch)
      arc = new_arc(http_client: http)

      arc.call(:broadcast_many, [tx_no_source, tx2])

      body = JSON.parse(http.last_request.body)
      expect(body[0]['rawTx']).to eq('01000000')
      expect(body[1]['rawTx']).to eq('020000000000ef0000')
    end

    it 'returns a retryable error on HTTP 500' do
      body = { 'detail' => 'server fault' }.to_json
      http = mock_http.new(500, body)
      arc = new_arc(http_client: http)

      result = arc.call(:broadcast_many, [tx])

      expect(result).to be_error
      expect(result.retryable?).to be true
    end

    it 'returns a non-retryable error when ARC returns a non-array 2xx body' do
      http = mock_http.new(200, success_body)
      arc = new_arc(http_client: http)

      result = arc.call(:broadcast_many, [tx])

      expect(result).to be_error
      expect(result.retryable?).to be false
      expect(result.message).to match(/malformed batch/)
    end
  end

  # ---------------------------------------------------------------------------
  # :get_tx_status
  # ---------------------------------------------------------------------------

  describe '#call(:get_tx_status)' do
    it 'returns success with txid, tx_status, block_hash, block_height' do
      body = {
        'txid' => 'abc123',
        'txStatus' => 'MINED',
        'blockHash' => '000000abc',
        'blockHeight' => 800_000
      }.to_json
      http = mock_http.new(200, body)
      arc = new_arc(http_client: http)

      result = arc.call(:get_tx_status, 'abc123')

      expect(result).to be_success
      expect(result.data[:txid]).to eq('abc123')
      expect(result.data[:tx_status]).to eq('MINED')
      expect(result.data[:block_hash]).to eq('000000abc')
      expect(result.data[:block_height]).to eq(800_000)
    end

    it 'sends GET to /v1/tx/{txid}' do
      body = { 'txid' => 'abc123', 'txStatus' => 'SEEN_ON_NETWORK' }.to_json
      http = mock_http.new(200, body)
      arc = new_arc(http_client: http)

      arc.call(:get_tx_status, 'abc123')

      expect(http.last_uri.to_s).to eq('https://arc.example.com/v1/tx/abc123')
      expect(http.last_request).to be_a(Net::HTTP::Get)
    end

    it 'returns not_found on HTTP 404' do
      http = mock_http.new(404, { 'detail' => 'not found' }.to_json)
      arc = new_arc(http_client: http)

      result = arc.call(:get_tx_status, 'unknown')

      expect(result).to be_not_found
    end

    it 'returns a retryable error on HTTP 500' do
      body = { 'detail' => 'server error' }.to_json
      http = mock_http.new(500, body)
      arc = new_arc(http_client: http)

      result = arc.call(:get_tx_status, 'abc123')

      expect(result).to be_error
      expect(result.retryable?).to be true
    end

    it 'returns a non-retryable error on HTTP 400' do
      body = { 'detail' => 'bad request' }.to_json
      http = mock_http.new(400, body)
      arc = new_arc(http_client: http)

      result = arc.call(:get_tx_status, 'abc123')

      expect(result).to be_error
      expect(result.retryable?).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # :get_policy
  # ---------------------------------------------------------------------------

  describe '#call(:get_policy)' do
    let(:policy_body) do
      {
        'policy' => {
          'miningFee' => { 'bytes' => 1000, 'satoshis' => 1 },
          'maxScriptSizePolicy' => 100_000
        }
      }.to_json
    end

    it 'returns success wrapping the policy hash' do
      http = mock_http.new(200, policy_body)
      arc = new_arc(http_client: http)

      result = arc.call(:get_policy)

      expect(result).to be_success
      expect(result.data[:policy]).to be_a(Hash)
      expect(result.data[:policy]['miningFee']).to eq('bytes' => 1000, 'satoshis' => 1)
    end

    it 'sends GET to /v1/policy' do
      http = mock_http.new(200, policy_body)
      arc = new_arc(http_client: http)

      arc.call(:get_policy)

      expect(http.last_uri.to_s).to eq('https://arc.example.com/v1/policy')
      expect(http.last_request).to be_a(Net::HTTP::Get)
    end

    it 'returns a retryable error on HTTP 500' do
      http = mock_http.new(500, { 'detail' => 'server error' }.to_json)
      arc = new_arc(http_client: http)

      result = arc.call(:get_policy)

      expect(result).to be_error
      expect(result.retryable?).to be true
    end

    it 'returns a non-retryable error on HTTP 400' do
      http = mock_http.new(400, { 'detail' => 'bad request' }.to_json)
      arc = new_arc(http_client: http)

      result = arc.call(:get_policy)

      expect(result).to be_error
      expect(result.retryable?).to be false
    end

    it 'tolerates non-standard policy shapes from ARC implementations' do
      body = { 'policy' => { 'custom_field' => 42 } }.to_json
      http = mock_http.new(200, body)
      arc = new_arc(http_client: http)

      result = arc.call(:get_policy)

      expect(result).to be_success
      expect(result.data[:policy]).to eq('custom_field' => 42)
    end
  end

  # ---------------------------------------------------------------------------
  # Authentication and header wiring
  # ---------------------------------------------------------------------------

  describe 'authentication and headers' do
    it 'sets Authorization header when api_key is provided' do
      http = mock_http.new(200, success_body)
      arc = new_arc(api_key: 'my-key', http_client: http)

      arc.call(:broadcast, tx)

      expect(http.last_request['Authorization']).to eq('Bearer my-key')
    end

    it 'omits Authorization header when api_key is nil' do
      http = mock_http.new(200, success_body)
      arc = new_arc(http_client: http)

      arc.call(:broadcast, tx)

      expect(http.last_request['Authorization']).to be_nil
    end

    it 'sets X-CallbackUrl and X-CallbackToken when configured' do
      http = mock_http.new(200, success_body)
      arc = new_arc(
        callback_url: 'https://example.com/cb',
        callback_token: 'secret',
        http_client: http
      )

      arc.call(:broadcast, tx)

      expect(http.last_request['X-CallbackUrl']).to eq('https://example.com/cb')
      expect(http.last_request['X-CallbackToken']).to eq('secret')
    end

    it 'omits callback headers when not configured' do
      http = mock_http.new(200, success_body)
      arc = new_arc(http_client: http)

      arc.call(:broadcast, tx)

      expect(http.last_request['X-CallbackUrl']).to be_nil
      expect(http.last_request['X-CallbackToken']).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # URL configuration
  # ---------------------------------------------------------------------------

  describe 'URL configuration' do
    it 'uses BSV::MAINNET_URL as the default base URL' do
      arc = described_class.new
      expect(arc.instance_variable_get(:@url)).to eq(BSV::MAINNET_URL.chomp('/'))
    end

    it 'accepts a custom base URL' do
      http = mock_http.new(200, success_body)
      arc = described_class.new(url: 'https://custom-arc.example.com', http_client: http)

      arc.call(:broadcast, tx)

      expect(http.last_uri.host).to eq('custom-arc.example.com')
    end

    it 'strips trailing slash from the base URL' do
      http = mock_http.new(200, success_body)
      arc = described_class.new(url: 'https://arc.example.com/', http_client: http)

      arc.call(:broadcast, tx)

      expect(http.last_uri.to_s).to eq('https://arc.example.com/v1/tx')
    end
  end

  # ---------------------------------------------------------------------------
  # Capabilities
  # ---------------------------------------------------------------------------

  describe '.capabilities' do
    it 'declares all four required commands' do
      expect(described_class.capabilities).to include(:broadcast, :broadcast_many, :get_tx_status, :get_policy)
    end

    it 'inherits from BSV::Network::Provider' do
      expect(described_class.superclass).to eq(BSV::Network::Provider)
    end
  end
end
