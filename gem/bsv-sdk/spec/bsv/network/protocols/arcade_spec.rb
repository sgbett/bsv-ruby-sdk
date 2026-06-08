# frozen_string_literal: true

RSpec.describe BSV::Network::Protocols::Arcade do
  subject(:arcade) do
    described_class.new(
      base_url: 'https://arcade.example.com',
      http_client: http_client
    )
  end

  # rubocop:disable RSpec/VerifiedDoubles
  let(:http_client) { double('HttpClient') }
  # rubocop:enable RSpec/VerifiedDoubles

  def stub_response(code, body)
    response = fake_http_response(code, body)
    allow(http_client).to receive(:request).and_return(response)
    response
  end

  def stub_json_response(code, data)
    stub_response(code, JSON.generate(data))
  end

  def make_tx(ef_hex: nil, hex: 'deadbeef')
    tx = instance_double(BSV::Transaction::Tx)
    if ef_hex
      allow(tx).to receive(:to_ef_hex).and_return(ef_hex)
    else
      allow(tx).to receive(:to_ef_hex).and_raise(ArgumentError, 'source data missing')
    end
    allow(tx).to receive(:to_hex).and_return(hex)
    tx
  end

  describe '.commands' do
    it 'declares exactly the expected 3 endpoints' do
      expect(described_class.commands).to eq(
        Set.new(%i[broadcast get_tx_status health])
      )
    end
  end

  describe 'inheritance' do
    it 'is a subclass of BSV::Network::Protocol' do
      expect(described_class).to be < BSV::Network::Protocol
    end

    it 'is independent from ARC' do
      expect(described_class).not_to be < BSV::Network::Protocols::ARC
    end
  end

  describe '#call(:broadcast)' do
    context 'when transaction submits fresh (happy path)' do
      let(:tx) { make_tx(ef_hex: 'efhex123') }

      before { stub_json_response(200, { 'status' => 'submitted' }) }

      it 'returns success' do
        result = arcade.call(:broadcast, tx)
        expect(result).to be_http_success
      end

      it 'returns the status field' do
        result = arcade.call(:broadcast, tx)
        expect(result.data['status']).to eq('submitted')
      end

      it 'sends EF hex in the rawTx body field' do
        arcade.call(:broadcast, tx)
        expect(http_client).to have_received(:request) do |_uri, req|
          body = JSON.parse(req.body)
          expect(body['rawTx']).to eq('efhex123')
        end
      end
    end

    context 'when transaction is resubmitted (idempotent)' do
      before do
        stub_json_response(200, {
                             'status' => 'already submitted',
                             'txid' => 'abc123def456',
                             'state' => 'SEEN_ON_NETWORK'
                           })
      end

      it 'returns success' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result).to be_http_success
      end

      it 'preserves txid in data' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result.data['txid']).to eq('abc123def456')
      end

      it 'preserves state in data' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result.data['state']).to eq('SEEN_ON_NETWORK')
      end
    end

    context 'when Arcade returns 200 with status only and no txid' do
      before { stub_json_response(200, { 'status' => 'submitted' }) }

      it 'returns success without requiring txid' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result).to be_http_success
      end
    end

    context 'when EF serialisation is unavailable (fallback to raw hex)' do
      let(:tx) { make_tx(ef_hex: nil, hex: 'rawhex456') }

      before { stub_json_response(200, { 'status' => 'submitted' }) }

      it 'falls back to raw hex' do
        arcade.call(:broadcast, tx)
        expect(http_client).to have_received(:request) do |_uri, req|
          body = JSON.parse(req.body)
          expect(body['rawTx']).to eq('rawhex456')
        end
      end
    end

    context 'when tx is a hex string' do
      before { stub_json_response(200, { 'status' => 'submitted' }) }

      it 'passes the hex string through as rawTx' do
        arcade.call(:broadcast, 'aabbccdd')
        expect(http_client).to have_received(:request) do |_uri, req|
          body = JSON.parse(req.body)
          expect(body['rawTx']).to eq('aabbccdd')
        end
      end
    end

    context 'when tx is a binary string' do
      before { stub_json_response(200, { 'status' => 'submitted' }) }

      it 'converts binary to hex for rawTx' do
        arcade.call(:broadcast, "\xDE\xAD\xBE\xEF".b)
        expect(http_client).to have_received(:request) do |_uri, req|
          body = JSON.parse(req.body)
          expect(body['rawTx']).to eq('deadbeef')
        end
      end
    end

    context 'when Arcade returns 400 with a reason' do
      before { stub_json_response(400, { 'reason' => 'transaction is invalid' }) }

      it 'returns failure' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result).not_to be_http_success
      end

      it 'surfaces the reason in error_message' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result.error_message).to include('transaction is invalid')
      end

      it 'is not retryable' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result.retryable?).to be(false)
      end

      it 'preserves the parsed body in data so callers can read it' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result.data).to eq('reason' => 'transaction is invalid')
      end
    end

    context 'when Arcade returns 4xx with txStatus and extraInfo (terminal rejection shape)' do
      before { stub_json_response(400, { 'txStatus' => 'REJECTED', 'extraInfo' => 'double spend' }) }

      it 'exposes txStatus and extraInfo via data so callers can detect rejection' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result).not_to be_http_success
        expect(result.data['txStatus']).to eq('REJECTED')
        expect(result.data['extraInfo']).to eq('double spend')
      end
    end

    context 'when Arcade returns 503 with Retry-After header' do
      before do
        response = fake_http_response(503, '')
        response['Retry-After'] = '30'
        allow(http_client).to receive(:request).and_return(response)
      end

      it 'returns failure' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result).not_to be_http_success
      end

      it 'is retryable' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result.retryable?).to be(true)
      end

      it 'includes retry delay in error_message' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result.error_message).to include('retry after 30s')
      end
    end

    context 'when Arcade returns 503 without Retry-After header' do
      before { stub_response(503, '') }

      it 'is retryable' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result.retryable?).to be(true)
      end

      it 'omits retry delay from error_message' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result.error_message).not_to include('retry after')
      end
    end

    context 'when Arcade returns 500' do
      before { stub_json_response(500, { 'detail' => 'internal error' }) }

      it 'returns failure' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result).not_to be_http_success
      end

      it 'is retryable' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result.retryable?).to be(true)
      end
    end

    context 'when Arcade returns a malformed 2xx (missing status)' do
      before { stub_json_response(200, { 'txid' => 'somehex' }) }

      it 'returns failure' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result).not_to be_http_success
      end

      it 'reports malformed in error_message' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result.error_message).to include('malformed')
      end
    end

    context 'when Arcade returns a non-JSON 2xx body' do
      before { stub_response(200, 'not json at all') }

      it 'returns failure' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result).not_to be_http_success
      end

      it 'reports malformed in error_message' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result.error_message).to include('malformed')
      end
    end

    context 'when Arcade returns a 2xx with JSON that is not a Hash (Array)' do
      before { stub_response(200, JSON.generate([{ 'status' => 'submitted' }])) }

      it 'returns failure' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result).not_to be_http_success
      end

      it 'reports malformed in error_message' do
        result = arcade.call(:broadcast, 'deadbeef')
        expect(result.error_message).to include('malformed')
      end
    end

    context 'with Arcade-specific optional headers' do
      before { stub_json_response(200, { 'status' => 'submitted' }) }

      it 'sends X-CallbackUrl when specified' do
        arcade.call(:broadcast, 'deadbeef', callback_url: 'https://cb.example.com')
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['X-CallbackUrl']).to eq('https://cb.example.com')
        end
      end

      it 'sends X-CallbackToken when specified' do
        arcade.call(:broadcast, 'deadbeef', callback_token: 'secret-token')
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['X-CallbackToken']).to eq('secret-token')
        end
      end

      it 'sends X-FullStatusUpdates when truthy' do
        arcade.call(:broadcast, 'deadbeef', full_status_updates: true)
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['X-FullStatusUpdates']).to eq('true')
        end
      end

      it 'sends X-SkipFeeValidation when truthy' do
        arcade.call(:broadcast, 'deadbeef', skip_fee_validation: true)
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['X-SkipFeeValidation']).to eq('true')
        end
      end

      it 'sends X-SkipScriptValidation when truthy' do
        arcade.call(:broadcast, 'deadbeef', skip_script_validation: true)
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['X-SkipScriptValidation']).to eq('true')
        end
      end

      it 'does not send XDeployment-ID (ARC-only header)' do
        arcade.call(:broadcast, 'deadbeef')
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['XDeployment-ID']).to be_nil
        end
      end

      it 'does not send X-SkipTxValidation (ARC-only header)' do
        arcade.call(:broadcast, 'deadbeef')
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['X-SkipTxValidation']).to be_nil
        end
      end

      it 'does not send X-CallbackBatch (ARC-only header)' do
        arcade.call(:broadcast, 'deadbeef')
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['X-CallbackBatch']).to be_nil
        end
      end
    end

    context 'with constructor-level callback configuration' do
      let(:arcade_with_callbacks) do
        described_class.new(
          base_url: 'https://arcade.example.com',
          callback_url: 'https://my-callback.example.com',
          callback_token: 'cb-token',
          http_client: http_client
        )
      end

      before { stub_json_response(200, { 'status' => 'submitted' }) }

      it 'sends X-CallbackUrl from constructor' do
        arcade_with_callbacks.call(:broadcast, 'deadbeef')
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['X-CallbackUrl']).to eq('https://my-callback.example.com')
        end
      end

      it 'sends X-CallbackToken from constructor' do
        arcade_with_callbacks.call(:broadcast, 'deadbeef')
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req['X-CallbackToken']).to eq('cb-token')
        end
      end
    end
  end

  describe '#call(:get_tx_status)' do
    context 'when transaction exists and is mined' do
      before do
        stub_json_response(200, {
                             'txid' => 'abc',
                             'txStatus' => 'MINED',
                             'status' => 200,
                             'timestamp' => '2026-05-29T00:00:00Z',
                             'blockHash' => 'bh',
                             'blockHeight' => 800_000,
                             'merklePath' => 'mp_hex',
                             'extraInfo' => nil,
                             'competingTxs' => nil
                           })
      end

      it 'returns success' do
        result = arcade.call(:get_tx_status, 'abc')
        expect(result).to be_http_success
      end

      it 'exposes the txStatus field' do
        result = arcade.call(:get_tx_status, 'abc')
        expect(result.data['txStatus']).to eq('MINED')
      end
    end

    context 'when transaction is not found' do
      before { stub_response(404, '{"error":"transaction not found"}') }

      it 'returns failure' do
        result = arcade.call(:get_tx_status, 'unknown_txid')
        expect(result).not_to be_http_success
      end

      it 'is marked http_not_found' do
        result = arcade.call(:get_tx_status, 'unknown_txid')
        expect(result).to be_http_not_found
      end
    end

    context 'when transaction has a rejected status' do
      before { stub_json_response(200, { 'txid' => 'abc', 'txStatus' => 'REJECTED' }) }

      it 'returns failure' do
        result = arcade.call(:get_tx_status, 'abc')
        expect(result).not_to be_http_success
      end

      it 'surfaces the REJECTED status in error_message' do
        result = arcade.call(:get_tx_status, 'abc')
        expect(result.error_message).to include('REJECTED')
      end
    end

    context 'when txStatus is lowercase rejected (case-insensitive)' do
      before { stub_json_response(200, { 'txid' => 'abc', 'txStatus' => 'rejected' }) }

      it 'returns failure' do
        result = arcade.call(:get_tx_status, 'abc')
        expect(result).not_to be_http_success
      end
    end

    context 'when server returns 500' do
      before { stub_response(500, 'Internal server error') }

      it 'returns retryable error' do
        result = arcade.call(:get_tx_status, 'abc')
        expect(result).not_to be_http_success
        expect(result.retryable?).to be(true)
      end
    end
  end

  describe '#call(:health)' do
    before do
      stub_json_response(200, {
                           'status' => 'ok',
                           'datahub_urls' => [{ 'url' => 'wss://example.com', 'healthy' => true }]
                         })
    end

    it 'returns success' do
      result = arcade.call(:health)
      expect(result).to be_http_success
    end

    it 'exposes datahub_urls as an Array' do
      result = arcade.call(:health)
      expect(result.data['datahub_urls']).to be_an(Array)
    end
  end
end
