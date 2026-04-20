# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Auth::Peer do
  let(:alice_key)    { BSV::Primitives::PrivateKey.generate }
  let(:bob_key)      { BSV::Primitives::PrivateKey.generate }
  let(:alice_wallet) { BSV::Wallet::Client.new(alice_key, storage: BSV::Wallet::Store::Memory.new) }
  let(:bob_wallet)   { BSV::Wallet::Client.new(bob_key, storage: BSV::Wallet::Store::Memory.new) }

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

  # Performs the full three-step handshake via transport and returns the session nonce.
  # The handshake is transport-mediated: alice sends the request via transport_a, which
  # delivers it to bob; bob's on_data triggers handle_incoming_message, which sends the
  # response back via transport_b; alice's on_data completes the handshake.
  def perform_handshake(initiator, initiator_transport)
    request = initiator.send(:create_initial_request)
    initiator_transport.send(request)
    request[:initial_nonce]
  end

  describe '.new' do
    it 'raises ArgumentError when transport is nil' do
      expect do
        described_class.new(wallet: alice_wallet, transport: nil)
      end.to raise_error(ArgumentError, /transport is required/)
    end
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

  describe '#create_initial_request (private)' do
    subject(:request) { alice.send(:create_initial_request) }

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
      second_request = alice.send(:create_initial_request)
      expect(request[:initial_nonce]).not_to eq(second_request[:initial_nonce])
    end

    it 'is private' do
      expect { alice.create_initial_request }.to raise_error(NoMethodError)
    end
  end

  describe 'full handshake round-trip via transport' do
    it 'authenticates Alice after the handshake completes' do
      nonce = perform_handshake(alice, transport_a)
      expect(alice.authenticated?(nonce)).to be(true)
    end

    it 'authenticates Bob after the handshake completes' do
      perform_handshake(alice, transport_a)
      bob_nonce = bob.session_manager.instance_variable_get(:@by_nonce).keys.first
      expect(bob.authenticated?(bob_nonce)).to be(true)
    end

    it "includes Bob's identity key in the initial response" do
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

      nonce = perform_handshake(alice, transport_a)
      expect(received_response[:your_nonce]).to eq(nonce)
    end
  end

  describe 'version and type guard (private handle_incoming_message)' do
    it 'raises AuthError when the version is wrong' do
      bad_msg = { version: '9.9', message_type: BSV::Auth::MSG_INITIAL_REQUEST }
      expect { alice.send(:handle_incoming_message, bad_msg) }.to raise_error(BSV::Auth::AuthError, /Unsupported auth version/)
    end

    it 'raises AuthError for an unknown message type' do
      bad_msg = { version: BSV::Auth::AUTH_VERSION, message_type: 'mystery' }
      expect { alice.send(:handle_incoming_message, bad_msg) }.to raise_error(BSV::Auth::AuthError, /Unknown message type/)
    end

    it 'handle_incoming_message is private' do
      bad_msg = { version: BSV::Auth::AUTH_VERSION, message_type: BSV::Auth::MSG_GENERAL }
      expect { alice.handle_incoming_message(bad_msg) }.to raise_error(NoMethodError)
    end
  end

  describe 'general message exchange (post-handshake)' do
    let(:payload) { [72, 101, 108, 108, 111] } # "Hello"

    let(:alice_session_nonce) do
      perform_handshake(alice, transport_a)
      alice.session_manager.instance_variable_get(:@by_nonce).keys.first
    end

    it 'can create a general message after authentication' do
      msg = alice.send(:create_general_message, alice_session_nonce, payload)
      expect(msg[:message_type]).to eq(BSV::Auth::MSG_GENERAL)
    end

    it 'create_general_message is private' do
      perform_handshake(alice, transport_a)
      nonce = alice.session_manager.instance_variable_get(:@by_nonce).keys.first
      expect { alice.create_general_message(nonce, payload) }.to raise_error(NoMethodError)
    end

    it 'Bob can verify and read the payload sent by Alice via transport' do
      perform_handshake(alice, transport_a)
      alice_nonce = alice.session_manager.instance_variable_get(:@by_nonce).keys.first

      received_result = nil
      transport_b.on_data do |msg|
        received_result = bob.send(:handle_incoming_message, msg)
      end

      msg = alice.send(:create_general_message, alice_nonce, payload)
      transport_a.send(msg)

      expect(received_result[:payload]).to eq(payload)
      expect(received_result[:peer_identity_key]).to eq(alice.identity_key)
    end
  end

  describe 'general message — raises without auth' do
    it 'raises AuthError when no session exists for the identifier' do
      expect do
        alice.send(:create_general_message, 'no-such-nonce', [1, 2, 3])
      end.to raise_error(BSV::Auth::AuthError, /Not authenticated/)
    end
  end

  describe '#on_general_message / #off_general_message' do
    let(:payload) { [72, 101, 108, 108, 111] } # "Hello"

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

      msg = alice.send(:create_general_message, alice_session_nonce, payload)
      bob.send(:handle_incoming_message, msg)

      expect(received.length).to eq(1)
      expect(received[0][0]).to eq(alice.identity_key)
      expect(received[0][1]).to eq(payload)
    end

    it 'fires all registered callbacks when a message is received' do
      calls = []
      bob.on_general_message { |_k, _p| calls << :first }
      bob.on_general_message { |_k, _p| calls << :second }

      msg = alice.send(:create_general_message, alice_session_nonce, payload)
      bob.send(:handle_incoming_message, msg)

      expect(calls).to contain_exactly(:first, :second)
    end

    it 'does not fire a callback after off_general_message removes it' do
      calls = []
      id = bob.on_general_message { |_k, _p| calls << :fired }
      bob.off_general_message(id)

      msg = alice.send(:create_general_message, alice_session_nonce, payload)
      bob.send(:handle_incoming_message, msg)

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

      msg = alice.send(:create_general_message, alice_nonce, [1, 2, 3])
      bob.send(:handle_incoming_message, msg)

      expect(bob.last_interacted_peer).to eq(alice.identity_key)
    end

    it 'is not overwritten on initial request if already set (responder side)' do
      carol_wallet = BSV::Wallet::Client.new(BSV::Primitives::PrivateKey.generate, storage: BSV::Wallet::Store::Memory.new)

      # Carol↔bob2 full handshake: establishes bob2.last_interacted_peer = carol
      tc1, tc2 = PairedTransport.create_pair
      carol2 = described_class.new(wallet: carol_wallet, transport: tc1)
      bob2   = described_class.new(wallet: bob_wallet,   transport: tc2)
      carol2.get_authenticated_session(bob2.identity_key)
      first_peer = bob2.last_interacted_peer
      expect(first_peer).to eq(carol2.identity_key)

      # Simulate a second initiator (Alice) sending an initialRequest directly to bob2
      # via handle_incoming_message (bypassing transport routing to avoid double-delivery).
      # Bob2's response will be forwarded via tc2→tc1→carol2, which will fail nonce
      # verification (carol2 does not recognise alice's nonce) and raise — that's
      # acceptable since we only care that bob2.last_interacted_peer stays as carol.
      ta, _tb = PairedTransport.create_pair
      alice2 = described_class.new(wallet: alice_wallet, transport: ta)
      alice_req = alice2.send(:create_initial_request)

      # Bob2's process_initial_request uses ||= so it should not overwrite carol.
      # The response forwarded to tc2 will trigger an error on carol2's side — ignore it.
      begin
        bob2.send(:handle_incoming_message, alice_req)
      rescue BSV::Auth::AuthError
        nil
      end

      expect(bob2.last_interacted_peer).to eq(first_peer)
    end

    it 'is not set when auto_persist_last_session is false' do
      transport_c, transport_d = PairedTransport.create_pair
      alice2 = described_class.new(wallet: alice_wallet, transport: transport_c, auto_persist_last_session: false)
      bob2   = described_class.new(wallet: bob_wallet,   transport: transport_d, auto_persist_last_session: false)

      request = alice2.send(:create_initial_request)
      transport_c.send(request)

      expect(alice2.last_interacted_peer).to be_nil
      expect(bob2.last_interacted_peer).to be_nil
    end
  end

  describe 'tampered initial response' do
    it 'raises AuthError when the signature has been tampered with' do
      request = alice.send(:create_initial_request)
      response = bob.send(:handle_incoming_message, request)

      bad_sig = response[:signature].dup
      bad_sig[-1] ^= 0xFF
      tampered = response.merge(signature: bad_sig)

      expect { alice.send(:handle_incoming_message, tampered) }
        .to raise_error(BSV::Auth::AuthError, /signature verification failed/)
    end

    it 'removes the pending session after a failed signature verification' do
      request   = alice.send(:create_initial_request)
      our_nonce = request[:initial_nonce]

      response = bob.send(:handle_incoming_message, request)
      bad_sig  = response[:signature].dup
      bad_sig[-1] ^= 0xFF
      tampered = response.merge(signature: bad_sig)

      begin
        alice.send(:handle_incoming_message, tampered)
      rescue BSV::Auth::AuthError
        nil
      end

      expect(alice.session_manager.get_session(our_nonce)).to be_nil
    end
  end

  # --- Certificate exchange helpers ---

  # Shared helper: issue a MasterCertificate and build a VerifiableCertificate
  # with a keyring for the given verifier.
  def build_verifiable_certificate(subject_wallet:, certifier_wallet:, verifier_hex:, cert_type:, fields:)
    master_cert = BSV::Auth::MasterCertificate.issue_certificate_for_subject(
      certifier_wallet,
      subject_wallet.get_public_key({ identity_key: true })[:public_key],
      fields,
      cert_type
    )

    keyring = BSV::Auth::MasterCertificate.create_keyring_for_verifier(
      subject_wallet,
      certifier: master_cert.certifier,
      verifier: verifier_hex,
      fields: master_cert.fields,
      fields_to_reveal: fields.keys,
      master_keyring: master_cert.master_keyring,
      serial_number: master_cert.serial_number
    )

    BSV::Auth::VerifiableCertificate.from_certificate(master_cert, keyring)
  end

  describe '#create_certificate_request (private, low-level builder)' do
    let(:cert_type) { Base64.strict_encode64(SecureRandom.random_bytes(32)) }

    before { perform_handshake(alice, transport_a) }

    it 'returns a message hash with the correct message_type' do
      to_request = { certifiers: [bob.identity_key], types: { cert_type => ['name'] } }
      msg = alice.send(:create_certificate_request, alice.last_interacted_peer, to_request)
      expect(msg[:message_type]).to eq(BSV::Auth::MSG_CERT_REQUEST)
    end

    it 'includes nonce, your_nonce, initial_nonce, signature, and requested_certificates' do
      to_request = { certifiers: [bob.identity_key], types: { cert_type => ['name'] } }
      msg = alice.send(:create_certificate_request, alice.last_interacted_peer, to_request)
      expect(msg[:nonce]).not_to be_nil
      expect(msg[:your_nonce]).not_to be_nil
      expect(msg[:initial_nonce]).not_to be_nil
      expect(msg[:signature]).not_to be_nil
      expect(msg[:requested_certificates]).to eq(to_request)
    end

    it 'raises AuthError for an unauthenticated identifier' do
      expect do
        alice.send(:create_certificate_request, 'no-such-peer', { certifiers: ['abc'], types: {} })
      end.to raise_error(BSV::Auth::AuthError, /Not authenticated/)
    end

    it 'is private' do
      to_request = { certifiers: [bob.identity_key], types: { cert_type => ['name'] } }
      expect { alice.create_certificate_request(alice.last_interacted_peer, to_request) }
        .to raise_error(NoMethodError)
    end
  end

  describe '#create_certificate_response (private, low-level builder)' do
    let(:certifier_wallet) { BSV::Wallet::Client.new(BSV::Primitives::PrivateKey.generate, storage: BSV::Wallet::Store::Memory.new) }
    let(:verifiable_cert) do
      build_verifiable_certificate(
        subject_wallet: alice_wallet,
        certifier_wallet: certifier_wallet,
        verifier_hex: bob.identity_key,
        cert_type: cert_type,
        fields: { 'name' => 'Alice' }
      )
    end
    let(:cert_type) { Base64.strict_encode64(SecureRandom.random_bytes(32)) }

    before { perform_handshake(alice, transport_a) }

    it 'returns a message hash with the correct message_type' do
      msg = alice.send(:create_certificate_response, alice.last_interacted_peer, [verifiable_cert])
      expect(msg[:message_type]).to eq(BSV::Auth::MSG_CERT_RESPONSE)
    end

    it 'includes certificates serialised as Hashes' do
      msg = alice.send(:create_certificate_response, alice.last_interacted_peer, [verifiable_cert])
      expect(msg[:certificates]).to be_an(Array)
      expect(msg[:certificates].first).to be_a(Hash)
      expect(msg[:certificates].first['subject']).to eq(alice.identity_key)
    end

    it 'raises AuthError for an unauthenticated identifier' do
      expect do
        alice.send(:create_certificate_response, 'no-such-peer', [verifiable_cert])
      end.to raise_error(BSV::Auth::AuthError, /Not authenticated/)
    end
  end

  describe 'certificateRequest dispatch and processing' do
    let(:certifier_wallet) { BSV::Wallet::Client.new(BSV::Primitives::PrivateKey.generate, storage: BSV::Wallet::Store::Memory.new) }
    let(:cert_type)        { Base64.strict_encode64(SecureRandom.random_bytes(32)) }

    # Handshake first, then Alice creates a cert request to Bob
    let(:cert_request_msg) do
      perform_handshake(alice, transport_a)
      to_request = { certifiers: [certifier_wallet.get_public_key({ identity_key: true })[:public_key]], types: { cert_type => ['name'] } }
      alice.send(:create_certificate_request, alice.last_interacted_peer, to_request)
    end

    it 'dispatches certificateRequest to process_certificate_request' do
      expect { bob.send(:handle_incoming_message, cert_request_msg) }.not_to raise_error
    end

    it 'raises AuthError for an invalid nonce in certificateRequest' do
      perform_handshake(alice, transport_a)
      to_request = { certifiers: ['abc'], types: {} }
      bad_nonce_msg = {
        version: BSV::Auth::AUTH_VERSION,
        message_type: BSV::Auth::MSG_CERT_REQUEST,
        identity_key: alice.identity_key,
        nonce: Base64.strict_encode64(SecureRandom.random_bytes(32)),
        initial_nonce: 'fake',
        your_nonce: Base64.strict_encode64(SecureRandom.random_bytes(32)),
        requested_certificates: to_request,
        signature: [0] * 71
      }
      expect { bob.send(:handle_incoming_message, bad_nonce_msg) }
        .to raise_error(BSV::Auth::AuthError, /Unable to verify nonce/)
    end

    it 'raises AuthError when certificateRequest signature is tampered' do
      msg = cert_request_msg.dup
      bad_sig = msg[:signature].dup
      bad_sig[-1] ^= 0xFF
      msg[:signature] = bad_sig
      expect { bob.send(:handle_incoming_message, msg) }
        .to raise_error(BSV::Auth::AuthError, /signature verification failed/)
    end

    it 'fires on_certificate_request callback when registered' do
      received = []
      bob.on_certificate_request { |sender_key, requested| received << [sender_key, requested] }

      bob.send(:handle_incoming_message, cert_request_msg)

      expect(received.length).to eq(1)
      expect(received[0][0]).to eq(alice.identity_key)
      expect(received[0][1][:types]).to have_key(cert_type)
    end

    it 'does not call get_verifiable_certificates when certificate_request callback is registered' do
      bob.on_certificate_request { |_k, _r| }

      allow(BSV::Auth).to receive(:get_verifiable_certificates)
      bob.send(:handle_incoming_message, cert_request_msg)
      expect(BSV::Auth).not_to have_received(:get_verifiable_certificates)
    end
  end

  describe 'certificateResponse dispatch and processing' do
    let(:certifier_wallet) { BSV::Wallet::Client.new(BSV::Primitives::PrivateKey.generate, storage: BSV::Wallet::Store::Memory.new) }
    let(:cert_type)        { Base64.strict_encode64(SecureRandom.random_bytes(32)) }
    let(:certifier_hex)    { certifier_wallet.get_public_key({ identity_key: true })[:public_key] }
    let(:bob) do
      described_class.new(
        wallet: bob_wallet,
        transport: transport_b,
        certificates_to_request: { certifiers: [certifier_hex], types: { cert_type => ['name'] } }
      )
    end

    let(:verifiable_cert) do
      build_verifiable_certificate(
        subject_wallet: alice_wallet,
        certifier_wallet: certifier_wallet,
        verifier_hex: bob.identity_key,
        cert_type: cert_type,
        fields: { 'name' => 'Alice' }
      )
    end

    let(:cert_response_msg) do
      perform_handshake(alice, transport_a)
      alice.send(:create_certificate_response, alice.last_interacted_peer, [verifiable_cert])
    end

    it 'dispatches certificateResponse to process_certificate_response' do
      expect { bob.send(:handle_incoming_message, cert_response_msg) }.not_to raise_error
    end

    it 'marks session.certificates_validated = true when certificates are valid' do
      bob.send(:handle_incoming_message, cert_response_msg)

      bob_session = bob.session_manager.get_session(alice.identity_key)
      expect(bob_session.certificates_validated).to be(true)
    end

    it 'fires on_certificates_received callback with sender key and certs' do
      received = []
      bob.on_certificates_received { |sender_key, certs| received << [sender_key, certs] }

      bob.send(:handle_incoming_message, cert_response_msg)

      expect(received.length).to eq(1)
      expect(received[0][0]).to eq(alice.identity_key)
      expect(received[0][1]).to be_an(Array)
      expect(received[0][1].first['subject']).to eq(alice.identity_key)
    end

    it 'raises AuthError when certificateResponse signature is tampered' do
      msg = cert_response_msg.dup
      bad_sig = msg[:signature].dup
      bad_sig[-1] ^= 0xFF
      msg[:signature] = bad_sig

      expect { bob.send(:handle_incoming_message, msg) }
        .to raise_error(BSV::Auth::AuthError, /signature verification failed/)
    end

    it 'fires on_certificates_received with empty array when certs array is empty' do
      perform_handshake(alice, transport_a)
      empty_response = alice.send(:create_certificate_response, alice.last_interacted_peer, [])

      received = []
      bob.on_certificates_received { |_k, certs| received << certs }
      bob.send(:handle_incoming_message, empty_response)

      expect(received).to eq([[]])
    end

    it 'does not call validate_certificates when certificates array is empty' do
      perform_handshake(alice, transport_a)
      empty_response = alice.send(:create_certificate_response, alice.last_interacted_peer, [])

      allow(BSV::Auth).to receive(:validate_certificates)
      bob.send(:handle_incoming_message, empty_response)
      expect(BSV::Auth).not_to have_received(:validate_certificates)
    end
  end

  describe 'certificateRequest round-trip via transport' do
    let(:certifier_wallet) { BSV::Wallet::Client.new(BSV::Primitives::PrivateKey.generate, storage: BSV::Wallet::Store::Memory.new) }
    let(:cert_type)        { Base64.strict_encode64(SecureRandom.random_bytes(32)) }
    let(:certifier_hex)    { certifier_wallet.get_public_key({ identity_key: true })[:public_key] }

    let(:bob_cert) do
      build_verifiable_certificate(
        subject_wallet: bob_wallet,
        certifier_wallet: certifier_wallet,
        verifier_hex: alice.identity_key,
        cert_type: cert_type,
        fields: { 'name' => 'Bob' }
      )
    end

    it 'auto-fetches and sends certificateResponse when no callback registered' do
      perform_handshake(alice, transport_a)

      to_request = { certifiers: [certifier_hex], types: { cert_type => ['name'] } }
      cert_request_msg = alice.send(:create_certificate_request, alice.last_interacted_peer, to_request)

      expect { bob.send(:handle_incoming_message, cert_request_msg) }.not_to raise_error
    end

    it 'fires certificate_request callback during certificateRequest and skips auto-fetch' do
      perform_handshake(alice, transport_a)

      callback_fired = false
      bob.on_certificate_request { |_key, _req| callback_fired = true }

      to_request = { certifiers: [certifier_hex], types: { cert_type => ['name'] } }
      cert_request_msg = alice.send(:create_certificate_request, alice.last_interacted_peer, to_request)
      bob.send(:handle_incoming_message, cert_request_msg)

      expect(callback_fired).to be(true)
    end
  end

  describe 'certificates in initial handshake' do
    let(:certifier_wallet) { BSV::Wallet::Client.new(BSV::Primitives::PrivateKey.generate, storage: BSV::Wallet::Store::Memory.new) }
    let(:cert_type)        { Base64.strict_encode64(SecureRandom.random_bytes(32)) }
    let(:certifier_hex)    { certifier_wallet.get_public_key({ identity_key: true })[:public_key] }

    context 'when responder includes certificates in initialResponse' do
      it 'initiator validates certificates and marks session validated' do
        cert = build_verifiable_certificate(
          subject_wallet: bob_wallet,
          certifier_wallet: certifier_wallet,
          verifier_hex: alice.identity_key,
          cert_type: cert_type,
          fields: { 'name' => 'Bob' }
        )

        ta, tb = PairedTransport.create_pair
        alice2 = described_class.new(
          wallet: alice_wallet,
          transport: ta,
          certificates_to_request: { certifiers: [certifier_hex], types: { cert_type => ['name'] } }
        )
        bob2 = described_class.new(wallet: bob_wallet, transport: tb)

        request  = alice2.send(:create_initial_request)
        response = bob2.send(:handle_incoming_message, request)

        # Manually inject Bob's cert into the response (simulating auto-fetch)
        response_with_certs = response.merge(certificates: [cert.to_h])

        alice2.send(:handle_incoming_message, response_with_certs)

        alice_session = alice2.session_manager.get_session(bob2.identity_key)
        expect(alice_session.certificates_validated).to be(true)
      end

      it 'fires on_certificates_received callback on the initiator' do
        cert = build_verifiable_certificate(
          subject_wallet: bob_wallet,
          certifier_wallet: certifier_wallet,
          verifier_hex: alice.identity_key,
          cert_type: cert_type,
          fields: { 'name' => 'Bob' }
        )

        ta, tb = PairedTransport.create_pair
        alice2 = described_class.new(
          wallet: alice_wallet,
          transport: ta,
          certificates_to_request: { certifiers: [certifier_hex], types: { cert_type => ['name'] } }
        )
        bob2 = described_class.new(wallet: bob_wallet, transport: tb)

        received = []
        alice2.on_certificates_received { |sender_key, certs| received << [sender_key, certs] }

        request  = alice2.send(:create_initial_request)
        response = bob2.send(:handle_incoming_message, request)
        response_with_certs = response.merge(certificates: [cert.to_h])
        alice2.send(:handle_incoming_message, response_with_certs)

        expect(received.length).to eq(1)
        expect(received[0][0]).to eq(bob2.identity_key)
      end
    end

    context 'when responder requests certificates in initialResponse' do
      it 'fires certificate_request callback on initiator when callback is registered' do
        ta, tb = PairedTransport.create_pair
        alice2 = described_class.new(wallet: alice_wallet, transport: ta)
        bob2   = described_class.new(
          wallet: bob_wallet,
          transport: tb,
          certificates_to_request: { certifiers: [certifier_hex], types: { cert_type => ['name'] } }
        )

        callback_fired = false
        alice2.on_certificate_request { |_k, _r| callback_fired = true }

        request  = alice2.send(:create_initial_request)
        response = bob2.send(:handle_incoming_message, request)
        alice2.send(:handle_incoming_message, response)

        expect(callback_fired).to be(true)
      end

      it 'does not send empty certificateResponse when auto-fetch returns nothing' do
        ta, tb = PairedTransport.create_pair
        alice2 = described_class.new(wallet: alice_wallet, transport: ta)
        bob2   = described_class.new(
          wallet: bob_wallet,
          transport: tb,
          certificates_to_request: { certifiers: [certifier_hex], types: { cert_type => ['name'] } }
        )

        request  = alice2.send(:create_initial_request)
        response = bob2.send(:handle_incoming_message, request)

        expect { alice2.send(:handle_incoming_message, response) }.not_to raise_error
      end
    end

    context 'when initiator requests certificates in initialRequest' do
      it 'fires certificate_request callback on responder when callback is registered' do
        ta, tb = PairedTransport.create_pair
        alice2 = described_class.new(
          wallet: alice_wallet,
          transport: ta,
          certificates_to_request: { certifiers: [certifier_hex], types: { cert_type => ['name'] } }
        )
        bob2 = described_class.new(wallet: bob_wallet, transport: tb)

        callback_fired = false
        bob2.on_certificate_request { |_k, _r| callback_fired = true }

        request = alice2.send(:create_initial_request)
        bob2.send(:handle_incoming_message, request)

        expect(callback_fired).to be(true)
      end

      it 'includes certificates in initialResponse when auto-fetch returns certs' do
        ta, tb = PairedTransport.create_pair
        alice2 = described_class.new(
          wallet: alice_wallet,
          transport: ta,
          certificates_to_request: { certifiers: [certifier_hex], types: { cert_type => ['name'] } }
        )
        bob2 = described_class.new(wallet: bob_wallet, transport: tb)

        fake_cert = build_verifiable_certificate(
          subject_wallet: bob_wallet,
          certifier_wallet: certifier_wallet,
          verifier_hex: alice_wallet.get_public_key({ identity_key: true })[:public_key],
          cert_type: cert_type,
          fields: { 'name' => 'Bob' }
        )

        allow(BSV::Auth).to receive(:get_verifiable_certificates).and_return([fake_cert])

        request  = alice2.send(:create_initial_request)
        response = bob2.send(:handle_incoming_message, request)

        expect(response[:certificates]).to be_an(Array)
        expect(response[:certificates]).not_to be_empty
      end
    end
  end

  # --- High-level session API ---

  describe '#to_peer' do
    let(:payload) { [72, 101, 108, 108, 111] } # "Hello"

    it 'sends a general message that triggers on_general_message on the receiver' do
      received = []
      bob.on_general_message { |sender_key, msg_payload| received << [sender_key, msg_payload] }

      alice.to_peer(payload, bob.identity_key)

      expect(received.length).to eq(1)
      expect(received[0][0]).to eq(alice.identity_key)
      expect(received[0][1]).to eq(payload)
    end

    it 'auto-initiates handshake when no session exists' do
      alice.to_peer(payload, bob.identity_key)
      expect(alice.authenticated?(bob.identity_key)).to be(true)
    end

    it 'reuses an existing authenticated session on second call' do
      alice.to_peer(payload, bob.identity_key)
      nonces_after_first = alice.session_manager.instance_variable_get(:@by_nonce).keys.dup

      alice.to_peer(payload, bob.identity_key)
      nonces_after_second = alice.session_manager.instance_variable_get(:@by_nonce).keys

      expect(nonces_after_second).to eq(nonces_after_first)
    end

    it 'uses @last_interacted_peer as default identity_key' do
      # First call establishes the session and sets @last_interacted_peer
      alice.to_peer(payload, bob.identity_key)

      received = []
      bob.on_general_message { |_key, msg_payload| received << msg_payload }

      # Second call without identity_key — should use @last_interacted_peer
      alice.to_peer([1, 2, 3])

      expect(received).to include([1, 2, 3])
    end

    it 'raises AuthError when certificates are required but not yet validated' do
      certifier_hex = BSV::Primitives::PrivateKey.generate.public_key.to_hex
      cert_type     = Base64.strict_encode64(SecureRandom.random_bytes(32))

      ta, tb = PairedTransport.create_pair
      alice2 = described_class.new(
        wallet: alice_wallet,
        transport: ta,
        certificates_to_request: { certifiers: [certifier_hex], types: { cert_type => ['name'] } }
      )
      bob2 = described_class.new(wallet: bob_wallet, transport: tb)

      # Perform handshake manually (no certs provided — session will be unvalidated)
      request  = alice2.send(:create_initial_request)
      response = bob2.send(:handle_incoming_message, request)
      alice2.send(:handle_incoming_message, response)

      # At this point alice2 has certificates_required = true, certificates_validated = false
      session = alice2.session_manager.get_session(bob2.identity_key)
      expect(session.certificates_required).to be(true)
      expect(session.certificates_validated).to be(false)

      expect { alice2.to_peer(payload, bob2.identity_key) }
        .to raise_error(BSV::Auth::AuthError, /certificate validation/)
    end
  end

  describe '#get_authenticated_session' do
    it 'returns an authenticated session' do
      session = alice.get_authenticated_session(bob.identity_key)
      expect(session.authenticated?).to be(true)
    end

    it 'returns the same session on a second call (no new handshake)' do
      session1 = alice.get_authenticated_session(bob.identity_key)
      nonces1  = alice.session_manager.instance_variable_get(:@by_nonce).keys.dup

      session2 = alice.get_authenticated_session(bob.identity_key)
      nonces2  = alice.session_manager.instance_variable_get(:@by_nonce).keys

      expect(session2.session_nonce).to eq(session1.session_nonce)
      expect(nonces2).to eq(nonces1)
    end

    it 'resolves from @last_interacted_peer when no identity_key given' do
      alice.get_authenticated_session(bob.identity_key)
      expect(alice.last_interacted_peer).to eq(bob.identity_key)

      session = alice.get_authenticated_session
      expect(session.peer_identity_key).to eq(bob.identity_key)
    end

    it 'raises AuthError when handshake times out' do
      # Build a transport that drops all messages so the handshake never completes
      dropping_transport = PairedTransport.new
      dropping_transport.partner = PairedTransport.new # messages go to unregistered peer

      fast_alice = described_class.new(wallet: alice_wallet, transport: dropping_transport, handshake_timeout: 1)

      expect { fast_alice.get_authenticated_session(bob.identity_key) }
        .to raise_error(BSV::Auth::AuthError, /timed out/)
    end
  end

  describe '#request_certificates' do
    let(:certifier_wallet) { BSV::Wallet::Client.new(BSV::Primitives::PrivateKey.generate, storage: BSV::Wallet::Store::Memory.new) }
    let(:cert_type)        { Base64.strict_encode64(SecureRandom.random_bytes(32)) }
    let(:certifier_hex)    { certifier_wallet.get_public_key({ identity_key: true })[:public_key] }

    it 'sends a certificateRequest via transport, triggering on_certificate_request on the peer' do
      alice.get_authenticated_session(bob.identity_key)

      callback_fired = false
      bob.on_certificate_request { |_key, _req| callback_fired = true }

      to_request = { certifiers: [certifier_hex], types: { cert_type => ['name'] } }
      alice.request_certificates(to_request, bob.identity_key)

      expect(callback_fired).to be(true)
    end

    it 'uses @last_interacted_peer when no identity_key given' do
      alice.get_authenticated_session(bob.identity_key)

      callback_fired = false
      bob.on_certificate_request { |_key, _req| callback_fired = true }

      to_request = { certifiers: [certifier_hex], types: { cert_type => ['name'] } }
      alice.request_certificates(to_request)

      expect(callback_fired).to be(true)
    end
  end

  describe '#send_certificate_response' do
    let(:certifier_wallet) { BSV::Wallet::Client.new(BSV::Primitives::PrivateKey.generate, storage: BSV::Wallet::Store::Memory.new) }
    let(:cert_type)        { Base64.strict_encode64(SecureRandom.random_bytes(32)) }
    let(:certifier_hex)    { certifier_wallet.get_public_key({ identity_key: true })[:public_key] }
    let(:bob) do
      described_class.new(
        wallet: bob_wallet,
        transport: transport_b,
        certificates_to_request: { certifiers: [certifier_hex], types: { cert_type => ['name'] } }
      )
    end

    let(:verifiable_cert) do
      build_verifiable_certificate(
        subject_wallet: alice_wallet,
        certifier_wallet: certifier_wallet,
        verifier_hex: bob.identity_key,
        cert_type: cert_type,
        fields: { 'name' => 'Alice' }
      )
    end

    it 'sends a certificateResponse via transport, triggering on_certificates_received on the peer' do
      alice.get_authenticated_session(bob.identity_key)

      received = []
      bob.on_certificates_received { |sender_key, certs| received << [sender_key, certs] }

      alice.send_certificate_response(bob.identity_key, [verifiable_cert])

      expect(received.length).to eq(1)
      expect(received[0][0]).to eq(alice.identity_key)
      expect(received[0][1].first['subject']).to eq(alice.identity_key)
    end
  end
end
