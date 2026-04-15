# frozen_string_literal: true

# rubocop:disable RSpec/DescribeClass
require 'spec_helper'
require 'base64'
require 'json'

# A real, valid compressed public key for private key scalar=99.
# Using a real key avoids "invalid point" errors when PublicKey.from_hex is called.
AUTH_FETCH_PAYMENT_VALID_PUB_KEY = '02e22fbe15c0af8ccc5780c0735f84dbe9a790badee8245c06c7ca37331cb36980'

RSpec.describe 'BSV::Auth::AuthFetch — 402 payment handling' do
  let(:server_pub_key)    { AUTH_FETCH_PAYMENT_VALID_PUB_KEY }
  let(:derivation_prefix) { 'test-prefix-abc' }
  let(:canned_tx_bytes)   { [1, 2, 3, 4, 5, 6, 7, 8] }
  let(:canned_tx_base64)  { Base64.strict_encode64(canned_tx_bytes.pack('C*')) }

  # -------------------------------------------------------------------------
  # Mock wallet
  # -------------------------------------------------------------------------
  #
  # Supports create_action and get_public_key so the full payment flow runs.
  # Returns a valid secp256k1 public key so PublicKey.from_hex succeeds.

  let(:mock_wallet) do
    wallet = double('wallet') # rubocop:disable RSpec/VerifiedDoubles
    allow(wallet).to receive_messages(get_public_key: { public_key: AUTH_FETCH_PAYMENT_VALID_PUB_KEY }, create_action: { txid: 'deadbeef', tx: canned_tx_bytes }, create_hmac: { hmac: Array.new(32, 0) })
    wallet
  end

  # -------------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------------

  # Builds a valid serialised AuthFetch response that can be injected via
  # +fire_callbacks(:general_message, ...)+ on the Peer instance.
  def build_auth_response(request_nonce, status:, headers: [], body: '')
    BSV::Auth::AuthPayload.serialize_response(
      request_id: request_nonce,
      status: status,
      headers: headers,
      body: body
    )
  end

  # Returns a hash of valid 402 payment headers.
  def valid_402_headers(prefix: derivation_prefix, satoshis: '1000', version: '1.0')
    {
      BSV::Auth::AuthHeaders::PAYMENT_VERSION => version,
      BSV::Auth::AuthHeaders::PAYMENT_SATOSHIS_REQUIRED => satoshis,
      BSV::Auth::AuthHeaders::IDENTITY_KEY => server_pub_key,
      BSV::Auth::AuthHeaders::PAYMENT_DERIVATION_PREFIX => prefix
    }
  end

  # Stubs Peer#to_peer so that:
  # 1. On the first call it fires a 402 response via the general_message callback
  # 2. On the second call it fires a 200 response
  def stub_peer_402_then_200(_client, _url)
    call_count = 0
    nonce_first  = nil
    nonce_second = nil

    allow(BSV::Auth::AuthPayload).to receive(:serialize_request).and_wrap_original do |orig, **kwargs|
      if call_count == 0
        nonce_first = kwargs[:request_nonce]
      else
        nonce_second = kwargs[:request_nonce]
      end
      orig.call(**kwargs)
    end

    allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) do |peer, _payload| # rubocop:disable RSpec/AnyInstance
      call_count += 1
      response_binary = if call_count == 1
                          build_auth_response(
                            nonce_first,
                            status: 402,
                            headers: valid_402_headers.to_a,
                            body: 'payment required'
                          )
                        else
                          build_auth_response(
                            nonce_second || nonce_first,
                            status: 200,
                            body: 'paid!'
                          )
                        end
      peer.send(:fire_callbacks, :general_message, server_pub_key, response_binary.bytes)
    end
  end

  # -------------------------------------------------------------------------
  # Tests
  # -------------------------------------------------------------------------

  describe '402 with valid payment headers — triggers payment flow and retries' do
    it 'calls create_action and retries with x-bsv-payment header, returning 200' do
      client = BSV::Auth::AuthFetch.new(wallet: mock_wallet)
      stub_peer_402_then_200(client, 'https://api.example.com/resource')

      payment_header_sent = nil
      allow(BSV::Auth::AuthHeaders).to receive(:filter_request_headers).and_wrap_original do |orig, hdrs|
        payment_header_sent = hdrs[BSV::Auth::AuthHeaders::PAYMENT] if hdrs.key?(BSV::Auth::AuthHeaders::PAYMENT)
        orig.call(hdrs)
      end

      response = client.fetch('https://api.example.com/resource')

      expect(response.status).to eq(200)
      expect(response.body).to eq('paid!')
      expect(mock_wallet).to have_received(:create_action).once
      expect(payment_header_sent).not_to be_nil
    end

    it 'encodes the payment header as JSON with camelCase keys' do
      client = BSV::Auth::AuthFetch.new(wallet: mock_wallet)
      stub_peer_402_then_200(client, 'https://api.example.com/resource')

      payment_json = nil
      allow(BSV::Auth::AuthHeaders).to receive(:filter_request_headers).and_wrap_original do |orig, hdrs|
        payment_json = hdrs[BSV::Auth::AuthHeaders::PAYMENT]
        orig.call(hdrs)
      end

      client.fetch('https://api.example.com/resource')

      parsed = JSON.parse(payment_json)
      expect(parsed).to have_key('derivationPrefix')
      expect(parsed).to have_key('derivationSuffix')
      expect(parsed).to have_key('transaction')
      expect(parsed['transaction']).to eq(canned_tx_base64)
    end

    it 'includes the correct derivation prefix from the 402 response' do
      client = BSV::Auth::AuthFetch.new(wallet: mock_wallet)
      stub_peer_402_then_200(client, 'https://api.example.com/resource')

      payment_json = nil
      allow(BSV::Auth::AuthHeaders).to receive(:filter_request_headers).and_wrap_original do |orig, hdrs|
        payment_json = hdrs[BSV::Auth::AuthHeaders::PAYMENT]
        orig.call(hdrs)
      end

      client.fetch('https://api.example.com/resource')

      parsed = JSON.parse(payment_json)
      expect(parsed['derivationPrefix']).to eq(derivation_prefix)
    end
  end

  describe '402 with missing x-bsv-payment-version — raises AuthError' do
    it 'raises AuthError mentioning the missing header' do
      client = BSV::Auth::AuthFetch.new(wallet: mock_wallet)
      bad_headers = valid_402_headers.reject { |k, _| k == BSV::Auth::AuthHeaders::PAYMENT_VERSION }

      nonce_ref = nil
      allow(BSV::Auth::AuthPayload).to receive(:serialize_request).and_wrap_original do |orig, **kwargs|
        nonce_ref = kwargs[:request_nonce]
        orig.call(**kwargs)
      end

      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) do |peer, _payload| # rubocop:disable RSpec/AnyInstance
        binary = build_auth_response(nonce_ref, status: 402, headers: bad_headers.to_a)
        peer.send(:fire_callbacks, :general_message, server_pub_key, binary.bytes)
      end

      expect do
        client.fetch('https://api.example.com/resource')
      end.to raise_error(BSV::Auth::AuthError, /x-bsv-payment-version/)
    end
  end

  describe '402 with mismatched payment version — raises AuthError' do
    it 'raises AuthError mentioning unsupported version' do
      client = BSV::Auth::AuthFetch.new(wallet: mock_wallet)
      bad_headers = valid_402_headers(version: '2.0')

      nonce_ref = nil
      allow(BSV::Auth::AuthPayload).to receive(:serialize_request).and_wrap_original do |orig, **kwargs|
        nonce_ref = kwargs[:request_nonce]
        orig.call(**kwargs)
      end

      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) do |peer, _payload| # rubocop:disable RSpec/AnyInstance
        binary = build_auth_response(nonce_ref, status: 402, headers: bad_headers.to_a)
        peer.send(:fire_callbacks, :general_message, server_pub_key, binary.bytes)
      end

      expect do
        client.fetch('https://api.example.com/resource')
      end.to raise_error(BSV::Auth::AuthError, /Unsupported/)
    end
  end

  describe '402 with invalid satoshis — raises AuthError' do
    [['0', 'zero'], ['-5', 'negative'], ['not-a-number', 'non-numeric']].each do |satoshis, label|
      it "raises AuthError for #{label} satoshis (#{satoshis.inspect})" do
        client = BSV::Auth::AuthFetch.new(wallet: mock_wallet)
        bad_headers = valid_402_headers(satoshis: satoshis)

        nonce_ref = nil
        allow(BSV::Auth::AuthPayload).to receive(:serialize_request).and_wrap_original do |orig, **kwargs|
          nonce_ref = kwargs[:request_nonce]
          orig.call(**kwargs)
        end

        allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) do |peer, _payload| # rubocop:disable RSpec/AnyInstance
          binary = build_auth_response(nonce_ref, status: 402, headers: bad_headers.to_a)
          peer.send(:fire_callbacks, :general_message, server_pub_key, binary.bytes)
        end

        expect do
          client.fetch('https://api.example.com/resource')
        end.to raise_error(BSV::Auth::AuthError, /satoshis/)
      end
    end
  end

  describe '402 with missing derivation prefix — raises AuthError' do
    it 'raises AuthError mentioning the missing header' do
      client = BSV::Auth::AuthFetch.new(wallet: mock_wallet)
      bad_headers = valid_402_headers.reject { |k, _| k == BSV::Auth::AuthHeaders::PAYMENT_DERIVATION_PREFIX }

      nonce_ref = nil
      allow(BSV::Auth::AuthPayload).to receive(:serialize_request).and_wrap_original do |orig, **kwargs|
        nonce_ref = kwargs[:request_nonce]
        orig.call(**kwargs)
      end

      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) do |peer, _payload| # rubocop:disable RSpec/AnyInstance
        binary = build_auth_response(nonce_ref, status: 402, headers: bad_headers.to_a)
        peer.send(:fire_callbacks, :general_message, server_pub_key, binary.bytes)
      end

      expect do
        client.fetch('https://api.example.com/resource')
      end.to raise_error(BSV::Auth::AuthError, /x-bsv-payment-derivation-prefix/)
    end
  end

  describe '402 with wallet that lacks create_action — raises AuthError' do
    it 'raises a clear error describing the missing capability' do
      limited_wallet = double('limited_wallet') # rubocop:disable RSpec/VerifiedDoubles
      allow(limited_wallet).to receive(:respond_to?).with(:get_public_key).and_return(false)
      allow(limited_wallet).to receive(:respond_to?).with(:create_action).and_return(false)

      client = BSV::Auth::AuthFetch.new(wallet: limited_wallet)

      nonce_ref = nil
      allow(BSV::Auth::AuthPayload).to receive(:serialize_request).and_wrap_original do |orig, **kwargs|
        nonce_ref = kwargs[:request_nonce]
        orig.call(**kwargs)
      end

      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) do |peer, _payload| # rubocop:disable RSpec/AnyInstance
        binary = build_auth_response(nonce_ref, status: 402, headers: valid_402_headers.to_a)
        peer.send(:fire_callbacks, :general_message, server_pub_key, binary.bytes)
      end

      expect do
        client.fetch('https://api.example.com/resource')
      end.to raise_error(BSV::Auth::AuthError, /create_action and get_public_key/)
    end
  end

  describe 'max retries exhausted — raises AuthError' do
    it 'raises AuthError after exceeding payment_max_retries' do
      client = BSV::Auth::AuthFetch.new(wallet: mock_wallet, payment_max_retries: 2)

      nonces = []
      allow(BSV::Auth::AuthPayload).to receive(:serialize_request).and_wrap_original do |orig, **kwargs|
        nonces << kwargs[:request_nonce]
        orig.call(**kwargs)
      end

      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) do |peer, _| # rubocop:disable RSpec/AnyInstance
        nonce = nonces.last
        binary = build_auth_response(nonce, status: 402, headers: valid_402_headers.to_a)
        peer.send(:fire_callbacks, :general_message, server_pub_key, binary.bytes)
      end

      expect do
        client.fetch('https://api.example.com/resource')
      end.to raise_error(BSV::Auth::AuthError, /failed after 2 attempt/)
    end
  end

  describe 'requirements change between 402 responses — regenerates payment' do
    it 'calls create_action twice when satoshis change' do
      client = BSV::Auth::AuthFetch.new(wallet: mock_wallet, payment_max_retries: 3)

      nonces = []
      allow(BSV::Auth::AuthPayload).to receive(:serialize_request).and_wrap_original do |orig, **kwargs|
        nonces << kwargs[:request_nonce]
        orig.call(**kwargs)
      end

      call_count = 0
      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) do |peer, _| # rubocop:disable RSpec/AnyInstance
        call_count += 1
        nonce = nonces.last
        if call_count == 1
          # First response: 402 with 1000 satoshis
          hdrs = valid_402_headers(satoshis: '1000')
          binary = build_auth_response(nonce, status: 402, headers: hdrs.to_a)
        elsif call_count == 2
          # Second response: 402 with different satoshis (requirements changed)
          hdrs = valid_402_headers(satoshis: '2000')
          binary = build_auth_response(nonce, status: 402, headers: hdrs.to_a)
        else
          # Third response: 200 success
          binary = build_auth_response(nonce, status: 200, body: 'ok')
        end
        peer.send(:fire_callbacks, :general_message, server_pub_key, binary.bytes)
      end

      response = client.fetch('https://api.example.com/resource')
      expect(response.status).to eq(200)
      expect(mock_wallet).to have_received(:create_action).twice
    end
  end

  describe 'payment context reuse — same requirements between retries' do
    it 'calls create_action only once when requirements stay the same' do
      client = BSV::Auth::AuthFetch.new(wallet: mock_wallet, payment_max_retries: 3)

      nonces = []
      allow(BSV::Auth::AuthPayload).to receive(:serialize_request).and_wrap_original do |orig, **kwargs|
        nonces << kwargs[:request_nonce]
        orig.call(**kwargs)
      end

      call_count = 0
      allow_any_instance_of(BSV::Auth::Peer).to receive(:to_peer) do |peer, _| # rubocop:disable RSpec/AnyInstance
        call_count += 1
        nonce = nonces.last
        binary = if call_count <= 2
                   # Same requirements both times
                   build_auth_response(nonce, status: 402, headers: valid_402_headers.to_a)
                 else
                   build_auth_response(nonce, status: 200, body: 'ok')
                 end
        peer.send(:fire_callbacks, :general_message, server_pub_key, binary.bytes)
      end

      response = client.fetch('https://api.example.com/resource')
      expect(response.status).to eq(200)
      expect(mock_wallet).to have_received(:create_action).once
    end
  end

  describe 'constructor — payment_max_retries parameter' do
    it 'accepts payment_max_retries keyword' do
      expect do
        BSV::Auth::AuthFetch.new(wallet: mock_wallet, payment_max_retries: 5)
      end.not_to raise_error
    end

    it 'defaults to 3 retries' do
      client = BSV::Auth::AuthFetch.new(wallet: mock_wallet)
      expect(client.instance_variable_get(:@payment_max_retries)).to eq(3)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
