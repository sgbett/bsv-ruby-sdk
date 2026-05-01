# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Auth::SessionManager do
  subject(:manager) { described_class.new }

  let(:session_nonce) { 'nonce-abc' }
  let(:peer_key)      { "02#{'ab' * 32}" }

  def build_session(nonce: session_nonce, peer_identity_key: nil, authenticated: false)
    s = BSV::Auth::PeerSession.new(session_nonce: nonce)
    s.peer_identity_key = peer_identity_key if peer_identity_key
    s.is_authenticated  = authenticated
    s
  end

  describe '#add_session / #get_session' do
    it 'stores and retrieves a session by session_nonce' do
      session = build_session
      manager.add_session(session)
      expect(manager.get_session(session_nonce)).to equal(session)
    end

    it 'returns nil for an unknown nonce' do
      expect(manager.get_session('unknown-nonce')).to be_nil
    end

    it 'indexes by peer_identity_key when present' do
      session = build_session(peer_identity_key: peer_key)
      manager.add_session(session)
      expect(manager.get_session(peer_key)).to equal(session)
    end

    it 'returns nil when looking up an unknown peer_identity_key' do
      expect(manager.get_session(peer_key)).to be_nil
    end

    it 'raises ArgumentError when session_nonce is empty' do
      session = build_session(nonce: '')
      expect { manager.add_session(session) }.to raise_error(ArgumentError, /session_nonce is required/)
    end
  end

  describe '#update_session' do
    it 'reflects updated attributes after update_session' do
      session = build_session(peer_identity_key: peer_key)
      manager.add_session(session)

      session.is_authenticated = true
      manager.update_session(session)

      retrieved = manager.get_session(session_nonce)
      expect(retrieved.authenticated?).to be(true)
    end

    it 'updates the secondary identity-key index when peer key changes' do
      session = build_session
      manager.add_session(session)

      session.peer_identity_key = peer_key
      manager.update_session(session)

      expect(manager.get_session(peer_key)).to equal(session)
    end
  end

  describe '#remove_session' do
    it 'removes the session so it cannot be retrieved by nonce' do
      session = build_session
      manager.add_session(session)
      manager.remove_session(session)
      expect(manager.get_session(session_nonce)).to be_nil
    end

    it 'removes the session from the identity-key index too' do
      session = build_session(peer_identity_key: peer_key)
      manager.add_session(session)
      manager.remove_session(session)
      expect(manager.get_session(peer_key)).to be_nil
    end

    it 'is idempotent for an unknown session' do
      session = build_session
      expect { manager.remove_session(session) }.not_to raise_error
    end
  end

  describe '#session?' do
    it 'returns true after a session is added' do
      manager.add_session(build_session)
      expect(manager.session?(session_nonce)).to be(true)
    end

    it 'returns false before any session is added' do
      expect(manager.session?(session_nonce)).to be(false)
    end

    it 'returns false after the session is removed' do
      session = build_session
      manager.add_session(session)
      manager.remove_session(session)
      expect(manager.session?(session_nonce)).to be(false)
    end
  end

  describe 'multiple sessions per peer identity key' do
    it 'returns the most recently updated session when looking up by identity key' do
      session_a = build_session(nonce: 'nonce-a', peer_identity_key: peer_key)
      session_b = build_session(nonce: 'nonce-b', peer_identity_key: peer_key)

      session_a.last_update = 1000
      session_b.last_update = 2000

      manager.add_session(session_a)
      manager.add_session(session_b)

      expect(manager.get_session(peer_key)).to equal(session_b)
    end
  end

  describe 'authenticated? helper (via Peer)' do
    it 'returns false when no session exists' do
      expect(manager.get_session('no-such-nonce')).to be_nil
    end

    it 'reflects authentication state on the session' do
      session = build_session(authenticated: true)
      manager.add_session(session)
      expect(manager.get_session(session_nonce).authenticated?).to be(true)
    end
  end
end
