# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Auth::SessionManager do
  subject(:manager) { described_class.new }

  let(:session_nonce) { 'nonce-abc' }
  let(:peer_key)      { "02#{'ab' * 32}" }

  def build_session(nonce: session_nonce, peer_identity_key: nil, authenticated: false, last_update: nil)
    s = BSV::Auth::PeerSession.new(session_nonce: nonce)
    s.peer_identity_key = peer_identity_key if peer_identity_key
    s.is_authenticated  = authenticated
    s.last_update       = last_update unless last_update.nil?
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
      now_ms    = (Time.now.to_f * 1000).to_i
      session_a = build_session(nonce: 'nonce-a', peer_identity_key: peer_key, last_update: now_ms - 2000)
      session_b = build_session(nonce: 'nonce-b', peer_identity_key: peer_key, last_update: now_ms - 1000)

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

  describe 'TTL expiry' do
    let(:now_ms) { (Time.now.to_f * 1000).to_i }

    context 'with default TTL (3600s)' do
      it 'returns a session whose last_update is within the TTL' do
        session = build_session(last_update: now_ms)
        manager.add_session(session)
        expect(manager.get_session(session_nonce)).to equal(session)
      end

      it 'returns nil for a session past the TTL' do
        old_ms = now_ms - (3601 * 1000)
        session = build_session(last_update: old_ms)
        manager.add_session(session)
        expect(manager.get_session(session_nonce)).to be_nil
      end

      it 'removes an expired session from both indexes on get_session' do
        old_ms = now_ms - (3601 * 1000)
        session = build_session(last_update: old_ms, peer_identity_key: peer_key)
        manager.add_session(session)

        manager.get_session(session_nonce)

        expect(manager.get_session(session_nonce)).to be_nil
        expect(manager.get_session(peer_key)).to be_nil
      end
    end

    context 'with session?' do
      it 'returns false for an expired session (by nonce)' do
        old_ms = now_ms - (3601 * 1000)
        session = build_session(last_update: old_ms)
        manager.add_session(session)
        expect(manager.session?(session_nonce)).to be(false)
      end

      it 'returns false for an expired session (by identity key)' do
        old_ms = now_ms - (3601 * 1000)
        session = build_session(last_update: old_ms, peer_identity_key: peer_key)
        manager.add_session(session)
        expect(manager.session?(peer_key)).to be(false)
      end

      it 'returns true for a non-expired session' do
        session = build_session(last_update: now_ms)
        manager.add_session(session)
        expect(manager.session?(session_nonce)).to be(true)
      end
    end

    context 'with a custom TTL (60s)' do
      subject(:manager) { described_class.new(default_ttl: 60) }

      it 'returns nil after 61 seconds have elapsed' do
        old_ms = now_ms - (61 * 1000)
        session = build_session(last_update: old_ms)
        manager.add_session(session)
        expect(manager.get_session(session_nonce)).to be_nil
      end

      it 'returns the session when it is within 60 seconds' do
        recent_ms = now_ms - (59 * 1000)
        session = build_session(last_update: recent_ms)
        manager.add_session(session)
        expect(manager.get_session(session_nonce)).to equal(session)
      end
    end

    context 'with TTL disabled (default_ttl: nil)' do
      subject(:manager) { described_class.new(default_ttl: nil) }

      it 'returns a session regardless of age' do
        old_ms = now_ms - (999_999 * 1000)
        session = build_session(last_update: old_ms)
        manager.add_session(session)
        expect(manager.get_session(session_nonce)).to equal(session)
      end

      it 'returns true from session? regardless of age' do
        old_ms = now_ms - (999_999 * 1000)
        session = build_session(last_update: old_ms)
        manager.add_session(session)
        expect(manager.session?(session_nonce)).to be(true)
      end
    end

    context 'with last_update: nil' do
      it 'treats the session as expired' do
        session = build_session
        session.last_update = nil
        manager.add_session(session)
        expect(manager.get_session(session_nonce)).to be_nil
      end
    end

    context 'with last_update: 0' do
      it 'treats the session as expired' do
        session = build_session(last_update: 0)
        manager.add_session(session)
        expect(manager.get_session(session_nonce)).to be_nil
      end
    end

    context 'with mixed expired and active sessions for the same identity key' do
      it 'skips expired sessions and returns the best non-expired one' do
        old_ms    = now_ms - (3601 * 1000)
        recent_ms = now_ms

        expired = build_session(nonce: 'nonce-expired', peer_identity_key: peer_key, last_update: old_ms)
        active  = build_session(nonce: 'nonce-active',  peer_identity_key: peer_key, last_update: recent_ms)

        manager.add_session(expired)
        manager.add_session(active)

        expect(manager.get_session(peer_key)).to equal(active)
      end

      it 'returns nil when all sessions for a peer have expired' do
        old_ms = now_ms - (3601 * 1000)

        s1 = build_session(nonce: 'nonce-1', peer_identity_key: peer_key, last_update: old_ms)
        s2 = build_session(nonce: 'nonce-2', peer_identity_key: peer_key, last_update: old_ms)

        manager.add_session(s1)
        manager.add_session(s2)

        expect(manager.get_session(peer_key)).to be_nil
      end
    end
  end

  describe '#sweep_expired' do
    let(:now_ms) { (Time.now.to_f * 1000).to_i }

    it 'removes all expired sessions and returns the count' do
      old_ms = now_ms - (3601 * 1000)

      s1 = build_session(nonce: 'nonce-1', peer_identity_key: peer_key, last_update: old_ms)
      s2 = build_session(nonce: 'nonce-2', last_update: old_ms)
      s3 = build_session(nonce: 'nonce-3', last_update: now_ms)

      manager.add_session(s1)
      manager.add_session(s2)
      manager.add_session(s3)

      count = manager.sweep_expired
      expect(count).to eq(2)

      expect(manager.get_session('nonce-1')).to be_nil
      expect(manager.get_session('nonce-2')).to be_nil
      expect(manager.get_session('nonce-3')).to equal(s3)
    end

    it 'returns 0 when no sessions have expired' do
      manager.add_session(build_session(last_update: now_ms))
      expect(manager.sweep_expired).to eq(0)
    end

    it 'returns 0 when the store is empty' do
      expect(manager.sweep_expired).to eq(0)
    end

    it 'cleans up identity index entries for swept sessions' do
      old_ms = now_ms - (3601 * 1000)
      session = build_session(peer_identity_key: peer_key, last_update: old_ms)
      manager.add_session(session)
      manager.sweep_expired
      expect(manager.get_session(peer_key)).to be_nil
    end

    it 'does nothing when TTL is disabled' do
      manager_no_ttl = described_class.new(default_ttl: nil)
      old_ms = now_ms - (999_999 * 1000)
      session = build_session(last_update: old_ms)
      manager_no_ttl.add_session(session)
      expect(manager_no_ttl.sweep_expired).to eq(0)
    end
  end
end
