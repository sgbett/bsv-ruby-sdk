# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::Substrates::HTTPWalletJSON do
  let(:base_url) { 'http://wallet.example.com:3321' }
  let(:substrate) { described_class.new(base_url) }
  let(:substrate_with_originator) do
    described_class.new(base_url, originator: 'myapp.example.com')
  end

  # Builds a minimal fake Net::HTTP response.
  def stub_response(body, code: '200')
    response = instance_double(Net::HTTPResponse)
    allow(response).to receive(:code).and_return(code)
    allow(response).to receive(:body).and_return(JSON.generate(body))
    response
  end

  # Stubs Net::HTTP.start to capture the request and return a canned response.
  def stub_http(response)
    allow(Net::HTTP).to receive(:start).and_yield(stub_http_session(response))
  end

  def stub_http_session(response)
    session = instance_double(Net::HTTP)
    allow(session).to receive(:request).and_return(response)
    session
  end

  # -------------------------------------------------------------------------
  # Constructor
  # -------------------------------------------------------------------------

  describe '#initialize' do
    it 'stores base_url' do
      expect(substrate.instance_variable_get(:@base_url)).to eq(base_url)
    end

    it 'stores originator when provided' do
      s = described_class.new(base_url, originator: 'app.example.com')
      expect(s.instance_variable_get(:@originator)).to eq('app.example.com')
    end

    it 'stores http_client when provided' do
      client = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      s = described_class.new(base_url, http_client: client)
      expect(s.instance_variable_get(:@http_client)).to eq(client)
    end

    it 'defaults originator to nil' do
      expect(substrate.instance_variable_get(:@originator)).to be_nil
    end

    it 'defaults http_client to nil' do
      expect(substrate.instance_variable_get(:@http_client)).to be_nil
    end
  end

  # -------------------------------------------------------------------------
  # METHOD_NAMES constant
  # -------------------------------------------------------------------------

  describe 'METHOD_NAMES' do
    it 'contains all 28 interface method symbols' do
      expect(described_class::METHOD_NAMES.keys).to match_array(
        BSV::Wallet::Wire::Serializer::CALL_CODES.keys
      )
    end

    it 'maps :get_public_key to "getPublicKey"' do
      expect(described_class::METHOD_NAMES[:get_public_key]).to eq('getPublicKey')
    end

    it 'maps :create_action to "createAction"' do
      expect(described_class::METHOD_NAMES[:create_action]).to eq('createAction')
    end

    it 'maps :list_outputs to "listOutputs"' do
      expect(described_class::METHOD_NAMES[:list_outputs]).to eq('listOutputs')
    end

    it 'maps :is_authenticated to "isAuthenticated"' do
      expect(described_class::METHOD_NAMES[:is_authenticated]).to eq('isAuthenticated')
    end
  end

  # -------------------------------------------------------------------------
  # HTTP request routing — correct endpoint per method
  # -------------------------------------------------------------------------

  describe 'HTTP endpoint routing' do
    BSV::Wallet::Wire::Serializer::CALL_CODES.each_key do |method_sym|
      camel = BSV::WireFormat.snake_to_camel(method_sym.to_s)

      it "POSTs to /#{camel} for ##{method_sym}" do
        expected_uri = URI.parse("#{base_url}/#{camel}")
        response = stub_response({})

        allow(Net::HTTP).to receive(:start)
          .with(expected_uri.host, expected_uri.port, use_ssl: false)
          .and_yield(stub_http_session(response))

        substrate.public_send(method_sym, {})
      end
    end
  end

  # -------------------------------------------------------------------------
  # Key conversion — to_wire on outbound, from_wire on inbound
  # -------------------------------------------------------------------------

  describe 'key conversion' do
    it 'converts snake_case arg keys to camelCase in the request body' do
      captured_body = nil
      session = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(session)
      allow(session).to receive(:request) do |req|
        captured_body = req.body
        stub_response({ 'publicKey' => '02abc' })
      end

      substrate.get_public_key({ identity_key: true })

      parsed = JSON.parse(captured_body)
      expect(parsed).to have_key('identityKey')
      expect(parsed).not_to have_key('identity_key')
    end

    it 'converts camelCase response keys to snake_case symbols' do
      stub_http(stub_response({ 'publicKey' => '02abc123' }))

      result = substrate.get_public_key({ identity_key: true })

      expect(result).to eq({ public_key: '02abc123' })
    end

    it 'handles nested camelCase response keys' do
      body = { 'totalActions' => 1, 'actions' => [{ 'txid' => 'aa', 'lockingScript' => 'dead' }] }
      stub_http(stub_response(body))

      result = substrate.list_actions({ labels: ['test'] })

      expect(result[:total_actions]).to eq(1)
      expect(result[:actions].first[:locking_script]).to eq('dead')
    end

    it 'sends empty JSON object for empty args' do
      captured_body = nil
      session = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(session)
      allow(session).to receive(:request) do |req|
        captured_body = req.body
        stub_response({ 'height' => 800_000 })
      end

      substrate.get_height({})

      expect(captured_body).to eq('{}')
    end

    it 'passes array values through without key conversion' do
      captured_body = nil
      session = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(session)
      allow(session).to receive(:request) do |req|
        captured_body = req.body
        stub_response({ 'ciphertext' => [1, 2, 3] })
      end

      substrate.encrypt({ plaintext: [10, 20, 30], protocol_id: [2, 'test'], key_id: 'k1' })

      parsed = JSON.parse(captured_body)
      expect(parsed['plaintext']).to eq([10, 20, 30])
    end
  end

  # -------------------------------------------------------------------------
  # Request headers
  # -------------------------------------------------------------------------

  describe 'request headers' do
    it 'sets Content-Type: application/json' do
      captured_headers = nil
      session = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(session)
      allow(session).to receive(:request) do |req|
        captured_headers = req.to_hash
        stub_response({})
      end

      substrate.get_height({})

      expect(captured_headers['content-type']).to include('application/json')
    end

    it 'sets Accept: application/json' do
      captured_headers = nil
      session = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(session)
      allow(session).to receive(:request) do |req|
        captured_headers = req.to_hash
        stub_response({})
      end

      substrate.get_height({})

      expect(captured_headers['accept']).to include('application/json')
    end

    context 'with originator set' do
      it 'sends Origin header' do
        captured_headers = nil
        session = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:start).and_yield(session)
        allow(session).to receive(:request) do |req|
          captured_headers = req.to_hash
          stub_response({})
        end

        substrate_with_originator.get_height({})

        expect(captured_headers['origin']).to include('http://myapp.example.com')
      end

      it 'sends Originator header' do
        captured_headers = nil
        session = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:start).and_yield(session)
        allow(session).to receive(:request) do |req|
          captured_headers = req.to_hash
          stub_response({})
        end

        substrate_with_originator.get_height({})

        expect(captured_headers['originator']).to include('http://myapp.example.com')
      end

      it 'does not send Origin/Originator when originator is nil' do
        captured_headers = nil
        session = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:start).and_yield(session)
        allow(session).to receive(:request) do |req|
          captured_headers = req.to_hash
          stub_response({})
        end

        substrate.get_height({})

        expect(captured_headers).not_to have_key('origin')
        expect(captured_headers).not_to have_key('originator')
      end

      it 'keeps scheme when originator already has one' do
        s = described_class.new(base_url, originator: 'https://myapp.example.com')
        captured_headers = nil
        session = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:start).and_yield(session)
        allow(session).to receive(:request) do |req|
          captured_headers = req.to_hash
          stub_response({})
        end

        s.get_height({})

        expect(captured_headers['origin']).to include('https://myapp.example.com')
      end
    end
  end

  # -------------------------------------------------------------------------
  # Error handling
  # -------------------------------------------------------------------------

  describe 'error handling' do
    it 'raises WalletError with message from response body on non-2xx' do
      stub_http(stub_response({ 'message' => 'something went wrong' }, code: '500'))

      expect { substrate.get_height({}) }.to raise_error(
        BSV::Wallet::WalletError, 'something went wrong'
      )
    end

    it 'raises WalletError with fallback message when response has no message field' do
      stub_http(stub_response({}, code: '503'))

      expect { substrate.get_height({}) }.to raise_error(
        BSV::Wallet::WalletError, /HTTP 503/
      )
    end

    it 'raises WalletError (code 5) for 400 isError with code 5' do
      body = { 'isError' => true, 'code' => 5, 'message' => 'review required' }
      stub_http(stub_response(body, code: '400'))

      error = nil
      begin
        substrate.create_action({ description: 'test' })
      rescue BSV::Wallet::WalletError => e
        error = e
      end

      expect(error).not_to be_nil
      expect(error.code).to eq(5)
    end

    it 'raises InvalidParameterError for 400 isError with code 6' do
      body = { 'isError' => true, 'code' => 6, 'parameter' => 'description', 'message' => 'bad param' }
      stub_http(stub_response(body, code: '400'))

      expect { substrate.create_action({ description: '' }) }.to raise_error(
        BSV::Wallet::InvalidParameterError
      )
    end

    it 'raises InsufficientFundsError for 400 isError with code 7' do
      body = { 'isError' => true, 'code' => 7, 'message' => 'not enough satoshis' }
      stub_http(stub_response(body, code: '400'))

      expect { substrate.create_action({ description: 'pay' }) }.to raise_error(
        BSV::Wallet::InsufficientFundsError
      )
    end

    it 'raises plain WalletError for 400 isError with unrecognised code' do
      body = { 'isError' => true, 'code' => 99, 'message' => 'unknown error' }
      stub_http(stub_response(body, code: '400'))

      expect { substrate.get_height({}) }.to raise_error(
        BSV::Wallet::WalletError, 'unknown error'
      )
    end
  end

  # -------------------------------------------------------------------------
  # Injectable http_client
  # -------------------------------------------------------------------------

  describe 'http_client injection' do
    it 'uses the injected client instead of Net::HTTP when provided' do
      fake_response = stub_response({ 'height' => 999 })
      fake_client = double('http_client') # rubocop:disable RSpec/VerifiedDoubles
      allow(fake_client).to receive(:post).and_return(fake_response)
      allow(Net::HTTP).to receive(:start).and_call_original

      s = described_class.new(base_url, http_client: fake_client)

      result = s.get_height({})

      expect(result).to eq({ height: 999 })
      expect(fake_client).to have_received(:post)
      expect(Net::HTTP).not_to have_received(:start)
    end
  end

  # -------------------------------------------------------------------------
  # Uses HTTPS when base_url scheme is https
  # -------------------------------------------------------------------------

  describe 'HTTPS support' do
    it 'enables SSL when base_url uses https' do
      s = described_class.new('https://secure.example.com')

      allow(Net::HTTP).to receive(:start)
        .with('secure.example.com', 443, use_ssl: true)
        .and_yield(stub_http_session(stub_response({})))

      s.get_height({})

      expect(Net::HTTP).to have_received(:start)
        .with('secure.example.com', 443, use_ssl: true)
    end
  end
end
