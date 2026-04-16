# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Network::ARC do
  # Mock HTTP client that stores the last request and returns a configurable response
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

  # Minimal transaction double supporting the Extended Format (BRC-30)
  # preferred by ARC, plus the plain raw-tx hex fallback used when any
  # input lacks source_satoshis / source_locking_script.
  let(:tx) do
    instance_double(
      BSV::Transaction::Transaction,
      to_ef_hex: '010000000000ef0000',
      to_hex: '01000000'
    )
  end

  # Alternate transaction double that cannot produce EF form (matches the
  # real Transaction#to_ef behaviour of raising when inputs are missing
  # source_satoshis or source_locking_script).
  let(:tx_no_source) do
    dbl = instance_double(BSV::Transaction::Transaction, to_hex: '01000000')
    allow(dbl).to receive(:to_ef_hex).and_raise(ArgumentError, 'inputs must have source_satoshis for EF')
    dbl
  end

  let(:success_body) do
    {
      'txid' => 'abc123',
      'txStatus' => 'SEEN_ON_NETWORK',
      'title' => 'Added to mempool',
      'extraInfo' => '',
      'blockHash' => '',
      'blockHeight' => 0,
      'timestamp' => '2025-01-01T00:00:00Z',
      'competingTxs' => nil
    }.to_json
  end

  describe '#broadcast' do
    it 'returns a BroadcastResponse on success' do
      http = mock_http.new(200, success_body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      response = arc.broadcast(tx)

      expect(response).to be_a(BSV::Network::BroadcastResponse)
      expect(response.txid).to eq('abc123')
      expect(response.tx_status).to eq('SEEN_ON_NETWORK')
      expect(response.message).to eq('Added to mempool')
      expect(response.success?).to be true
    end

    it 'sends JSON body with Extended Format hex raw tx' do
      http = mock_http.new(200, success_body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      arc.broadcast(tx)

      expect(http.last_request['Content-Type']).to eq('application/json')
      body = JSON.parse(http.last_request.body)
      expect(body).to eq('rawTx' => '010000000000ef0000')
    end

    it 'falls back to plain raw-tx hex when EF encoding is unavailable' do
      http = mock_http.new(200, success_body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      arc.broadcast(tx_no_source)

      body = JSON.parse(http.last_request.body)
      expect(body).to eq('rawTx' => '01000000')
    end

    it 'sends the XDeployment-ID header (default random identifier)' do
      http = mock_http.new(200, success_body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      arc.broadcast(tx)

      expect(http.last_request['XDeployment-ID']).to start_with('bsv-ruby-sdk-')
    end

    it 'sends an explicit XDeployment-ID when configured' do
      http = mock_http.new(200, success_body)
      arc = described_class.new('https://arc.example.com', deployment_id: 'acme-prod-42', http_client: http)

      arc.broadcast(tx)

      expect(http.last_request['XDeployment-ID']).to eq('acme-prod-42')
    end

    it 'sends X-CallbackUrl and X-CallbackToken headers when configured' do
      http = mock_http.new(200, success_body)
      arc = described_class.new(
        'https://arc.example.com',
        callback_url: 'https://example.com/arc-cb',
        callback_token: 'secret-token',
        http_client: http
      )

      arc.broadcast(tx)

      expect(http.last_request['X-CallbackUrl']).to eq('https://example.com/arc-cb')
      expect(http.last_request['X-CallbackToken']).to eq('secret-token')
    end

    it 'omits X-CallbackUrl and X-CallbackToken when not configured' do
      http = mock_http.new(200, success_body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      arc.broadcast(tx)

      expect(http.last_request['X-CallbackUrl']).to be_nil
      expect(http.last_request['X-CallbackToken']).to be_nil
    end

    it 'posts to /v1/tx' do
      http = mock_http.new(200, success_body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      arc.broadcast(tx)

      expect(http.last_uri.to_s).to eq('https://arc.example.com/v1/tx')
    end

    it 'raises BroadcastError on HTTP 400' do
      body = { 'title' => 'Bad request', 'detail' => 'malformed tx', 'txid' => nil }.to_json
      http = mock_http.new(400, body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      expect { arc.broadcast(tx) }.to raise_error(BSV::Network::BroadcastError) do |error|
        expect(error.message).to eq('malformed tx')
        expect(error.status_code).to eq(400)
      end
    end

    it 'raises BroadcastError on HTTP 465 (fee too low)' do
      body = { 'title' => 'Fee too low', 'detail' => 'fee is below minimum', 'txid' => 'abc123' }.to_json
      http = mock_http.new(465, body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      expect { arc.broadcast(tx) }.to raise_error(BSV::Network::BroadcastError) do |error|
        expect(error.message).to eq('fee is below minimum')
        expect(error.status_code).to eq(465)
        expect(error.txid).to eq('abc123')
      end
    end

    it 'raises BroadcastError when txStatus is REJECTED' do
      body = { 'txid' => 'abc123', 'txStatus' => 'REJECTED', 'title' => 'Transaction rejected' }.to_json
      http = mock_http.new(200, body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      expect { arc.broadcast(tx) }.to raise_error(BSV::Network::BroadcastError) do |error|
        expect(error.message).to eq('Transaction rejected')
        expect(error.txid).to eq('abc123')
        expect(error.status_code).to eq(200)
      end
    end

    it 'raises BroadcastError when txStatus is DOUBLE_SPEND_ATTEMPTED' do
      body = {
        'txid' => 'abc123',
        'txStatus' => 'DOUBLE_SPEND_ATTEMPTED',
        'title' => 'Double spend',
        'competingTxs' => ['def456']
      }.to_json
      http = mock_http.new(200, body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      expect { arc.broadcast(tx) }.to raise_error(BSV::Network::BroadcastError, 'Double spend')
    end

    # Regression for https://github.com/sgbett/bsv-ruby-sdk/issues/305 (F5.13)
    #
    # Prior behaviour: `REJECTED_STATUSES` only contained REJECTED and
    # DOUBLE_SPEND_ATTEMPTED. ARC responses with txStatus INVALID, MALFORMED,
    # MINED_IN_STALE_BLOCK, or any ORPHAN-containing status / extraInfo were
    # silently treated as successful broadcasts — callers relying on
    # broadcast() to signal failure would trust un-broadcast transactions.
    describe 'failure status recognition (issue #305)' do
      %w[INVALID MALFORMED MINED_IN_STALE_BLOCK].each do |failure_status|
        it "raises BroadcastError when txStatus is #{failure_status}" do
          body = {
            'txid' => 'abc123',
            'txStatus' => failure_status,
            'title' => "Transaction #{failure_status.downcase}"
          }.to_json
          http = mock_http.new(200, body)
          arc = described_class.new('https://arc.example.com', http_client: http)

          expect { arc.broadcast(tx) }
            .to raise_error(BSV::Network::BroadcastError)
        end
      end

      it 'raises BroadcastError when txStatus contains ORPHAN' do
        body = {
          'txid' => 'abc123',
          'txStatus' => 'ORPHAN_MISSING_PARENT',
          'title' => 'Orphan transaction'
        }.to_json
        http = mock_http.new(200, body)
        arc = described_class.new('https://arc.example.com', http_client: http)

        expect { arc.broadcast(tx) }
          .to raise_error(BSV::Network::BroadcastError, 'Orphan transaction')
      end

      it 'raises BroadcastError when extraInfo contains ORPHAN' do
        body = {
          'txid' => 'abc123',
          'txStatus' => 'SEEN_ON_NETWORK',
          'title' => 'Orphan',
          'extraInfo' => 'transaction is an ORPHAN — missing parent tx'
        }.to_json
        http = mock_http.new(200, body)
        arc = described_class.new('https://arc.example.com', http_client: http)

        expect { arc.broadcast(tx) }
          .to raise_error(BSV::Network::BroadcastError)
      end
    end

    # Follow-up hardening from PR #306 review — match TS's case-insensitive
    # detection at `ts-sdk/src/transaction/broadcasters/ARC.ts:155-166`.
    # ARC's OpenAPI pins txStatus as an UPPERCASE enum, but ARC has a
    # documented history of emitting values outside its own contract
    # (TS issue #105), so normalisation is the defensive choice.
    describe 'case-insensitive failure status detection (#306 review)' do
      %w[rejected invalid malformed mined_in_stale_block REJECTED Invalid].each do |status|
        it "raises BroadcastError on txStatus #{status.inspect} (case-insensitive)" do
          body = { 'txid' => 'abc123', 'txStatus' => status, 'title' => 'rejected' }.to_json
          http = mock_http.new(200, body)
          arc = described_class.new('https://arc.example.com', http_client: http)

          expect { arc.broadcast(tx) }
            .to raise_error(BSV::Network::BroadcastError)
        end
      end

      it 'raises BroadcastError when extraInfo contains lowercase "orphan"' do
        body = {
          'txid' => 'abc123',
          'txStatus' => 'SEEN_ON_NETWORK',
          'title' => 'Orphan',
          'extraInfo' => 'transaction is an orphan — missing parent tx'
        }.to_json
        http = mock_http.new(200, body)
        arc = described_class.new('https://arc.example.com', http_client: http)

        expect { arc.broadcast(tx) }
          .to raise_error(BSV::Network::BroadcastError)
      end

      it 'raises BroadcastError when txStatus contains mixed-case "Orphan"' do
        body = {
          'txid' => 'abc123',
          'txStatus' => 'seen_in_Orphan_mempool'
        }.to_json
        http = mock_http.new(200, body)
        arc = described_class.new('https://arc.example.com', http_client: http)

        expect { arc.broadcast(tx) }
          .to raise_error(BSV::Network::BroadcastError)
      end
    end

    # Follow-up hardening from PR #306 review — guard against malformed
    # 2xx responses that would otherwise produce a silent "success"
    # BroadcastResponse full of nils.
    describe 'malformed 2xx response rejection (#306 review)' do
      it 'raises BroadcastError on a 2xx response that is not JSON' do
        http = mock_http.new(200, 'an ARC proxy wrote this plaintext response')
        arc = described_class.new('https://arc.example.com', http_client: http)

        expect { arc.broadcast(tx) }
          .to raise_error(BSV::Network::BroadcastError, /malformed/)
      end

      it 'raises BroadcastError on a 2xx JSON response without a txid' do
        body = { 'txStatus' => 'SEEN_ON_NETWORK' }.to_json # no txid
        http = mock_http.new(200, body)
        arc = described_class.new('https://arc.example.com', http_client: http)

        expect { arc.broadcast(tx) }
          .to raise_error(BSV::Network::BroadcastError, /malformed/)
      end

      it 'raises BroadcastError on a 2xx JSON response with explicit null txid' do
        body = { 'txid' => nil, 'txStatus' => 'SEEN_ON_NETWORK' }.to_json
        http = mock_http.new(200, body)
        arc = described_class.new('https://arc.example.com', http_client: http)

        expect { arc.broadcast(tx) }
          .to raise_error(BSV::Network::BroadcastError, /malformed/)
      end
    end

    it 'handles non-JSON response body gracefully' do
      http = mock_http.new(500, 'Internal Server Error')
      arc = described_class.new('https://arc.example.com', http_client: http)

      expect { arc.broadcast(tx) }.to raise_error(BSV::Network::BroadcastError) do |error|
        expect(error.message).to eq('Internal Server Error')
        expect(error.status_code).to eq(500)
      end
    end

    describe 'skip-validation headers (#340)' do
      it 'sends X-SkipFeeValidation header when skip_fee_validation: true' do
        http = mock_http.new(200, success_body)
        arc = described_class.new('https://arc.example.com', http_client: http)

        arc.broadcast(tx, skip_fee_validation: true)

        expect(http.last_request['X-SkipFeeValidation']).to eq('true')
      end

      it 'sends X-SkipScriptValidation header when skip_script_validation: true' do
        http = mock_http.new(200, success_body)
        arc = described_class.new('https://arc.example.com', http_client: http)

        arc.broadcast(tx, skip_script_validation: true)

        expect(http.last_request['X-SkipScriptValidation']).to eq('true')
      end

      it 'omits X-SkipFeeValidation and X-SkipScriptValidation when not set' do
        http = mock_http.new(200, success_body)
        arc = described_class.new('https://arc.example.com', http_client: http)

        arc.broadcast(tx)

        expect(http.last_request['X-SkipFeeValidation']).to be_nil
        expect(http.last_request['X-SkipScriptValidation']).to be_nil
      end

      it 'omits X-SkipFeeValidation and X-SkipScriptValidation when set to false' do
        http = mock_http.new(200, success_body)
        arc = described_class.new('https://arc.example.com', http_client: http)

        arc.broadcast(tx, skip_fee_validation: false, skip_script_validation: false)

        expect(http.last_request['X-SkipFeeValidation']).to be_nil
        expect(http.last_request['X-SkipScriptValidation']).to be_nil
      end

      it 'can set both skip headers simultaneously' do
        http = mock_http.new(200, success_body)
        arc = described_class.new('https://arc.example.com', http_client: http)

        arc.broadcast(tx, skip_fee_validation: true, skip_script_validation: true)

        expect(http.last_request['X-SkipFeeValidation']).to eq('true')
        expect(http.last_request['X-SkipScriptValidation']).to eq('true')
      end
    end
  end

  describe '#status' do
    it 'returns a BroadcastResponse for a known txid' do
      body = { 'txid' => 'abc123', 'txStatus' => 'MINED', 'blockHeight' => 800_000 }.to_json
      http = mock_http.new(200, body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      response = arc.status('abc123')

      expect(response).to be_a(BSV::Network::BroadcastResponse)
      expect(response.txid).to eq('abc123')
      expect(response.mined?).to be true
      expect(response.block_height).to eq(800_000)
    end

    it 'sends GET to /v1/tx/{txid}' do
      body = { 'txid' => 'abc123', 'txStatus' => 'SEEN_ON_NETWORK' }.to_json
      http = mock_http.new(200, body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      arc.status('abc123')

      expect(http.last_uri.to_s).to eq('https://arc.example.com/v1/tx/abc123')
      expect(http.last_request).to be_a(Net::HTTP::Get)
    end

    it 'raises BroadcastError on failure' do
      body = { 'title' => 'Not found', 'detail' => 'transaction not found' }.to_json
      http = mock_http.new(404, body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      expect { arc.status('unknown') }.to raise_error(BSV::Network::BroadcastError) do |error|
        expect(error.status_code).to eq(404)
      end
    end
  end

  describe 'authentication' do
    it 'sets Authorization header when api_key is provided' do
      http = mock_http.new(200, success_body)
      arc = described_class.new('https://arc.example.com', api_key: 'my-key', http_client: http)

      arc.broadcast(tx)

      expect(http.last_request['Authorization']).to eq('Bearer my-key')
    end

    it 'omits Authorization header when api_key is nil' do
      http = mock_http.new(200, success_body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      arc.broadcast(tx)

      expect(http.last_request['Authorization']).to be_nil
    end
  end

  describe 'URL normalisation' do
    it 'strips trailing slash from base URL' do
      http = mock_http.new(200, success_body)
      arc = described_class.new('https://arc.example.com/', http_client: http)

      arc.broadcast(tx)

      expect(http.last_uri.to_s).to eq('https://arc.example.com/v1/tx')
    end
  end

  describe '#broadcast_many' do
    # Second transaction double for multi-tx batch tests
    let(:tx2) do
      instance_double(
        BSV::Transaction::Transaction,
        to_ef_hex: '020000000000ef0000',
        to_hex: '02000000'
      )
    end

    # Reusable single-item batch response body (parses success_body JSON string)
    def single_batch(extra_txid: nil)
      item1 = JSON.parse(success_body)
      return [item1].to_json unless extra_txid

      item2 = item1.merge('txid' => extra_txid)
      [item1, item2].to_json
    end

    it 'POSTs to /v1/txs with a JSON array body' do
      http = mock_http.new(200, single_batch(extra_txid: 'def456'))
      arc = described_class.new('https://arc.example.com', http_client: http)

      arc.broadcast_many([tx, tx2])

      expect(http.last_uri.to_s).to eq('https://arc.example.com/v1/txs')
      expect(http.last_request).to be_a(Net::HTTP::Post)
      body = JSON.parse(http.last_request.body)
      expected = [{ 'rawTx' => '010000000000ef0000' }, { 'rawTx' => '020000000000ef0000' }]
      expect(body).to eq(expected)
    end

    it 'returns an array of BroadcastResponse on all-success' do
      http = mock_http.new(200, single_batch(extra_txid: 'def456'))
      arc = described_class.new('https://arc.example.com', http_client: http)

      results = arc.broadcast_many([tx, tx2])

      expect(results.length).to eq(2)
      expect(results[0]).to be_a(BSV::Network::BroadcastResponse)
      expect(results[0].txid).to eq('abc123')
      expect(results[1]).to be_a(BSV::Network::BroadcastResponse)
      expect(results[1].txid).to eq('def456')
    end

    it 'returns a mixed array when some txs are rejected' do
      rejected = {
        'txid' => 'def456',
        'txStatus' => 'REJECTED',
        'title' => 'Transaction rejected',
        'detail' => 'inputs already spent'
      }
      batch = [JSON.parse(success_body), rejected].to_json
      http = mock_http.new(200, batch)
      arc = described_class.new('https://arc.example.com', http_client: http)

      results = arc.broadcast_many([tx, tx2])

      expect(results[0]).to be_a(BSV::Network::BroadcastResponse)
      expect(results[0].txid).to eq('abc123')
      expect(results[1]).to be_a(BSV::Network::BroadcastError)
      expect(results[1].message).to eq('inputs already spent')
      expect(results[1].txid).to eq('def456')
      expect(results[1].status_code).to eq(200)
    end

    it 'raises BroadcastError on HTTP 500' do
      body = { 'title' => 'Internal error', 'detail' => 'server fault' }.to_json
      http = mock_http.new(500, body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      expect { arc.broadcast_many([tx]) }.to raise_error(BSV::Network::BroadcastError) do |error|
        expect(error.message).to eq('server fault')
        expect(error.status_code).to eq(500)
      end
    end

    it 'raises BroadcastError when ARC returns a non-array response body' do
      body = { 'txid' => 'abc123', 'txStatus' => 'SEEN_ON_NETWORK' }.to_json
      http = mock_http.new(200, body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      expect { arc.broadcast_many([tx]) }
        .to raise_error(BSV::Network::BroadcastError, /malformed batch response/)
    end

    it 'returns BroadcastError for batch items missing txid' do
      body = [{ 'txStatus' => 'SEEN_ON_NETWORK', 'title' => 'ok' }].to_json
      http = mock_http.new(200, body)
      arc = described_class.new('https://arc.example.com', http_client: http)

      results = arc.broadcast_many([tx])

      expect(results[0]).to be_a(BSV::Network::BroadcastError)
      expect(results[0].message).to match(/malformed/)
    end

    it 'uses EF hex for each tx when available' do
      http = mock_http.new(200, single_batch)
      arc = described_class.new('https://arc.example.com', http_client: http)

      arc.broadcast_many([tx])

      body = JSON.parse(http.last_request.body)
      expect(body[0]['rawTx']).to eq('010000000000ef0000')
    end

    it 'falls back to plain hex per tx when EF is unavailable' do
      http = mock_http.new(200, single_batch(extra_txid: 'def456'))
      arc = described_class.new('https://arc.example.com', http_client: http)

      arc.broadcast_many([tx_no_source, tx2])

      body = JSON.parse(http.last_request.body)
      expect(body[0]['rawTx']).to eq('01000000')
      expect(body[1]['rawTx']).to eq('020000000000ef0000')
    end

    it 'passes X-SkipFeeValidation and X-SkipScriptValidation headers when set' do
      http = mock_http.new(200, single_batch)
      arc = described_class.new('https://arc.example.com', http_client: http)

      arc.broadcast_many([tx], skip_fee_validation: true, skip_script_validation: true)

      expect(http.last_request['X-SkipFeeValidation']).to eq('true')
      expect(http.last_request['X-SkipScriptValidation']).to eq('true')
    end

    it 'omits skip-validation headers when not set' do
      http = mock_http.new(200, single_batch)
      arc = described_class.new('https://arc.example.com', http_client: http)

      arc.broadcast_many([tx])

      expect(http.last_request['X-SkipFeeValidation']).to be_nil
      expect(http.last_request['X-SkipScriptValidation']).to be_nil
    end

    it 'passes X-WaitFor header when wait_for is set' do
      http = mock_http.new(200, single_batch)
      arc = described_class.new('https://arc.example.com', http_client: http)

      arc.broadcast_many([tx], wait_for: 'SEEN_ON_NETWORK')

      expect(http.last_request['X-WaitFor']).to eq('SEEN_ON_NETWORK')
    end

    it 'returns an empty array without making an HTTP request when given empty input' do
      http = mock_http.new(200, '[]')
      arc = described_class.new('https://arc.example.com', http_client: http)

      results = arc.broadcast_many([])

      expect(results).to eq([])
      expect(http.last_request).to be_nil
    end
  end

  describe '.default' do
    it 'returns an ARC instance pointed at the mainnet GorillaPool endpoint' do
      http = mock_http.new(200, success_body)
      arc = described_class.default(http_client: http)

      expect(arc).to be_a(described_class)
      arc.broadcast(tx)
      expect(http.last_uri.host).to eq('arcade.gorillapool.io')
    end

    it 'returns an ARC instance pointed at the testnet GorillaPool endpoint' do
      http = mock_http.new(200, success_body)
      arc = described_class.default(testnet: true, http_client: http)
      arc.broadcast(tx)
      expect(http.last_uri.host).to eq('testnet.arcade.gorillapool.io')
    end

    it 'passes api_key through to the underlying instance' do
      http = mock_http.new(200, success_body)
      arc = described_class.default(api_key: 'x', http_client: http)
      arc.broadcast(tx)
      expect(http.last_request['Authorization']).to eq('Bearer x')
    end

    it 'passes callback_url through to the underlying instance' do
      http = mock_http.new(200, success_body)
      arc = described_class.default(callback_url: 'https://example.com/cb', http_client: http)
      arc.broadcast(tx)
      expect(http.last_request['X-CallbackUrl']).to eq('https://example.com/cb')
    end
  end
end
