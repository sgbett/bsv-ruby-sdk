# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Auth::Peer do
  let(:alice_key)    { BSV::Primitives::PrivateKey.generate }
  let(:bob_key)      { BSV::Primitives::PrivateKey.generate }
  let(:alice_wallet) { BSV::Wallet::ProtoWallet.new(alice_key) }
  let(:bob_wallet)   { BSV::Wallet::ProtoWallet.new(bob_key) }
  let(:alice)        { described_class.new(wallet: alice_wallet) }
  let(:bob)          { described_class.new(wallet: bob_wallet) }

  # Performs the full three-step handshake and returns [request, response].
  def perform_handshake(initiator, responder)
    request  = initiator.create_initial_request
    response = responder.handle_incoming_message(request)
    initiator.handle_incoming_message(response)
    [request, response]
  end

  describe '#identity_key' do
    it 'returns the compressed public key hex for the wallet' do
      expect(alice.identity_key).to eq(alice_key.public_key.to_hex)
    end

    it 'returns a 66-character hex string (compressed pubkey)' do
      expect(alice.identity_key.length).to eq(66)
    end

    it 'returns a consistent value on repeated calls' do
      first_call  = alice.identity_key
      second_call = alice.identity_key
      expect(first_call).to eq(second_call)
    end

    it 'returns different keys for different wallets' do
      expect(alice.identity_key).not_to eq(bob.identity_key)
    end
  end

  describe '#create_initial_request' do
    subject(:request) { alice.create_initial_request }

    it 'returns a hash with the expected keys' do
      expect(request).to include(
        version: BSV::Auth::AUTH_VERSION,
        message_type: BSV::Auth::MSG_INITIAL_REQUEST,
        identity_key: alice.identity_key
      )
    end

    it 'includes a non-empty initial_nonce' do
      expect(request[:initial_nonce]).to be_a(String)
      expect(request[:initial_nonce]).not_to be_empty
    end

    it 'creates a pending session in the session manager' do
      nonce = request[:initial_nonce]
      expect(alice.session_manager.session?(nonce)).to be(true)
    end

    it 'generates a unique nonce on each call' do
      second_request = alice.create_initial_request
      expect(request[:initial_nonce]).not_to eq(second_request[:initial_nonce])
    end
  end

  describe '#handle_incoming_message — full handshake round-trip' do
    it 'authenticates Alice after processing the initial response' do
      request  = alice.create_initial_request
      response = bob.handle_incoming_message(request)
      alice.handle_incoming_message(response)

      expect(alice.authenticated?(request[:initial_nonce])).to be(true)
    end

    it 'authenticates Bob after processing the initial request' do
      request  = alice.create_initial_request
      response = bob.handle_incoming_message(request)
      alice.handle_incoming_message(response)

      # Bob's session is indexed by his own nonce (from the response)
      expect(bob.authenticated?(response[:initial_nonce])).to be(true)
    end

    it 'returns nil when Alice processes the initial response (no further reply needed)' do
      request  = alice.create_initial_request
      response = bob.handle_incoming_message(request)
      result   = alice.handle_incoming_message(response)

      expect(result).to be_nil
    end

    it "includes Bob's identity key in the initial response" do
      request  = alice.create_initial_request
      response = bob.handle_incoming_message(request)

      expect(response[:identity_key]).to eq(bob.identity_key)
    end

    it "echoes Alice's nonce back in the response" do
      request  = alice.create_initial_request
      response = bob.handle_incoming_message(request)

      expect(response[:your_nonce]).to eq(request[:initial_nonce])
    end
  end

  describe '#handle_incoming_message — version and type guards' do
    it 'raises AuthError when the version is wrong' do
      bad_msg = { version: '9.9', message_type: BSV::Auth::MSG_INITIAL_REQUEST }
      expect { alice.handle_incoming_message(bad_msg) }.to raise_error(BSV::Auth::AuthError, /Unsupported auth version/)
    end

    it 'raises AuthError for an unknown message type' do
      bad_msg = { version: BSV::Auth::AUTH_VERSION, message_type: 'mystery' }
      expect { alice.handle_incoming_message(bad_msg) }.to raise_error(BSV::Auth::AuthError, /Unknown message type/)
    end
  end

  describe '#create_general_message / #handle_incoming_message (general)' do
    let(:payload) { [72, 101, 108, 108, 111] } # "Hello"

    # Perform handshake and expose Alice's session nonce for use in examples.
    let(:alice_session_nonce) do
      perform_handshake(alice, bob)
      alice.session_manager.instance_variable_get(:@by_nonce).keys.first
    end

    it 'can create a general message after authentication' do
      msg = alice.create_general_message(alice_session_nonce, payload)
      expect(msg[:message_type]).to eq(BSV::Auth::MSG_GENERAL)
    end

    it 'Bob can verify and read the payload sent by Alice' do
      msg    = alice.create_general_message(alice_session_nonce, payload)
      result = bob.handle_incoming_message(msg)

      expect(result[:payload]).to eq(payload)
      expect(result[:peer_identity_key]).to eq(alice.identity_key)
    end
  end

  describe '#create_general_message — raises without auth' do
    it 'raises AuthError when no session exists for the identifier' do
      expect do
        alice.create_general_message('no-such-nonce', [1, 2, 3])
      end.to raise_error(BSV::Auth::AuthError, /Not authenticated/)
    end
  end

  describe '#handle_incoming_message — tampered initial response' do
    it 'raises AuthError when the signature has been tampered with' do
      request = alice.create_initial_request
      response = bob.handle_incoming_message(request)

      # Flip the last byte of the signature to invalidate it
      bad_sig = response[:signature].dup
      bad_sig[-1] ^= 0xFF
      tampered = response.merge(signature: bad_sig)

      expect { alice.handle_incoming_message(tampered) }
        .to raise_error(BSV::Auth::AuthError, /signature verification failed/)
    end

    it 'removes the pending session after a failed signature verification' do
      request = alice.create_initial_request
      our_nonce = request[:initial_nonce]

      response = bob.handle_incoming_message(request)
      bad_sig  = response[:signature].dup
      bad_sig[-1] ^= 0xFF
      tampered = response.merge(signature: bad_sig)

      begin
        alice.handle_incoming_message(tampered)
      rescue BSV::Auth::AuthError
        nil
      end

      expect(alice.session_manager.get_session(our_nonce)).to be_nil
    end
  end
end
