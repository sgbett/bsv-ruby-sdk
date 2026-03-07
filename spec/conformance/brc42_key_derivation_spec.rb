# frozen_string_literal: true

require 'spec_helper'

# Protocol conformance: BRC-42 key derivation
#
# Test vectors from the BRC-42 specification:
#   https://github.com/bitcoin-sv/BRCs/blob/master/key-derivation/0042.md#test-vectors
#
# Cross-validates against all three reference SDKs:
#   TS SDK:  src/primitives/__tests/PrivateKey.test.ts (deriveChild)
#   Go SDK:  primitives/ec/privatekey_test.go (TestDeriveChild)
#   Python:  tests/test_keys.py (test_brc42)

RSpec.describe BSV::Primitives::PrivateKey do # rubocop:disable RSpec/MultipleDescribes
  describe 'BRC-42 PrivateKey#derive_child — spec vectors (all SDKs)' do
    # Official BRC-42 private key derivation test vectors
    [
      {
        sender_pub: '033f9160df035156f1c48e75eae99914fa1a1546bec19781e8eddb900200bff9d1',
        recipient_priv: '6a1751169c111b4667a6539ee1be6b7cd9f6e9c8fe011a5f2fe31e03a15e0ede',
        invoice: 'f3WCaUmnN9U=',
        expected: '761656715bbfa172f8f9f58f5af95d9d0dfd69014cfdcacc9a245a10ff8893ef'
      },
      {
        sender_pub: '027775fa43959548497eb510541ac34b01d5ee9ea768de74244a4a25f7b60fae8d',
        recipient_priv: 'cab2500e206f31bc18a8af9d6f44f0b9a208c32d5cca2b22acfe9d1a213b2f36',
        invoice: '2Ska++APzEc=',
        expected: '09f2b48bd75f4da6429ac70b5dce863d5ed2b350b6f2119af5626914bdb7c276'
      },
      {
        sender_pub: '0338d2e0d12ba645578b0955026ee7554889ae4c530bd7a3b6f688233d763e169f',
        recipient_priv: '7a66d0896f2c4c2c9ac55670c71a9bc1bdbdfb4e8786ee5137cea1d0a05b6f20',
        invoice: 'cN/yQ7+k7pg=',
        expected: '7114cd9afd1eade02f76703cc976c241246a2f26f5c4b7a3a0150ecc745da9f0'
      },
      {
        sender_pub: '02830212a32a47e68b98d477000bde08cb916f4d44ef49d47ccd4918d9aaabe9c8',
        recipient_priv: '6e8c3da5f2fb0306a88d6bcd427cbfba0b9c7f4c930c43122a973d620ffa3036',
        invoice: 'm2/QAsmwaA4=',
        expected: 'f1d6fb05da1225feeddd1cf4100128afe09c3c1aadbffbd5c8bd10d329ef8f40'
      },
      {
        sender_pub: '03f20a7e71c4b276753969e8b7e8b67e2dbafc3958d66ecba98dedc60a6615336d',
        recipient_priv: 'e9d174eff5708a0a41b32624f9b9cc97ef08f8931ed188ee58d5390cad2bf68e',
        invoice: 'jgpUIjWFlVQ=',
        expected: 'c5677c533f17c30f79a40744b18085632b262c0c13d87f3848c385f1389f79a6'
      }
    ].each_with_index do |v, i|
      it "vector #{i + 1}: invoice #{v[:invoice]}" do
        sender_pub = BSV::Primitives::PublicKey.from_hex(v[:sender_pub])
        recipient_priv = described_class.from_hex(v[:recipient_priv])

        derived = recipient_priv.derive_child(sender_pub, v[:invoice])

        expect(derived.to_hex).to eq(v[:expected])
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
  describe 'BRC-42 PublicKey#derive_child — spec vectors (all SDKs)' do
    # Official BRC-42 public key derivation test vectors
    [
      {
        sender_priv: '583755110a8c059de5cd81b8a04e1be884c46083ade3f779c1e022f6f89da94c',
        recipient_pub: '02c0c1e1a1f7d247827d1bcf399f0ef2deef7695c322fd91a01a91378f101b6ffc',
        invoice: 'IBioA4D/OaE=',
        expected: '03c1bf5baadee39721ae8c9882b3cf324f0bf3b9eb3fc1b8af8089ca7a7c2e669f'
      },
      {
        sender_priv: '2c378b43d887d72200639890c11d79e8f22728d032a5733ba3d7be623d1bb118',
        recipient_pub: '039a9da906ecb8ced5c87971e9c2e7c921e66ad450fd4fc0a7d569fdb5bede8e0f',
        invoice: 'PWYuo9PDKvI=',
        expected: '0398cdf4b56a3b2e106224ff3be5253afd5b72de735d647831be51c713c9077848'
      },
      {
        sender_priv: 'd5a5f70b373ce164998dff7ecd93260d7e80356d3d10abf928fb267f0a6c7be6',
        recipient_pub: '02745623f4e5de046b6ab59ce837efa1a959a8f28286ce9154a4781ec033b85029',
        invoice: 'X9pnS+bByrM=',
        expected: '0273eec9380c1a11c5a905e86c2d036e70cbefd8991d9a0cfca671f5e0bbea4a3c'
      },
      {
        sender_priv: '46cd68165fd5d12d2d6519b02feb3f4d9c083109de1bfaa2b5c4836ba717523c',
        recipient_pub: '031e18bb0bbd3162b886007c55214c3c952bb2ae6c33dd06f57d891a60976003b1',
        invoice: '+ktmYRHv3uQ=',
        expected: '034c5c6bf2e52e8de8b2eb75883090ed7d1db234270907f1b0d1c2de1ddee5005d'
      }
    ].each_with_index do |v, i|
      it "vector #{i + 1}: invoice #{v[:invoice]}" do
        sender_priv = BSV::Primitives::PrivateKey.from_hex(v[:sender_priv])
        recipient_pub = described_class.from_hex(v[:recipient_pub])

        derived = recipient_pub.derive_child(sender_priv, v[:invoice])

        expect(derived.to_hex).to eq(v[:expected])
      end
    end
  end
end
