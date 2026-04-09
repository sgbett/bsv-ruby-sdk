# frozen_string_literal: true

require 'spec_helper'

# Protocol conformance: BRC-42 key derivation
#
# Test vectors from the BRC-42 specification:
#   https://github.com/bitcoin-sv/BRCs/blob/master/key-derivation/0042.md#test-vectors
#
# Vectors are vendored verbatim from go-sdk. See
# `spec/conformance/vectors/README.md` for provenance.
#
# Cross-validates against all three reference SDKs:
#   TS SDK:  src/primitives/__tests/PrivateKey.test.ts (deriveChild)
#   Go SDK:  primitives/ec/privatekey_test.go (TestDeriveChild)
#   Python:  tests/test_keys.py (test_brc42)

RSpec.describe BSV::Primitives::PrivateKey do # rubocop:disable RSpec/MultipleDescribes
  describe 'BRC-42 PrivateKey#derive_child — canonical vectors' do
    ConformanceVectors.load('BRC42.private.vectors.json').each_with_index do |v, i|
      it "vector #{i + 1}: invoice #{v['invoiceNumber']}" do
        sender_pub = BSV::Primitives::PublicKey.from_hex(v['senderPublicKey'])
        recipient_priv = described_class.from_hex(v['recipientPrivateKey'])

        derived = recipient_priv.derive_child(sender_pub, v['invoiceNumber'])

        expect(derived.to_hex).to eq(v['privateKey'])
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
    ConformanceVectors.load('BRC42.public.vectors.json').each_with_index do |v, i|
      it "vector #{i + 1}: invoice #{v['invoiceNumber']}" do
        sender_priv = BSV::Primitives::PrivateKey.from_hex(v['senderPrivateKey'])
        recipient_pub = described_class.from_hex(v['recipientPublicKey'])

        derived = recipient_pub.derive_child(sender_priv, v['invoiceNumber'])

        expect(derived.to_hex).to eq(v['publicKey'])
      end
    end
  end
end
