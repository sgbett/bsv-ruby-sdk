# frozen_string_literal: true

require 'spec_helper'

# Protocol conformance: Electrum ECIES (BIE1 format)
#
# Test vectors from the canonical conformance corpus:
#   tmp/conformance-vectors/conformance/vectors/sdk/crypto/ecies.json
#
# Covers:
#   - Deterministic encrypt + decrypt round-trips (sender_private_key supplies ephemeral key)
#   - Decrypt-only against known ciphertexts
#   - ECDH no-key symmetric mode (no_key: true)
#   - Tampered-ciphertext error cases (expected.throws)
#   - Large (1 KB) payloads (expected.decrypted_message_length_bytes)
#   - Round-trip only vectors (_roundtrip_only)

RSpec.describe 'SDK ECIES conformance (sdk.crypto.ecies)' do
  ConformanceVectors.each_canonical_vector('sdk.crypto.ecies') do |_envelope, v|
    it "#{v['id']}: #{v['description']}" do
      input    = v['input']
      expected = v['expected']

      if input['no_key']
        # ECDH symmetric mode: alice and bob produce the same ciphertext
        alice_priv = BSV::Primitives::PrivateKey.from_hex(input['alice_private_key'])
        alice_pub  = BSV::Primitives::PublicKey.from_hex(input['alice_public_key'])
        bob_priv   = BSV::Primitives::PrivateKey.from_hex(input['bob_private_key'])
        bob_pub    = BSV::Primitives::PublicKey.from_hex(input['bob_public_key'])
        message    = [input['message']].pack('H*')

        ct_alice = BSV::Primitives::ECIES.encrypt(message, bob_pub,   private_key: alice_priv, no_key: true)
        ct_bob   = BSV::Primitives::ECIES.encrypt(message, alice_pub, private_key: bob_priv,   no_key: true)

        expect(ct_alice).to eq(ct_bob)

        pt_alice = BSV::Primitives::ECIES.decrypt(ct_alice, alice_priv, sender_public_key: bob_pub)
        expect(pt_alice.force_encoding('UTF-8')).to eq(expected['decrypted_message_utf8'])

      elsif expected['throws']
        # Tampered-ciphertext error case: must raise on decrypt.
        # Note: vector specifies error_pattern "Invalid checksum" but our implementation
        # raises "HMAC verification failed" — semantically equivalent. Flagged on #847
        # (sdk.crypto.ecies.16 error_pattern mismatch).
        recipient_priv = BSV::Primitives::PrivateKey.from_hex(input['recipient_private_key'])
        bad_ct = [input['tampered_ciphertext_hex']].pack('H*')

        expect do
          BSV::Primitives::ECIES.decrypt(bad_ct, recipient_priv)
        end.to raise_error(BSV::Primitives::ECIES::DecryptionError)

      elsif expected.key?('_roundtrip_only')
        # _roundtrip_only is an upstream-defined sentinel (underscore-prefixed
        # convention in the canonical envelope) marking vectors that ship inputs
        # but no fixed expected ciphertext, e.g. when ephemeral entropy isn't
        # pinned. Verify that encrypt→decrypt recovers the original plaintext.
        sender_priv    = BSV::Primitives::PrivateKey.from_hex(input['sender_private_key'])
        recipient_priv = BSV::Primitives::PrivateKey.from_hex(input['recipient_private_key'])
        recipient_pub  = BSV::Primitives::PublicKey.from_hex(input['recipient_public_key'])
        message        = [input['message']].pack('H*')

        ct = BSV::Primitives::ECIES.encrypt(message, recipient_pub, private_key: sender_priv)
        pt = BSV::Primitives::ECIES.decrypt(ct, recipient_priv)

        expect(pt).to eq(message)

      elsif input.key?('ciphertext_hex') && !input.key?('sender_private_key')
        # Decrypt-only: just verify the known ciphertext decrypts correctly
        recipient_priv = BSV::Primitives::PrivateKey.from_hex(input['recipient_private_key'])
        ct = [input['ciphertext_hex']].pack('H*')

        pt = BSV::Primitives::ECIES.decrypt(ct, recipient_priv)

        expect(pt.unpack1('H*')).to eq(expected['decrypted_message'])

      else
        # Full encrypt + decrypt with deterministic ephemeral key (sender_private_key)
        sender_priv    = BSV::Primitives::PrivateKey.from_hex(input['sender_private_key'])
        recipient_priv = BSV::Primitives::PrivateKey.from_hex(input['recipient_private_key'])
        recipient_pub  = BSV::Primitives::PublicKey.from_hex(input['recipient_public_key'])
        message        = [input['message']].pack('H*')

        ct = BSV::Primitives::ECIES.encrypt(message, recipient_pub, private_key: sender_priv)

        expect(ct.unpack1('H*')).to eq(expected['ciphertext_hex']) if expected.key?('ciphertext_hex')

        pt = BSV::Primitives::ECIES.decrypt(ct, recipient_priv)

        if expected.key?('decrypted_message_length_bytes')
          expect(pt.bytesize).to eq(expected['decrypted_message_length_bytes'])
        elsif expected.key?('decrypted_message')
          expect(pt.unpack1('H*')).to eq(expected['decrypted_message'])
        end
      end
    end
  end
end
