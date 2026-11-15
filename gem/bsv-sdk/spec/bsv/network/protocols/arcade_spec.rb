# frozen_string_literal: true

require 'logger'
require 'stringio'

RSpec.describe BSV::Network::Protocols::Arcade do
  subject(:arcade) do
    described_class.new(
      base_url: 'https://arcade.example.com',
      http_client: http_client
    )
  end

  # rubocop:disable-next RSpec/VerifiedDoubles
  let(:http_client) { double('HttpClient') }
  let(:txid) { 'ab' * 32 }
  let(:ef_tx) { EfFixtures.ef_tx }
  let(:ef_hex) { ef_tx.to_ef_hex }

  def stub_response(code, body, headers: {})
    response = fake_http_response(code, body)
    headers.each { |name, value| response[name] = value }
    allow(http_client).to receive(:request).and_return(response)
    response
  end

  def stub_json_response(code, data, headers: {})
    stub_response(code, JSON.generate(data), headers: headers)
  end

  def sent_request
    request = nil
    expect(http_client).to have_received(:request) { |_uri, req| request = req }
    request
  end

  def sent_raw_tx
    JSON.parse(sent_request.body)['rawTx']
  end

  def accepted(extra = {})
    { 'txid' => txid, 'status' => 202, 'txStatus' => 'RECEIVED' }.merge(extra)
  end

  describe '.commands' do
    it 'declares exactly the expected 4 endpoints' do
      expect(described_class.commands).to eq(
        Set.new(%i[broadcast get_tx_status get_policy health])
      )
    end

    it 'routes endpoints at the service root' do
      expect(described_class.endpoints.transform_values { |defn| [defn[:method], defn[:path]] }).to eq(
        broadcast: [:post, '/tx'],
        get_tx_status: [:get, '/tx/{txid}'],
        get_policy: [:get, '/policy'],
        health: [:get, '/health']
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
    context 'when the service accepts the transaction' do
      before { stub_json_response(202, accepted) }

      it 'returns success with the parsed body' do
        result = arcade.call(:broadcast, ef_tx)
        expect(result).to be_http_success
        expect(result.data['txid']).to eq(txid)
        expect(result.data['status']).to eq(202)
        expect(result.data['txStatus']).to eq('RECEIVED')
      end

      it 'POSTs to /tx' do
        arcade.call(:broadcast, ef_tx)
        expect(http_client).to have_received(:request) do |_uri, req|
          expect(req.path).to eq('/tx')
          expect(req.method).to eq('POST')
        end
      end

      it 'sends Extended Format hex as rawTx' do
        arcade.call(:broadcast, ef_tx)
        expect(sent_raw_tx).to eq(ef_hex)
        expect(sent_raw_tx[8, 12]).to eq('0000000000ef')
      end
    end

    context 'when the status is not echoed' do
      it 'accepts SEEN_MULTIPLE_NODES without a status field' do
        stub_json_response(200, { 'txid' => txid, 'txStatus' => 'SEEN_MULTIPLE_NODES' })
        expect(arcade.call(:broadcast, ef_tx)).to be_http_success
      end

      it 'accepts a body with no txStatus' do
        stub_json_response(200, { 'txid' => txid })
        expect(arcade.call(:broadcast, ef_tx)).to be_http_success
      end
    end

    context 'when a 2xx body is malformed' do
      {
        'legacy status-only body' => '{"status":"submitted"}',
        'missing txid' => '{"txStatus":"RECEIVED","status":202}',
        'non-hex txid' => '{"txid":"not-a-txid","txStatus":"RECEIVED"}',
        'short txid' => '{"txid":"abcd","txStatus":"RECEIVED"}',
        'non-string txid' => '{"txid":5,"txStatus":"RECEIVED"}',
        'invalid UTF-8 txid' => %({"txid":"\xFF\xFE#{'ab' * 31}","txStatus":"RECEIVED"}).b,
        'array txStatus' => %({"txid":"#{'ab' * 32}","txStatus":["REJECTED"]}),
        'numeric txStatus' => %({"txid":"#{'ab' * 32}","txStatus":7}),
        'array' => '[]',
        'null' => 'null',
        'HTML' => '<html>OK</html>'
      }.each do |label, raw|
        it "fails for #{label}" do
          stub_response(200, raw)
          result = arcade.call(:broadcast, ef_tx)
          expect(result).not_to be_http_success
          expect(result.error_message).to eq('BSV Broadcaster returned a malformed 2xx response')
        end
      end
    end

    context 'when the status is a rejection' do
      %w[REJECTED rejected DOUBLE_SPEND_ATTEMPTED].each do |status|
        it "fails for #{status} and keeps the body" do
          stub_json_response(202, accepted('txStatus' => status, 'extraInfo' => 'bad sig', 'title' => 'OK'))
          result = arcade.call(:broadcast, ef_tx)
          expect(result).not_to be_http_success
          expect(result.error_message).to eq("#{status}: bad sig")
          expect(result.data['txid']).to eq(txid)
        end
      end

      it 'reports the bare status when extraInfo is absent' do
        stub_json_response(200, accepted('txStatus' => 'REJECTED'))
        expect(arcade.call(:broadcast, ef_tx).error_message).to eq('REJECTED')
      end
    end

    context 'when extraInfo mentions an orphan' do
      %w[PENDING_RETRY MINED].each do |status|
        it "does not treat a #{status} row as rejected" do
          stub_json_response(200, accepted('txStatus' => status, 'extraInfo' => 'upstream said: orphan block'))
          expect(arcade.call(:broadcast, ef_tx)).to be_http_success
        end
      end
    end

    context 'when the service reports a validation failure' do
      before do
        stub_json_response(400, {
                             'error' => 'transaction failed validation',
                             'reason' => 'script evaluation failed',
                             'txid' => txid,
                             'status' => 461,
                             'title' => 'Unlocking scripts are invalid',
                             'detail' => 'input 0',
                             'type' => 'https://example.com/errors/461'
                           })
      end

      it 'joins error and reason and keeps the ARC code in data' do
        result = arcade.call(:broadcast, ef_tx)
        expect(result).not_to be_http_success
        expect(result.error_message).to eq('transaction failed validation: script evaluation failed')
        expect(result.data['status']).to eq(461)
        expect(result.data['txid']).to eq(txid)
      end
    end

    context 'when the service returns other non-2xx bodies' do
      [401, 403].each do |code|
        it "reports the error text for #{code}" do
          stub_json_response(code, { 'error' => 'invalid credentials' })
          result = arcade.call(:broadcast, ef_tx)
          expect(result.error_message).to eq('invalid credentials')
        end
      end

      it 'falls back to detail when there is no error' do
        stub_json_response(422, { 'detail' => 'unprocessable' })
        expect(arcade.call(:broadcast, ef_tx).error_message).to eq('unprocessable')
      end

      it 'never echoes a non-JSON body' do
        stub_response(500, '<html>Internal secret stack trace</html>')
        result = arcade.call(:broadcast, ef_tx)
        expect(result.error_message).to eq('HTTP 500')
        expect(result.data).to be_nil
      end

      it 'cleans control characters out of service text' do
        stub_json_response(400, { 'error' => "bad\e[31m input\nline" })
        expect(arcade.call(:broadcast, ef_tx).error_message).to eq('bad [31m input line')
      end
    end

    context 'when the service signals backpressure' do
      it 'reports 503 with an integer Retry-After' do
        stub_json_response(503, { 'error' => 'busy' }, headers: { 'Retry-After' => '1' })
        result = arcade.call(:broadcast, ef_tx)
        expect(result).not_to be_http_success
        expect(result.error_message).to eq('BSV Broadcaster backpressure (HTTP 503); retry after 1s')
        expect(result.data).to eq('error' => 'busy')
        expect(result).to be_retryable
      end

      it 'reports 429 with an integer Retry-After' do
        stub_json_response(429, { 'error' => 'slow down' }, headers: { 'Retry-After' => '30' })
        expect(arcade.call(:broadcast, ef_tx).error_message)
          .to eq('BSV Broadcaster rate limit (HTTP 429); retry after 30s')
      end

      ['soon', 'Wed, 21 Oct 2026 07:28:00 GMT', '-5', '1234567', ''].each do |junk|
        it "omits a Retry-After of #{junk.inspect}" do
          stub_response(503, '<html>busy</html>', headers: { 'Retry-After' => junk })
          result = arcade.call(:broadcast, ef_tx)
          expect(result.error_message).to eq('BSV Broadcaster backpressure (HTTP 503)')
          expect(result.data).to be_nil
        end
      end

      it 'omits retry after when the header is absent' do
        stub_response(503, '')
        expect(arcade.call(:broadcast, ef_tx).error_message).to eq('BSV Broadcaster backpressure (HTTP 503)')
      end
    end

    context 'with the transaction in different forms' do
      before { stub_json_response(202, accepted) }

      it 'accepts upper-case Extended Format hex' do
        expect(arcade.call(:broadcast, ef_hex.upcase)).to be_http_success
        expect(sent_raw_tx).to eq(ef_hex.upcase)
      end

      it 'accepts binary Extended Format and sends it as hex' do
        expect(arcade.call(:broadcast, ef_tx.to_ef)).to be_http_success
        expect(sent_raw_tx).to eq(ef_hex)
      end

      it 'accepts Extended Format hex with a trailing newline' do
        expect(arcade.call(:broadcast, "#{ef_hex}\n")).to be_http_success
        expect(sent_raw_tx).to eq(ef_hex)
      end
    end

    context 'when the transaction is not in Extended Format' do
      {
        'plain hex' => -> { EfFixtures.ef_tx.to_hex },
        'BEEF hex' => -> { "0100beef#{'00' * 40}" },
        'a 10-byte plain transaction' => -> { '010000000000000000ef' },
        'an empty string' => -> { '' },
        'a transaction without source data' => -> { EfFixtures.tx_without_source_data }
      }.each do |label, build|
        it "raises ArgumentError naming Extended Format for #{label} and sends nothing" do
          allow(http_client).to receive(:request)
          message = label == 'an empty string' ? /empty/ : /Extended Format/
          expect { arcade.call(:broadcast, build.call) }.to raise_error(ArgumentError, message)
          expect(http_client).not_to have_received(:request)
        end
      end
    end

    context 'with the removed validation keywords' do
      %i[skip_fee_validation skip_script_validation].each do |keyword|
        it "raises ArgumentError for #{keyword}" do
          allow(http_client).to receive(:request)
          expect { arcade.call(:broadcast, ef_tx, keyword => true) }.to raise_error(ArgumentError)
          expect(http_client).not_to have_received(:request)
        end
      end
    end

    context 'with headers' do
      before { stub_json_response(202, accepted) }

      def sent_header_names
        sent_request.each_name.to_a
      end

      it 'sends neither skip headers nor XDeployment-ID by default' do
        arcade.call(:broadcast, ef_tx)
        names = sent_header_names
        expect(names.grep(/skip/i)).to be_empty
        expect(names).not_to include('xdeployment-id')
        expect(names).not_to include('x-callbackurl', 'x-callbacktoken', 'x-fullstatusupdates')
      end

      it 'sends the per-call callback headers and full status updates' do
        arcade.call(:broadcast, ef_tx, callback_url: 'https://cb.example.com', callback_token: 'tok',
                                       full_status_updates: true)
        request = sent_request
        expect(request['X-CallbackUrl']).to eq('https://cb.example.com')
        expect(request['X-CallbackToken']).to eq('tok')
        expect(request['X-FullStatusUpdates']).to eq('true')
      end

      it 'sends callback headers from the constructor' do
        configured = described_class.new(base_url: 'https://arcade.example.com', http_client: http_client,
                                         callback_url: 'https://ctor.example.com', callback_token: 'ctor-tok')
        configured.call(:broadcast, ef_tx)
        request = sent_request
        expect(request['X-CallbackUrl']).to eq('https://ctor.example.com')
        expect(request['X-CallbackToken']).to eq('ctor-tok')
      end

      it 'lets per-call callback values override the constructor' do
        configured = described_class.new(base_url: 'https://arcade.example.com', http_client: http_client,
                                         callback_url: 'https://ctor.example.com')
        configured.call(:broadcast, ef_tx, callback_url: 'https://call.example.com')
        expect(sent_request['X-CallbackUrl']).to eq('https://call.example.com')
      end
    end
  end

  describe '#call(:get_tx_status)' do
    context 'with debug logging enabled' do
      let(:log) { StringIO.new }

      before { allow(BSV).to receive(:logger).and_return(Logger.new(log, level: Logger::DEBUG)) }

      it 'does not log a credential reflected in an error body' do
        stub_json_response(401, { 'error' => 'bad key', 'reason' => 'Bearer SEKRET' })
        expect(arcade.call(:get_tx_status, txid).error_message).to include('SEKRET')
        expect(log.string).not_to include('SEKRET')
      end
    end

    context 'when the transaction is mined without a merkle path' do
      before { stub_json_response(200, { 'txid' => txid, 'txStatus' => 'MINED', 'blockHeight' => 850_000 }) }

      it 'returns success' do
        result = arcade.call(:get_tx_status, txid)
        expect(result).to be_http_success
        expect(result.data['txStatus']).to eq('MINED')
      end

      it 'GETs /tx/{txid}' do
        arcade.call(:get_tx_status, txid)
        expect(sent_request.path).to eq("/tx/#{txid}")
      end
    end

    context 'when the transaction is not found' do
      before { stub_json_response(404, { 'error' => 'transaction not found' }) }

      it 'reports the error text and stays a not-found response' do
        result = arcade.call(:get_tx_status, txid)
        expect(result).not_to be_http_success
        expect(result).to be_http_not_found
        expect(result.error_message).to eq('transaction not found')
      end
    end

    context 'when the service fails with a non-JSON body' do
      before { stub_response(500, '<html>boom</html>') }

      it 'reports the HTTP code and stays retryable' do
        result = arcade.call(:get_tx_status, txid)
        expect(result.error_message).to eq('HTTP 500')
        expect(result).to be_retryable
      end
    end

    context 'when the transport fails' do
      before { allow(http_client).to receive(:request).and_raise(Errno::ECONNREFUSED) }

      it 'passes the transport failure through unchanged' do
        result = arcade.call(:get_tx_status, txid)
        expect(result).not_to be_http_success
        expect(result.error_message).to start_with('transport error: Errno::ECONNREFUSED')
      end
    end

    context 'when the status is a rejection' do
      before { stub_json_response(200, { 'txid' => txid, 'txStatus' => 'REJECTED', 'extraInfo' => 'bad sig' }) }

      it 'fails with the status and extraInfo' do
        result = arcade.call(:get_tx_status, txid)
        expect(result).not_to be_http_success
        expect(result.error_message).to eq('REJECTED: bad sig')
      end
    end

    context 'when a 2xx body is malformed' do
      ['[]', '5', 'null', '{"txStatus":"MINED"}', '{"txid":"nope","txStatus":"MINED"}',
       %({"txid":"\xFF\xFE#{'ab' * 31}","txStatus":"MINED"}).b].each do |raw|
        it "fails for #{raw}" do
          stub_response(200, raw)
          result = arcade.call(:get_tx_status, txid)
          expect(result).not_to be_http_success
          expect(result.error_message).to eq('BSV Broadcaster returned a malformed 2xx response')
        end
      end
    end

    context 'when a 2xx status reply is not JSON' do
      ['<html>OK</html>', ''].each do |raw|
        it "reports a malformed 2xx for #{raw.inspect}" do
          stub_response(200, raw)
          result = arcade.call(:get_tx_status, txid)
          expect(result).not_to be_http_success
          expect(result.error_message).to eq('BSV Broadcaster returned a malformed 2xx response')
        end
      end
    end

    context 'when a 2xx status reply names a different transaction' do
      it 'fails as malformed' do
        stub_json_response(200, { 'txid' => 'cd' * 32, 'txStatus' => 'MINED' })
        result = arcade.call(:get_tx_status, txid)
        expect(result).not_to be_http_success
        expect(result.error_message).to eq('BSV Broadcaster returned a malformed 2xx response')
      end

      it 'accepts the requested txid in a different case' do
        stub_json_response(200, { 'txid' => txid.upcase, 'txStatus' => 'MINED' })
        expect(arcade.call(:get_tx_status, txid)).to be_http_success
      end
    end

    context 'when a 2xx status reply has a non-string txStatus' do
      [['REJECTED'], 7].each do |status|
        it "fails for #{status.inspect}" do
          stub_json_response(200, { 'txid' => txid, 'txStatus' => status })
          result = arcade.call(:get_tx_status, txid)
          expect(result).not_to be_http_success
          expect(result.error_message).to eq('BSV Broadcaster returned a malformed 2xx response')
        end
      end
    end

    context 'when the txid is invalid' do
      ['../policy', "#{'ab' * 31}a", ['ab' * 32].pack('H*')].each do |bad|
        it "raises ArgumentError before any request for a #{bad.length}-character txid" do
          allow(http_client).to receive(:request)
          expect { arcade.call(:get_tx_status, bad) }.to raise_error(ArgumentError, /txid/)
          expect(http_client).not_to have_received(:request)
        end
      end
    end
  end

  describe '#call(:get_policy)' do
    let(:policy) do
      {
        'policy' => { 'miningFee' => { 'satoshis' => 100, 'bytes' => 1000 }, 'maxTxSize' => 4_294_967_296 },
        'timestamp' => '2026-11-15T00:00:00Z'
      }
    end

    before { stub_json_response(200, policy) }

    it 'GETs /policy and returns the parsed body' do
      result = arcade.call(:get_policy)
      expect(result).to be_http_success
      expect(result.data['policy']['miningFee']).to eq('satoshis' => 100, 'bytes' => 1000)
      expect(sent_request.path).to eq('/policy')
    end
  end

  describe '#call(:health)' do
    it 'GETs /health' do
      stub_json_response(200, { 'status' => 'ok' })
      result = arcade.call(:health)
      expect(result).to be_http_success
      expect(sent_request.path).to eq('/health')
    end
  end
end
