# frozen_string_literal: true

require 'spec_helper'

# Protocol conformance: BRC-42 key derivation
#
# Test vectors from the canonical conformance corpus:
#   tmp/conformance-vectors/conformance/vectors/sdk/keys/key-derivation.json
#   tmp/conformance-vectors/conformance/vectors/sdk/keys/public-key.json
#
# The private vectors are key-005..key-009 (tagged brc42/key-derivation/private).
# The public vectors are pubkey-brc42-001..005 (tagged brc42/key-derivation/public).
#
# Cross-validates against all three reference SDKs:
#   TS SDK:  src/primitives/__tests/PrivateKey.test.ts (deriveChild)
#   Go SDK:  primitives/ec/privatekey_test.go (TestDeriveChild)
#   Python:  tests/test_keys.py (test_brc42)

PRIVATE_BRC42_IDS = %w[key-005 key-006 key-007 key-008 key-009].freeze
PUBLIC_BRC42_IDS  = %w[pubkey-brc42-001 pubkey-brc42-002 pubkey-brc42-003 pubkey-brc42-004 pubkey-brc42-005].freeze

RSpec.describe BSV::Primitives::PrivateKey do # rubocop:disable RSpec/MultipleDescribes
  describe 'BRC-42 PrivateKey#derive_child — canonical vectors' do
    ConformanceVectors.each_canonical_vector('sdk.keys.key-derivation') do |_envelope, v|
      next unless PRIVATE_BRC42_IDS.include?(v['id'])

      it "#{v['id']}: invoice #{v.dig('input', 'invoice_number')}" do
        sender_pub = BSV::Primitives::PublicKey.from_hex(v.dig('input', 'sender_public_key_hex'))
        recipient_priv = described_class.from_hex(v.dig('input', 'recipient_private_key_hex'))

        derived = recipient_priv.derive_child(sender_pub, v.dig('input', 'invoice_number'))

        expect(derived.to_hex).to eq(v.dig('expected', 'derived_private_key_hex'))
      end
    end
  end

  describe 'BRC-42 derivation properties' do
    it 'key pair correspondence: derive_child private key matches derive_child public key' do
      alice = described_class.generate
      bob = described_class.generate

      child_priv = alice.derive_child(bob.public_key, 'correspondence-test')
      child_pub = alice.public_key.derive_child(bob, 'correspondence-test')

      expect(child_priv.public_key).to eq(child_pub)
    end

    it 'different invoice numbers produce different keys' do
      alice = described_class.generate
      bob = described_class.generate

      k1 = alice.derive_child(bob.public_key, 'invoice-A')
      k2 = alice.derive_child(bob.public_key, 'invoice-B')

      expect(k1.to_hex).not_to eq(k2.to_hex)
    end

    it 'derived keys are valid (non-zero, less than N)' do
      alice = described_class.generate
      bob = described_class.generate

      child = alice.derive_child(bob.public_key, 'validity-test')

      expect(child.bn).to be > OpenSSL::BN.new('0')
      expect(child.bn).to be < BSV::Primitives::Curve::N
    end

    it 'is deterministic for same inputs' do
      alice = described_class.from_hex('6a1751169c111b4667a6539ee1be6b7cd9f6e9c8fe011a5f2fe31e03a15e0ede')
      sender_pub = BSV::Primitives::PublicKey.from_hex(
        '033f9160df035156f1c48e75eae99914fa1a1546bec19781e8eddb900200bff9d1'
      )

      d1 = alice.derive_child(sender_pub, 'f3WCaUmnN9U=')
      d2 = alice.derive_child(sender_pub, 'f3WCaUmnN9U=')

      expect(d1.to_hex).to eq(d2.to_hex)
    end
  end
end

RSpec.describe BSV::Primitives::PublicKey do
  describe 'BRC-42 PublicKey#derive_child — canonical vectors' do
    ConformanceVectors.each_canonical_vector('sdk.keys.public-key') do |_envelope, v|
      next unless PUBLIC_BRC42_IDS.include?(v['id'])

      it "#{v['id']}: invoice #{v.dig('input', 'invoice_number')}" do
        sender_priv   = BSV::Primitives::PrivateKey.from_hex(v.dig('input', 'sender_private_key_hex'))
        recipient_pub = described_class.from_hex(v.dig('input', 'recipient_public_key_hex'))

        derived = recipient_pub.derive_child(sender_priv, v.dig('input', 'invoice_number'))

        expect(derived.to_hex).to eq(v.dig('expected', 'derived_public_key_hex'))
      end
    end
  end
end
