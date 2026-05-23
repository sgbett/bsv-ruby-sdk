# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/paired_transport'

# End-to-end integration tests for the BSV Auth peer protocol.
#
# These tests exercise multi-component lifecycle scenarios — certificate issuance,
# exchange, validation, and high-level session management. They complement the unit
# specs in peer_spec.rb, which cover individual methods in isolation.
#
# All tests use PairedTransport for realistic message delivery (no direct method calls).
# Deterministic keys are used for reproducibility.

RSpec.describe 'BSV::Auth::Peer integration' do # rubocop:disable RSpec/DescribeClass
  # Deterministic keys — matching the pattern used in certificate_integration_spec.rb
  let(:alice_key)     { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(10)) }
  let(:bob_key)       { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(11)) }
  let(:carol_key)     { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(12)) }
  let(:certifier_key) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(22)) }

  let(:alice_wallet)     { BSV::Wallet::ProtoWallet.new(alice_key) }
  let(:bob_wallet)       { BSV::Wallet::ProtoWallet.new(bob_key) }
  let(:carol_wallet)     { BSV::Wallet::ProtoWallet.new(carol_key) }
  let(:certifier_wallet) { BSV::Wallet::ProtoWallet.new(certifier_key) }

  let(:cert_type)   { Base64.strict_encode64("\x01" * 32) }
  let(:serial)      { Base64.strict_encode64("\x02" * 32) }

  # --- Shared helper: issue and build a VerifiableCertificate ---

  def issue_verifiable_certificate(subject_wallet:, certifier_wallet:, verifier_hex:, cert_type:, fields:)
    master_cert = BSV::Auth::MasterCertificate.issue_certificate_for_subject(
      certifier_wallet,
      subject_wallet.get_public_key(identity_key: true)[:public_key],
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

  # --- Scenario 1: Full certificate exchange lifecycle ---

  describe 'Scenario 1: full certificate exchange lifecycle' do
    # Bob requires Alice to present a certificate from certifier_wallet.
    let(:requested_certs) do
      { certifiers: [certifier_wallet.get_public_key(identity_key: true)[:public_key]],
        types: { cert_type => ['name'] } }
    end

    let(:transport_a) { PairedTransport.new }
    let(:transport_b) { PairedTransport.new }

    let(:alice) { BSV::Auth::Peer.new(wallet: alice_wallet, transport: transport_a) }
    let(:bob) do
      BSV::Auth::Peer.new(wallet: bob_wallet, transport: transport_b,
                          certificates_to_request: requested_certs)
    end

    before do
      alice
      bob
      transport_a.partner = transport_b
      transport_b.partner = transport_a
    end

    it 'delivers the general message and marks certificates_validated on the session' do
      received_payload = nil
      bob.on_general_message { |_key, payload| received_payload = payload }

      certs_received_by_bob = nil
      bob.on_certificates_received { |_key, certs| certs_received_by_bob = certs }

      # Alice registers an on_certificate_request callback that:
      # (a) builds a verifier keyring for Bob
      # (b) constructs a VerifiableCertificate
      # (c) calls send_certificate_response
      alice.on_certificate_request do |requester_key, _requested|
        vc = issue_verifiable_certificate(
          subject_wallet: alice_wallet,
          certifier_wallet: certifier_wallet,
          verifier_hex: requester_key,
          cert_type: cert_type,
          fields: { 'name' => 'Alice' }
        )
        alice.send_certificate_response(requester_key, [vc])
      end

      # to_peer triggers the handshake; Alice's callback fires during the handshake
      # to satisfy Bob's certificate requirement
      payload = 'Hello, Bob!'.bytes
      alice.to_peer(payload, bob.identity_key)

      expect(received_payload).to eq(payload)
      expect(certs_received_by_bob).to be_an(Array)
      expect(certs_received_by_bob).not_to be_empty

      # Confirm Bob's session has certificates_validated = true
      bob_session = bob.session_manager.get_session(alice.identity_key)
      expect(bob_session).not_to be_nil
      expect(bob_session.certificates_validated).to be(true)
    end
  end

  # --- Scenario 2: Dynamic certificate request post-handshake ---

  describe 'Scenario 2: dynamic certificate request post-handshake' do
    let(:transport_a) { PairedTransport.new }
    let(:transport_b) { PairedTransport.new }

    let(:alice) { BSV::Auth::Peer.new(wallet: alice_wallet, transport: transport_a) }
    let(:bob)   { BSV::Auth::Peer.new(wallet: bob_wallet,   transport: transport_b) }

    before do
      alice
      bob
      transport_a.partner = transport_b
      transport_b.partner = transport_a
    end

    it 'allows Bob to request certificates from Alice after the initial handshake' do
      # Establish session — no cert requirements on either side
      alice.to_peer('Hi'.bytes, bob.identity_key)

      received_certs = nil
      decrypted_name = nil

      bob.on_certificates_received do |_key, certs|
        received_certs = certs
        # Attempt decryption using Bob's wallet
        cert_hash = certs.first
        vc = BSV::Auth::VerifiableCertificate.from_hash(cert_hash)
        vc.decrypt_fields(bob_wallet)
        decrypted_name = vc.decrypted_fields['name']
      end

      # Alice registers a cert request callback that will fire when Bob calls request_certificates
      alice.on_certificate_request do |requester_key, _requested|
        vc = issue_verifiable_certificate(
          subject_wallet: alice_wallet,
          certifier_wallet: certifier_wallet,
          verifier_hex: requester_key,
          cert_type: cert_type,
          fields: { 'name' => 'Alice' }
        )
        alice.send_certificate_response(requester_key, [vc])
      end

      certifier_hex = certifier_wallet.get_public_key(identity_key: true)[:public_key]
      bob.request_certificates(
        { certifiers: [certifier_hex], types: { cert_type => ['name'] } },
        alice.identity_key
      )

      expect(received_certs).not_to be_nil
      expect(received_certs).not_to be_empty
      expect(decrypted_name).to eq('Alice')
    end
  end

  # --- Scenario 3: Bidirectional certificate exchange ---
  #
  # Bidirectional cert exchange works as follows:
  # - Bob requires Alice's certs (via certificates_to_request)
  # - Alice's on_certificate_request callback fires during handshake and sends certs → Bob validates
  # - After handshake, Alice calls request_certificates to get Bob's certs
  # - Bob's on_certificate_request fires → Bob sends certs → Alice validates
  # Both peers end up with certificates_validated = true.

  describe 'Scenario 3: bidirectional certificate exchange' do
    let(:certifier_key2) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(33)) }
    let(:certifier_wallet2) { BSV::Wallet::ProtoWallet.new(certifier_key2) }

    let(:cert_type2) { Base64.strict_encode64("\x03" * 32) }

    # Bob requires Alice's certs
    let(:requested_by_bob) do
      { certifiers: [certifier_wallet.get_public_key(identity_key: true)[:public_key]],
        types: { cert_type => ['name'] } }
    end

    let(:transport_a) { PairedTransport.new }
    let(:transport_b) { PairedTransport.new }

    let(:alice) { BSV::Auth::Peer.new(wallet: alice_wallet, transport: transport_a) }
    let(:bob) do
      BSV::Auth::Peer.new(wallet: bob_wallet, transport: transport_b,
                          certificates_to_request: requested_by_bob)
    end

    before do
      alice
      bob
      transport_a.partner = transport_b
      transport_b.partner = transport_a
    end

    it 'both peers receive validated certificates from each other' do
      alice_certs_received = nil
      bob_certs_received   = nil

      alice.on_certificates_received { |_k, certs| alice_certs_received = certs }
      bob.on_certificates_received   { |_k, certs| bob_certs_received   = certs }

      # Alice responds to Bob's cert request during handshake
      alice.on_certificate_request do |requester_key, _req|
        vc = issue_verifiable_certificate(
          subject_wallet: alice_wallet,
          certifier_wallet: certifier_wallet,
          verifier_hex: requester_key,
          cert_type: cert_type,
          fields: { 'name' => 'Alice' }
        )
        alice.send_certificate_response(requester_key, [vc])
      end

      # Bob responds when Alice requests certs from him post-handshake
      bob.on_certificate_request do |requester_key, _req|
        vc = issue_verifiable_certificate(
          subject_wallet: bob_wallet,
          certifier_wallet: certifier_wallet2,
          verifier_hex: requester_key,
          cert_type: cert_type2,
          fields: { 'role' => 'admin' }
        )
        bob.send_certificate_response(requester_key, [vc])
      end

      # Handshake + Alice satisfies Bob's cert requirement
      alice.to_peer('ping'.bytes, bob.identity_key)

      bob_session = bob.session_manager.get_session(alice.identity_key)
      expect(bob_session.certificates_validated).to be(true)
      expect(bob_certs_received).not_to be_nil

      # Alice now requests certs from Bob post-handshake
      certifier2_hex = certifier_wallet2.get_public_key(identity_key: true)[:public_key]
      alice.request_certificates(
        { certifiers: [certifier2_hex], types: { cert_type2 => ['role'] } },
        bob.identity_key
      )

      alice_session = alice.session_manager.get_session(bob.identity_key)
      expect(alice_session.certificates_validated).to be(true)
      expect(alice_certs_received).not_to be_nil

      # Verify decrypted content
      vc = BSV::Auth::VerifiableCertificate.from_hash(alice_certs_received.first)
      decrypted = vc.decrypt_fields(alice_wallet)
      expect(decrypted['role']).to eq('admin')
    end
  end

  # --- Scenario 4: Certificate validation failure — wrong subject ---

  describe 'Scenario 4: certificate validation failure — wrong subject' do
    let(:eve_key)    { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(99)) }
    let(:eve_wallet) { BSV::Wallet::ProtoWallet.new(eve_key) }

    it 'raises AuthError when the certificate subject does not match the sender' do
      # Issue a certificate for Eve, then present it as if Alice sent it
      vc = issue_verifiable_certificate(
        subject_wallet: eve_wallet, # certificate subject is Eve
        certifier_wallet: certifier_wallet,
        verifier_hex: bob_wallet.get_public_key(identity_key: true)[:public_key],
        cert_type: cert_type,
        fields: { 'name' => 'Eve' }
      )

      # Build a fake message claiming to be from Alice but carrying Eve's certificate
      message = {
        identity_key: alice_wallet.get_public_key(identity_key: true)[:public_key],
        certificates: [vc.to_h]
      }

      requested = {
        certifiers: [certifier_wallet.get_public_key(identity_key: true)[:public_key]],
        types: { cert_type => ['name'] }
      }

      expect do
        BSV::Auth.validate_certificates(bob_wallet, message, requested)
      end.to raise_error(BSV::Auth::AuthError, /subject.*is not the same as.*sender/i)
    end
  end

  # --- Scenario 5: to_peer rejects when certificates not validated ---

  describe 'Scenario 5: to_peer rejects when certificates not validated' do
    let(:requested_certs) do
      { certifiers: [certifier_wallet.get_public_key(identity_key: true)[:public_key]],
        types: { cert_type => ['name'] } }
    end

    let(:transport_a) { PairedTransport.new }
    let(:transport_b) { PairedTransport.new }

    # Bob requires certificates from Alice, but Alice registers no cert callback
    let(:alice) { BSV::Auth::Peer.new(wallet: alice_wallet, transport: transport_a) }
    let(:bob) do
      BSV::Auth::Peer.new(wallet: bob_wallet, transport: transport_b,
                          certificates_to_request: requested_certs)
    end

    before do
      alice
      bob
      transport_a.partner = transport_b
      transport_b.partner = transport_a
    end

    it 'raises AuthError when Bob tries to send after handshake without certificates validated' do
      # Alice completes the handshake but never satisfies Bob's cert requirement.
      # Bob can handshake but not send a general message.
      alice.to_peer('trigger handshake'.bytes, bob.identity_key)

      bob_session = bob.session_manager.get_session(alice.identity_key)
      # Bob's session requires certs but they were never validated
      expect(bob_session.certificates_required).to be(true)
      expect(bob_session.certificates_validated).to be(false)

      expect do
        bob.to_peer('blocked message'.bytes, alice.identity_key)
      end.to raise_error(BSV::Auth::AuthError, /certificate validation/i)
    end
  end

  # --- Scenario 6: Multiple peers with independent sessions ---

  describe 'Scenario 6: multiple peers — independent sessions' do
    let(:transport_ab_a) { PairedTransport.new }
    let(:transport_ab_b) { PairedTransport.new }
    let(:transport_ac_a) { PairedTransport.new }
    let(:transport_ac_c) { PairedTransport.new }

    # Alice has two transports: one to Bob, one to Carol
    let(:alice_to_bob)   { BSV::Auth::Peer.new(wallet: alice_wallet, transport: transport_ab_a) }
    let(:bob)            { BSV::Auth::Peer.new(wallet: bob_wallet,   transport: transport_ab_b) }
    let(:alice_to_carol) { BSV::Auth::Peer.new(wallet: alice_wallet, transport: transport_ac_a) }
    let(:carol)          { BSV::Auth::Peer.new(wallet: carol_wallet, transport: transport_ac_c) }

    before do
      alice_to_bob
      bob
      alice_to_carol
      carol
      transport_ab_a.partner = transport_ab_b
      transport_ab_b.partner = transport_ab_a
      transport_ac_a.partner = transport_ac_c
      transport_ac_c.partner = transport_ac_a
    end

    it 'sessions are independent and do not cross-contaminate' do
      bob_received   = []
      carol_received = []

      bob.on_general_message   { |_k, payload| bob_received   << payload }
      carol.on_general_message { |_k, payload| carol_received << payload }

      alice_to_bob.to_peer('to bob'.bytes, bob.identity_key)
      alice_to_carol.to_peer('to carol'.bytes, carol.identity_key)

      expect(bob_received).to eq(['to bob'.bytes])
      expect(carol_received).to eq(['to carol'.bytes])
    end

    it 'last_interacted_peer tracks the most recent peer separately for each connection' do
      alice_to_bob.to_peer('ping'.bytes, bob.identity_key)
      expect(alice_to_bob.last_interacted_peer).to eq(bob.identity_key)

      alice_to_carol.to_peer('ping'.bytes, carol.identity_key)
      expect(alice_to_carol.last_interacted_peer).to eq(carol.identity_key)
    end

    it 'to_peer without identity_key uses last_interacted_peer' do
      carol_received = []
      carol.on_general_message { |_k, payload| carol_received << payload }

      # First message sets last_interacted_peer
      alice_to_carol.to_peer('first'.bytes, carol.identity_key)

      # Second message omits identity_key — should go to Carol via last_interacted_peer
      alice_to_carol.to_peer('second'.bytes)

      expect(carol_received).to eq(['first'.bytes, 'second'.bytes])
    end
  end

  # --- Scenario 7: Session reuse ---

  describe 'Scenario 7: session reuse — second to_peer uses existing session' do
    let(:transport_a) { PairedTransport.new }
    let(:transport_b) { PairedTransport.new }

    let(:alice) { BSV::Auth::Peer.new(wallet: alice_wallet, transport: transport_a) }
    let(:bob)   { BSV::Auth::Peer.new(wallet: bob_wallet,   transport: transport_b) }

    before do
      alice
      bob
      transport_a.partner = transport_b
      transport_b.partner = transport_a
    end

    it 'Bob receives both messages and no new handshake is created on the second call' do
      received = []
      bob.on_general_message { |_k, payload| received << payload }

      alice.to_peer('message 1'.bytes, bob.identity_key)
      alice.to_peer('message 2'.bytes, bob.identity_key)

      expect(received).to eq(['message 1'.bytes, 'message 2'.bytes])
    end

    it 'only one session exists in Alice\'s session manager after two to_peer calls' do
      alice.to_peer('msg1'.bytes, bob.identity_key)
      alice.to_peer('msg2'.bytes, bob.identity_key)

      # Alice should have exactly one session with Bob
      sessions = alice.session_manager.instance_variable_get(:@by_nonce)
      expect(sessions.size).to eq(1)
    end
  end

  # --- Scenario 8: Handshake timeout ---

  describe 'Scenario 8: handshake timeout' do
    it 'raises AuthError when the transport does not deliver the response' do
      # A "black hole" transport: accepts sends but never delivers to a partner
      black_hole = Class.new do
        include BSV::Auth::Transport

        def send(_message)
          # intentionally drops all messages
        end

        def on_data(&)
          # never delivers
        end
      end.new

      peer = BSV::Auth::Peer.new(wallet: alice_wallet, transport: black_hole,
                                 handshake_timeout: 0.05)

      expect do
        peer.to_peer('hello'.bytes, bob_wallet.get_public_key(identity_key: true)[:public_key])
      end.to raise_error(BSV::Auth::AuthError, /Handshake timed out/)
    end
  end

  # --- Scenario 9: Transport send failure cleans up queue ---

  describe 'Scenario 9: transport send failure cleans up handshake queue' do
    it 'propagates the error and leaves no orphaned queue entry' do
      failing_transport = Class.new do
        include BSV::Auth::Transport

        def send(_message)
          raise 'transport unavailable'
        end

        def on_data(&)
          # no-op
        end
      end.new

      peer = BSV::Auth::Peer.new(wallet: alice_wallet, transport: failing_transport)

      expect do
        peer.to_peer('hello'.bytes, bob_wallet.get_public_key(identity_key: true)[:public_key])
      end.to raise_error(RuntimeError, /transport unavailable/)

      # Queue should be cleaned up — no orphaned entries
      queues = peer.instance_variable_get(:@handshake_queues)
      expect(queues).to be_empty
    end
  end

  # --- Scenario 10: Certificates in initial handshake (both sides) ---

  describe 'Scenario 10: certificates included in initialResponse during handshake' do
    let(:requested_certs) do
      { certifiers: [certifier_wallet.get_public_key(identity_key: true)[:public_key]],
        types: { cert_type => ['name'] } }
    end

    let(:transport_a) { PairedTransport.new }
    let(:transport_b) { PairedTransport.new }

    # Bob requests certs from Alice and Alice responds via callback during the handshake
    let(:alice) { BSV::Auth::Peer.new(wallet: alice_wallet, transport: transport_a) }
    let(:bob) do
      BSV::Auth::Peer.new(wallet: bob_wallet, transport: transport_b,
                          certificates_to_request: requested_certs)
    end

    before do
      alice
      bob
      transport_a.partner = transport_b
      transport_b.partner = transport_a
    end

    it 'Alice responds to cert request in initialRequest callback and Bob validates during handshake' do
      certs_received_by_bob = nil
      bob.on_certificates_received { |_k, certs| certs_received_by_bob = certs }

      # Alice's callback fires when Bob's initialRequest includes requested_certificates
      alice.on_certificate_request do |requester_key, _requested|
        vc = issue_verifiable_certificate(
          subject_wallet: alice_wallet,
          certifier_wallet: certifier_wallet,
          verifier_hex: requester_key,
          cert_type: cert_type,
          fields: { 'name' => 'Alice' }
        )
        alice.send_certificate_response(requester_key, [vc])
      end

      # Trigger handshake by Alice connecting to Bob
      alice.to_peer('initial message'.bytes, bob.identity_key)

      expect(certs_received_by_bob).not_to be_nil

      # Bob's session should have certificates_validated = true now
      bob_session = bob.session_manager.get_session(alice.identity_key)
      expect(bob_session.certificates_validated).to be(true)
    end
  end

  # --- Scenario 11: Tampered certificate rejected ---

  describe 'Scenario 11: tampered certificate rejected' do
    it 'raises AuthError when the certificate signature has been tampered with' do
      vc = issue_verifiable_certificate(
        subject_wallet: alice_wallet,
        certifier_wallet: certifier_wallet,
        verifier_hex: bob_wallet.get_public_key(identity_key: true)[:public_key],
        cert_type: cert_type,
        fields: { 'name' => 'Alice' }
      )

      tampered = vc.to_h
      tampered['signature'] = tampered['signature'].dup
      # Flip a byte in the signature
      tampered['signature'][-2..-1] = (tampered['signature'][-2..].to_i(16) ^ 0xFF).to_s(16).rjust(2, '0')

      alice_key_hex = alice_wallet.get_public_key(identity_key: true)[:public_key]
      message = { identity_key: alice_key_hex, certificates: [tampered] }

      requested = {
        certifiers: [certifier_wallet.get_public_key(identity_key: true)[:public_key]],
        types: { cert_type => ['name'] }
      }

      expect do
        BSV::Auth.validate_certificates(bob_wallet, message, requested)
      end.to raise_error(BSV::Auth::AuthError)
    end
  end

  # --- Scenario 12: Wrong certifier rejected ---

  describe 'Scenario 12: wrong certifier rejected' do
    let(:rogue_certifier_key) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(77)) }
    let(:rogue_certifier_wallet) { BSV::Wallet::ProtoWallet.new(rogue_certifier_key) }

    it 'raises AuthError when the certifier is not in the requested list' do
      # Certificate issued by a rogue certifier not in Bob's trusted set
      vc = issue_verifiable_certificate(
        subject_wallet: alice_wallet,
        certifier_wallet: rogue_certifier_wallet,
        verifier_hex: bob_wallet.get_public_key(identity_key: true)[:public_key],
        cert_type: cert_type,
        fields: { 'name' => 'Alice' }
      )

      alice_key_hex = alice_wallet.get_public_key(identity_key: true)[:public_key]
      message = { identity_key: alice_key_hex, certificates: [vc.to_h] }

      trusted_certifier_hex = certifier_wallet.get_public_key(identity_key: true)[:public_key]
      requested = {
        certifiers: [trusted_certifier_hex], # only trusts certifier_wallet, not rogue
        types: { cert_type => ['name'] }
      }

      expect do
        BSV::Auth.validate_certificates(bob_wallet, message, requested)
      end.to raise_error(BSV::Auth::AuthError, /unrequested certifier/i)
    end
  end

  # --- Scenario 13: Decrypt certificate fields after exchange ---

  describe 'Scenario 13: verify actual decrypted field values after full exchange' do
    let(:requested_certs) do
      { certifiers: [certifier_wallet.get_public_key(identity_key: true)[:public_key]],
        types: { cert_type => %w[name email] } }
    end

    let(:transport_a) { PairedTransport.new }
    let(:transport_b) { PairedTransport.new }

    let(:alice) { BSV::Auth::Peer.new(wallet: alice_wallet, transport: transport_a) }
    let(:bob) do
      BSV::Auth::Peer.new(wallet: bob_wallet, transport: transport_b,
                          certificates_to_request: requested_certs)
    end

    before do
      alice
      bob
      transport_a.partner = transport_b
      transport_b.partner = transport_a
    end

    it 'Bob can decrypt all revealed fields and verifies the actual plaintext values' do
      decrypted_by_bob = nil

      bob.on_certificates_received do |_sender_key, certs|
        cert_hash = certs.first
        vc = BSV::Auth::VerifiableCertificate.from_hash(cert_hash)
        decrypted_by_bob = vc.decrypt_fields(bob_wallet)
      end

      alice.on_certificate_request do |requester_key, _requested|
        vc = issue_verifiable_certificate(
          subject_wallet: alice_wallet,
          certifier_wallet: certifier_wallet,
          verifier_hex: requester_key,
          cert_type: cert_type,
          fields: { 'name' => 'Alice Wonderland', 'email' => 'alice@example.com' }
        )
        alice.send_certificate_response(requester_key, [vc])
      end

      alice.to_peer('verify fields'.bytes, bob.identity_key)

      expect(decrypted_by_bob).not_to be_nil
      expect(decrypted_by_bob['name']).to eq('Alice Wonderland')
      expect(decrypted_by_bob['email']).to eq('alice@example.com')
    end
  end
end
