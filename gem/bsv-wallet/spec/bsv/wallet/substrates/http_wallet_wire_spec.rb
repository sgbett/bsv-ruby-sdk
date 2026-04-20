# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::Substrates::HTTPWalletWire do
  subject(:wire) { described_class.new(base_url, http_client: http_client) }

  let(:base_url)    { 'http://localhost:3301' }
  let(:http_client) { nil }
  let(:captured)    { {} }

  # Builds a minimal wire frame: [call_code, orig_len, *orig_bytes, *payload]
  def frame(call_code, originator_str = '', *payload_bytes)
    orig_bytes = originator_str.encode('UTF-8').bytes
    [call_code, orig_bytes.length] + orig_bytes + payload_bytes
  end

  # Stubs Net::HTTP to capture the outgoing request and return fixed response bytes.
  def stub_http(response_body_bytes, capture_into: captured)
    fake_response = instance_double(Net::HTTPOK, code: '200', body: response_body_bytes.pack('C*'))
    allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

    fake_http = instance_double(Net::HTTP)
    allow(fake_http).to receive(:request) do |req|
      capture_into[:request] = req
      fake_response
    end

    allow(Net::HTTP).to receive(:start).and_yield(fake_http)
  end

  describe '#transmit_to_wallet' do
    context 'with a valid get_version frame (call code 28)' do
      let(:message) { frame(28) }

      before { stub_http([0]) }

      it 'POSTs to /getVersion' do
        wire.transmit_to_wallet(message)
        expect(captured[:request].path).to eq('/getVersion')
      end

      it 'sets Content-Type to application/octet-stream' do
        wire.transmit_to_wallet(message)
        expect(captured[:request]['Content-Type']).to eq('application/octet-stream')
      end

      it 'returns the response body as a byte array' do
        result = wire.transmit_to_wallet(message)
        expect(result).to eq([0])
      end
    end

    context 'with a create_action frame (call code 1)' do
      let(:message) { frame(1) }

      before { stub_http([0, 1, 2]) }

      it 'POSTs to /createAction' do
        wire.transmit_to_wallet(message)
        expect(captured[:request].path).to eq('/createAction')
      end

      it 'returns response bytes as an Array of integers' do
        result = wire.transmit_to_wallet(message)
        expect(result).to eq([0, 1, 2])
        expect(result).to all(be_an(Integer))
      end
    end

    context 'when mapping all 28 call codes to URL paths' do
      let(:expected_paths) do
        {
          1 => '/createAction',
          2 => '/signAction',
          3 => '/abortAction',
          4 => '/listActions',
          5 => '/internalizeAction',
          6 => '/listOutputs',
          7 => '/relinquishOutput',
          8 => '/getPublicKey',
          9 => '/revealCounterpartyKeyLinkage',
          10 => '/revealSpecificKeyLinkage',
          11 => '/encrypt',
          12 => '/decrypt',
          13 => '/createHMAC',
          14 => '/verifyHMAC',
          15 => '/createSignature',
          16 => '/verifySignature',
          17 => '/acquireCertificate',
          18 => '/listCertificates',
          19 => '/proveCertificate',
          20 => '/relinquishCertificate',
          21 => '/discoverByIdentityKey',
          22 => '/discoverByAttributes',
          23 => '/isAuthenticated',
          24 => '/waitForAuthentication',
          25 => '/getHeight',
          26 => '/getHeaderForHeight',
          27 => '/getNetwork',
          28 => '/getVersion'
        }
      end

      it 'maps every call code to the correct camelCase URL path' do
        expected_paths.each do |code, path|
          local = {}
          stub_http([0], capture_into: local)
          wire.transmit_to_wallet(frame(code))
          expect(local[:request].path).to eq(path), "expected call code #{code} to map to #{path}"
        end
      end
    end

    context 'with an originator in the message header' do
      let(:message) { frame(28, 'wallet.example.com') }

      before { stub_http([0]) }

      it 'sends the originator as the Origin header' do
        wire.transmit_to_wallet(message)
        expect(captured[:request]['Origin']).to eq('wallet.example.com')
      end
    end

    context 'with a zero-length originator' do
      let(:message) { frame(28, '') }

      before { stub_http([0]) }

      it 'does not send an Origin header' do
        wire.transmit_to_wallet(message)
        expect(captured[:request]['Origin']).to be_nil
      end
    end

    context 'with payload bytes after the header' do
      let(:payload) { [0xDE, 0xAD, 0xBE, 0xEF] }
      let(:message) { frame(28, '', *payload) }

      before { stub_http([0]) }

      it 'sends the payload bytes as the request body' do
        wire.transmit_to_wallet(message)
        expect(captured[:request].body.bytes).to eq(payload)
      end
    end

    context 'with no payload bytes (header only)' do
      let(:message) { frame(28) }

      before { stub_http([0]) }

      it 'sends an empty body' do
        wire.transmit_to_wallet(message)
        expect(captured[:request].body).to eq('')
      end
    end

    context 'with an injectable http_client' do
      let(:calls) { [] }
      let(:http_client) do
        proc do |uri, body, originator|
          calls << { uri: uri, body: body, originator: originator }
          "\x00"
        end
      end

      it 'delegates to the injected http_client' do
        wire.transmit_to_wallet(frame(28, 'app.example.com'))
        expect(calls.length).to eq(1)
        expect(calls.first[:uri].to_s).to eq('http://localhost:3301/getVersion')
        expect(calls.first[:originator]).to eq('app.example.com')
      end

      it 'returns the client response as byte array' do
        result = wire.transmit_to_wallet(frame(28))
        expect(result).to eq([0])
      end
    end

    context 'when handling errors' do
      it 'raises ArgumentError for an empty message' do
        expect { wire.transmit_to_wallet([]) }.to raise_error(ArgumentError, /empty/)
      end

      it 'raises ArgumentError for nil message' do
        expect { wire.transmit_to_wallet(nil) }.to raise_error(ArgumentError, /empty/)
      end

      it 'raises ArgumentError for call code 0 (unknown)' do
        expect { wire.transmit_to_wallet(frame(0)) }.to raise_error(ArgumentError, /unknown call code: 0/)
      end

      it 'raises ArgumentError for call code 255 (unknown)' do
        expect { wire.transmit_to_wallet(frame(255)) }.to raise_error(ArgumentError, /unknown call code: 255/)
      end

      it 'raises RuntimeError for a non-2xx HTTP response' do
        fake_response = instance_double(Net::HTTPNotFound, code: '404', body: 'Not Found')
        allow(fake_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        fake_http = instance_double(Net::HTTP)
        allow(fake_http).to receive(:request).and_return(fake_response)
        allow(Net::HTTP).to receive(:start).and_yield(fake_http)

        expect { wire.transmit_to_wallet(frame(28)) }.to raise_error(RuntimeError, /HTTP 404/)
      end
    end
  end
end
