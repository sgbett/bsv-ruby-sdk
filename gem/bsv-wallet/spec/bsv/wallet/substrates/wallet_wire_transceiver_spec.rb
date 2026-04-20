# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe 'BSV::Wallet::Substrates::WalletWireTransceiver' do
  subject(:transceiver) { BSV::Wallet::Substrates::WalletWireTransceiver.new(wire, originator: constructor_originator) }

  let(:constructor_originator) { nil }
  let(:transmitted_frames)     { [] }
  let(:response_bytes)         { [] }

  # A simple mock wire that captures frames and returns configured response bytes.
  let(:wire) do
    frames = transmitted_frames
    resp = response_bytes
    double('wire').tap do |w| # rubocop:disable RSpec/VerifiedDoubles
      allow(w).to receive(:transmit_to_wallet) do |frame|
        frames << frame
        resp.dup
      end
    end
  end

  # Builds a serialised success response for a given method and result hash.
  def success_response_bytes(method_name, result)
    BSV::Wallet::Wire::Serializer.serialize_response(method_name, result).bytes.to_a
  end

  # Builds a serialised error response frame.
  def error_response_bytes(code, message, stack_trace: '')
    BSV::Wallet::Wire::Serializer.serialize_error(code, message, stack_trace: stack_trace).bytes.to_a
  end

  # Builds the expected request frame for verification purposes.
  def expected_request_frame(method_name, args, orig = nil)
    BSV::Wallet::Wire::Serializer.serialize_request(method_name, args, originator: orig.to_s).bytes.to_a
  end

  describe 'constructor' do
    it 'stores the wire transport' do
      expect(transceiver.instance_variable_get(:@wire)).to eq(wire)
    end

    it 'stores the originator' do
      transceiver_with_orig = BSV::Wallet::Substrates::WalletWireTransceiver.new(wire, originator: 'app.example.com')
      expect(transceiver_with_orig.instance_variable_get(:@originator)).to eq('app.example.com')
    end

    it 'defaults originator to nil' do
      expect(transceiver.instance_variable_get(:@originator)).to be_nil
    end
  end

  describe 'implements BSV::Wallet::Interface::BRC100' do
    it 'includes BSV::Wallet::Interface::BRC100' do
      expect(BSV::Wallet::Substrates::WalletWireTransceiver).to include(BSV::Wallet::Interface::BRC100)
    end

    it 'implements all 28 Interface methods' do
      methods = %i[
        create_action sign_action abort_action list_actions internalize_action
        list_outputs relinquish_output get_public_key reveal_counterparty_key_linkage
        reveal_specific_key_linkage encrypt decrypt create_hmac verify_hmac
        create_signature verify_signature acquire_certificate list_certificates
        prove_certificate relinquish_certificate discover_by_identity_key
        discover_by_attributes is_authenticated wait_for_authentication
        get_height get_header_for_height get_network get_version
      ]
      methods.each do |method|
        expect(transceiver).to respond_to(method), "expected transceiver to respond to ##{method}"
      end
    end
  end

  describe '#get_version' do
    let(:result) { { version: '0.1.0' } }

    before { response_bytes.replace(success_response_bytes(:get_version, result)) }

    it 'serialises the request and passes it to wire.transmit_to_wallet' do
      transceiver.get_version
      expect(transmitted_frames.length).to eq(1)
      expect(transmitted_frames.first).to eq(expected_request_frame(:get_version, {}))
    end

    it 'deserialises the response and returns a Hash' do
      returned = transceiver.get_version
      expect(returned).to eq(result)
    end
  end

  describe '#get_public_key' do
    let(:args)   { { identity_key: true } }
    let(:result) { { public_key: "02#{'ab' * 32}" } }

    before { response_bytes.replace(success_response_bytes(:get_public_key, result)) }

    it 'serialises the correct call code and args into the frame' do
      transceiver.get_public_key(args)
      expect(transmitted_frames.first).to eq(expected_request_frame(:get_public_key, args))
    end

    it 'returns the deserialised public_key' do
      returned = transceiver.get_public_key(args)
      expect(returned[:public_key]).to eq(result[:public_key])
    end
  end

  describe 'originator handling' do
    let(:result) { { version: '0.1.0' } }

    before { response_bytes.replace(success_response_bytes(:get_version, result)) }

    context 'when a constructor originator is set' do
      let(:constructor_originator) { 'constructor.example.com' }

      it 'embeds the constructor originator in the frame' do
        transceiver.get_version
        expected = expected_request_frame(:get_version, {}, 'constructor.example.com')
        expect(transmitted_frames.first).to eq(expected)
      end
    end

    context 'when a method-level originator is provided' do
      let(:constructor_originator) { 'constructor.example.com' }

      it 'uses the method-level originator instead of the constructor originator' do
        transceiver.get_version(originator: 'method.example.com')
        expected = expected_request_frame(:get_version, {}, 'method.example.com')
        expect(transmitted_frames.first).to eq(expected)
      end
    end

    context 'when neither originator is set' do
      it 'uses an empty originator string in the frame' do
        transceiver.get_version
        expected = expected_request_frame(:get_version, {}, '')
        expect(transmitted_frames.first).to eq(expected)
      end
    end
  end

  describe 'error handling' do
    context 'when the response has a non-zero error byte' do
      before { response_bytes.replace(error_response_bytes(42, 'Something went wrong')) }

      it 'raises WalletError with the error message' do
        expect { transceiver.get_version }.to raise_error(BSV::Wallet::WalletError, 'Something went wrong')
      end

      it 'includes the error code on the raised exception' do
        transceiver.get_version
      rescue BSV::Wallet::WalletError => e
        expect(e.code).to eq(42)
      end
    end
  end

  describe 'wire transport propagation' do
    it 'passes the frame as an Array of Integers to transmit_to_wallet' do
      response_bytes.replace(success_response_bytes(:get_version, { version: '0.1.0' }))
      transceiver.get_version
      frame = transmitted_frames.first
      expect(frame).to be_an(Array)
      expect(frame).to all(be_an(Integer).and(be_between(0, 255)))
    end

    it 'propagates exceptions raised by the wire transport' do
      allow(wire).to receive(:transmit_to_wallet).and_raise(RuntimeError, 'connection refused')
      expect { transceiver.get_version }.to raise_error(RuntimeError, 'connection refused')
    end
  end

  describe 'all 28 methods route through transmit' do
    # For each zero-arg method (args default to {}), verify the call code in the frame.
    {
      create_action: { args: { description: 'Test', outputs: [] }, result: { txid: 'aa' * 32, tx: [], no_send_change: [] } },
      get_height: { args: {}, result: { height: 800_000 } },
      get_network: { args: {}, result: { network: 'mainnet' } },
      get_version: { args: {}, result: { version: '0.1.0' } },
      is_authenticated: { args: {}, result: { authenticated: true } }
    }.each do |method_name, config|
      it "routes ##{method_name} through wire.transmit_to_wallet with the correct call code" do
        response_bytes.replace(success_response_bytes(method_name, config[:result]))
        expected_code = BSV::Wallet::Wire::Serializer::CALL_CODES[method_name]
        transceiver.public_send(method_name, config[:args])
        expect(transmitted_frames.last.first).to eq(expected_code)
      end
    end
  end

  describe 'integration with HTTPWalletWire' do
    # Verifies that WalletWireTransceiver composes correctly with HTTPWalletWire,
    # using an injected http_client to avoid real network calls.
    let(:http_responses) { [] }
    let(:http_client) do
      resps = http_responses
      proc do |_uri, _body, _originator|
        resps.shift || ''
      end
    end
    let(:http_wire)   { BSV::Wallet::Substrates::HTTPWalletWire.new('http://localhost:3301', http_client: http_client) }
    let(:integrated)  { BSV::Wallet::Substrates::WalletWireTransceiver.new(http_wire, originator: 'test.example.com') }

    it 'delegates get_version through HTTPWalletWire to the mocked HTTP client' do
      http_responses << BSV::Wallet::Wire::Serializer.serialize_response(:get_version, { version: '1.2.3' })
      result = integrated.get_version
      expect(result[:version]).to eq('1.2.3')
    end

    it 'raises WalletError when the HTTP server returns an error response' do
      http_responses << BSV::Wallet::Wire::Serializer.serialize_error(1, 'not authenticated')
      expect { integrated.is_authenticated }.to raise_error(BSV::Wallet::WalletError, 'not authenticated')
    end
  end
end
