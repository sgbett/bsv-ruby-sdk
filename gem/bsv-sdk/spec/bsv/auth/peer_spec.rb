# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Auth::Peer do
  let(:alice_key)    { BSV::Primitives::PrivateKey.generate }
  let(:bob_key)      { BSV::Primitives::PrivateKey.generate }
  let(:alice_wallet) { BSV::Wallet::ProtoWallet.new(alice_key) }
  let(:bob_wallet)   { BSV::Wallet::ProtoWallet.new(bob_key) }

  # Create two peers connected via PairedTransport.
  let(:transport_a)  { PairedTransport.new }
  let(:transport_b)  { PairedTransport.new }
  let(:alice) { described_class.new(wallet: alice_wallet, transport: transport_a) }
  let(:bob)   { described_class.new(wallet: bob_wallet,   transport: transport_b) }

  before do
    # Force both peers to be created (registering their on_data callbacks) and
    # wire the transports together before any message is delivered.
    # RSpec `let` is lazy — without these references, a peer's on_data would not
    # be registered before the first transport.send call, causing silent message drops.
    alice
    bob
    transport_a.partner = transport_b
    transport_b.partner = transport_a
  end

  # Performs the full three-step handshake via transport and returns [request, response].
  # The handshake is transport-mediated: alice sends the request via transport_a, which
  # delivers it to bob; bob's on_data triggers handle_incoming_message, which sends the
  # response back via transport_b; alice's on_data completes the handshake.
  def perform_handshake(initiator, initiator_transport)
    request = initiator.create_initial_request
    initiator_transport.send(request)
    request
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

  describe 'full handshake round-trip via transport' do
    it 'authenticates Alice after the handshake completes' do
      request = perform_handshake(alice, transport_a)
      expect(alice.authenticated?(request[:initial_nonce])).to be(true)
    end

    it 'authenticates Bob after the handshake completes' do
      perform_handshake(alice, transport_a)
      # Bob's session is indexed by his own nonce; find it by his authenticated state
      bob_nonce = bob.session_manager.instance_variable_get(:@by_nonce).keys.first
      expect(bob.authenticated?(bob_nonce)).to be(true)
    end

    it "includes Bob's identity key in the initial response" do
      # Capture the response sent by Bob via transport by observing transport_a delivery
      received_response = nil
      original_callback = transport_a.instance_variable_get(:@on_data_callback)
      transport_a.on_data do |msg|
        received_response = msg if msg[:message_type] == BSV::Auth::MSG_INITIAL_RESPONSE
        original_callback&.call(msg)
      end

      perform_handshake(alice, transport_a)
      expect(received_response[:identity_key]).to eq(bob.identity_key)
    end

    it "echoes Alice's nonce back in the initial response" do
      received_response = nil
      original_callback = transport_a.instance_variable_get(:@on_data_callback)
      transport_a.on_data do |msg|
        received_response = msg if msg[:message_type] == BSV::Auth::MSG_INITIAL_RESPONSE
        original_callback&.call(msg)
      end

      request = perform_handshake(alice, transport_a)
      expect(received_response[:your_nonce]).to eq(request[:initial_nonce])
    end
  end

  describe 'version and type guard via transport' do
    it 'raises AuthError when the version is wrong' do
      bad_msg = { version: '9.9', message_type: BSV::Auth::MSG_INITIAL_REQUEST }
      expect { alice.handle_incoming_message(bad_msg) }.to raise_error(BSV::Auth::AuthError, /Unsupported auth version/)
    end

    it 'raises AuthError for an unknown message type' do
      bad_msg = { version: BSV::Auth::AUTH_VERSION, message_type: 'mystery' }
      expect { alice.handle_incoming_message(bad_msg) }.to raise_error(BSV::Auth::AuthError, /Unknown message type/)
    end
  end

  describe 'general message exchange (post-handshake)' do
    let(:payload) { [72, 101, 108, 108, 111] } # "Hello"

    let(:alice_session_nonce) do
      perform_handshake(alice, transport_a)
      alice.session_manager.instance_variable_get(:@by_nonce).keys.first
    end

    it 'can create a general message after authentication' do
      msg = alice.create_general_message(alice_session_nonce, payload)
      expect(msg[:message_type]).to eq(BSV::Auth::MSG_GENERAL)
    end

    it 'Bob can verify and read the payload sent by Alice via transport' do
      # After handshake, Alice sends a general message via transport_a.
      # It is delivered to Bob's on_data, which processes it and returns a result.
      # We capture the result by intercepting Bob's handle_incoming_message response.
      perform_handshake(alice, transport_a)
      alice_nonce = alice.session_manager.instance_variable_get(:@by_nonce).keys.first

      received_result = nil
      transport_b.on_data do |msg|
        received_result = bob.handle_incoming_message(msg)
      end

      msg = alice.create_general_message(alice_nonce, payload)
      transport_a.send(msg)

      expect(received_result[:payload]).to eq(payload)
      expect(received_result[:peer_identity_key]).to eq(alice.identity_key)
    end
  end

  describe 'general message — raises without auth' do
    it 'raises AuthError when no session exists for the identifier' do
      expect do
        alice.create_general_message('no-such-nonce', [1, 2, 3])
      end.to raise_error(BSV::Auth::AuthError, /Not authenticated/)
    end
  end

  describe '#on_general_message / #off_general_message' do
    let(:payload) { [72, 101, 108, 108, 111] } # "Hello"

    # Complete the handshake so both peers are authenticated, then return Alice's
    # session nonce so she can build a general message directed at Bob.
    let(:alice_session_nonce) do
      perform_handshake(alice, transport_a)
      alice.session_manager.instance_variable_get(:@by_nonce).keys.first
    end

    it 'returns an integer callback ID' do
      id = bob.on_general_message { |_k, _p| }
      expect(id).to be_a(Integer)
    end

    it 'increments the ID for each registration' do
      id1 = bob.on_general_message { |_k, _p| }
      id2 = bob.on_general_message { |_k, _p| }
      expect(id2).to eq(id1 + 1)
    end

    it 'fires the callback with sender key and payload when a general message is received' do
      received = []
      bob.on_general_message { |sender_key, msg_payload| received << [sender_key, msg_payload] }

      msg = alice.create_general_message(alice_session_nonce, payload)
      bob.handle_incoming_message(msg)

      expect(received.length).to eq(1)
      expect(received[0][0]).to eq(alice.identity_key)
      expect(received[0][1]).to eq(payload)
    end

    it 'fires all registered callbacks when a message is received' do
      calls = []
      bob.on_general_message { |_k, _p| calls << :first }
      bob.on_general_message { |_k, _p| calls << :second }

      msg = alice.create_general_message(alice_session_nonce, payload)
      bob.handle_incoming_message(msg)

      expect(calls).to contain_exactly(:first, :second)
    end

    it 'does not fire a callback after off_general_message removes it' do
      calls = []
      id = bob.on_general_message { |_k, _p| calls << :fired }
      bob.off_general_message(id)

      msg = alice.create_general_message(alice_session_nonce, payload)
      bob.handle_incoming_message(msg)

      expect(calls).to be_empty
    end
  end

  describe '#on_certificates_received / #off_certificates_received' do
    it 'returns an integer callback ID' do
      id = alice.on_certificates_received { |_k, _c| }
      expect(id).to be_a(Integer)
    end

    it 'unregisters without error' do
      id = alice.on_certificates_received { |_k, _c| }
      expect { alice.off_certificates_received(id) }.not_to raise_error
    end
  end

  describe '#on_certificate_request / #off_certificate_request' do
    it 'returns an integer callback ID' do
      id = alice.on_certificate_request { |_k, _r| }
      expect(id).to be_a(Integer)
    end

    it 'unregisters without error' do
      id = alice.on_certificate_request { |_k, _r| }
      expect { alice.off_certificate_request(id) }.not_to raise_error
    end
  end

  describe '#last_interacted_peer' do
    it 'is nil initially' do
      expect(alice.last_interacted_peer).to be_nil
    end

    it 'is set to the peer identity key after the initiator processes the initial response' do
      perform_handshake(alice, transport_a)
      expect(alice.last_interacted_peer).to eq(bob.identity_key)
    end

    it 'is set for the responder after processing an initial request' do
      perform_handshake(alice, transport_a)
      expect(bob.last_interacted_peer).to eq(alice.identity_key)
    end

    it 'is updated after processing a general message' do
      perform_handshake(alice, transport_a)
      alice_nonce = alice.session_manager.instance_variable_get(:@by_nonce).keys.first

      # Reset bob's tracking to prove it updates on general message too
      bob.instance_variable_set(:@last_interacted_peer, nil)

      msg = alice.create_general_message(alice_nonce, [1, 2, 3])
      bob.handle_incoming_message(msg)

      expect(bob.last_interacted_peer).to eq(alice.identity_key)
    end

    it 'is not overwritten on initial request if already set (responder side)' do
      # Create bob2 without a transport so handle_incoming_message calls do not
      # trigger forwarding via a partner transport (which would interfere with other
      # peers' handshakes). The last_interacted_peer logic does not require transport.
      carol_wallet = BSV::Wallet::ProtoWallet.new(BSV::Primitives::PrivateKey.generate)
      carol2 = described_class.new(wallet: carol_wallet)
      bob2   = described_class.new(wallet: bob_wallet)

      # Carol↔bob2 handshake (direct calls)
      carol_request = carol2.create_initial_request
      carol_response = bob2.handle_incoming_message(carol_request)
      carol2.handle_incoming_message(carol_response)
      first_peer = bob2.last_interacted_peer

      # Alice↔bob2 handshake (direct calls)
      alice2 = described_class.new(wallet: alice_wallet)
      alice_request = alice2.create_initial_request
      alice_response = bob2.handle_incoming_message(alice_request)
      alice2.handle_incoming_message(alice_response)

      expect(bob2.last_interacted_peer).to eq(first_peer)
    end

    it 'is not set when auto_persist_last_session is false' do
      transport_c, transport_d = PairedTransport.create_pair
      alice2 = described_class.new(wallet: alice_wallet, transport: transport_c, auto_persist_last_session: false)
      bob2   = described_class.new(wallet: bob_wallet,   transport: transport_d, auto_persist_last_session: false)

      request = alice2.create_initial_request
      transport_c.send(request)

      expect(alice2.last_interacted_peer).to be_nil
      expect(bob2.last_interacted_peer).to be_nil
    end
  end

  describe 'tampered initial response' do
    it 'raises AuthError when the signature has been tampered with' do
      request = alice.create_initial_request
      response = bob.handle_incoming_message(request)

      bad_sig = response[:signature].dup
      bad_sig[-1] ^= 0xFF
      tampered = response.merge(signature: bad_sig)

      expect { alice.handle_incoming_message(tampered) }
        .to raise_error(BSV::Auth::AuthError, /signature verification failed/)
    end

    it 'removes the pending session after a failed signature verification' do
      request   = alice.create_initial_request
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
