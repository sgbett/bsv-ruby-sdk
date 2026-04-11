# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Primitives::ECDSA do
  # Go SDK test vector (from Trezor/CoreBitcoin)
  let(:privkey_hex) { 'cca9fbcc1b41e5a95d369eaa6ddcff73b61a4efaa279cfc6567e8daa39cbaf50' }
  let(:privkey_bn) { OpenSSL::BN.new(privkey_hex, 16) }
  let(:pubkey_point) { BSV::Primitives::Curve.multiply_generator(privkey_bn) }

  describe '.sign' do
    it 'produces a deterministic signature matching the Go SDK test vector' do
      message_hash = BSV::Primitives::Digest.sha256('sample')
      sig = described_class.sign(message_hash, privkey_bn)

      expected_hex = '3045022100af340daf02cc15c8d5d08d7735dfe6b98a474ed373bdb5fbecf7571be52b3842' \
                     '02205009fb27f37034a9b24b707b7c6b79ca23ddef9e25f7282e8a797efe53a8f124'

      expect(sig.to_hex).to eq(expected_hex)
    end

    it 'always produces low-S signatures' do
      10.times do |i|
        hash = BSV::Primitives::Digest.sha256("test message #{i}")
        sig = described_class.sign(hash, privkey_bn)
        expect(sig.low_s?).to be true
      end
    end

    it 'is deterministic — same inputs produce same signature' do
      hash = BSV::Primitives::Digest.sha256('deterministic')
      sig1 = described_class.sign(hash, privkey_bn)
      sig2 = described_class.sign(hash, privkey_bn)
      expect(sig1).to eq(sig2)
    end

    # RFC 6979 exact-match vectors from Trezor/CoreBitcoin (via Go SDK).
    # Each vector checks the exact (r, s) output, not just validity.
    it 'produces exact DER signatures matching Trezor/CoreBitcoin vectors' do
      vectors = [
        {
          key: 'cca9fbcc1b41e5a95d369eaa6ddcff73b61a4efaa279cfc6567e8daa39cbaf50',
          msg: 'sample',
          der: '3045022100af340daf02cc15c8d5d08d7735dfe6b98a474ed373bdb5fbecf7571be52b3842' \
               '02205009fb27f37034a9b24b707b7c6b79ca23ddef9e25f7282e8a797efe53a8f124'
        },
        {
          # Private key = 1 (leading zero bytes). S > half-order tests canonicalisation.
          key: '0000000000000000000000000000000000000000000000000000000000000001',
          msg: 'Satoshi Nakamoto',
          der: '3045022100934b1ea10a4b3c1757e2b0c017d0b6143ce3c9a7e6a4a49860d7a6ab210ee3d8' \
               '02202442ce9d2b916064108014783e923ec36b49743e2ffa1c4496f01a512aafd9e5'
        },
        {
          # Private key = N-1 (maximum valid key)
          key: 'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140',
          msg: 'Satoshi Nakamoto',
          der: '3045022100fd567d121db66e382991534ada77a6bd3106f0a1098c231e47993447cd6af2d0' \
               '02206b39cd0eb1bc8603e159ef5c20a5c8ad685a45b06ce9bebed3f153d10d93bed5'
        },
        {
          key: 'f8b8af8ce3c7cca5e300d33939540c10d45ce001b8f252bfbc57ba0342904181',
          msg: 'Alan Turing',
          der: '304402207063ae83e7f62bbb171798131b4a0564b956930092b33b07b395615d9ec7e15c' \
               '022058dfcc1e00a35e1572f366ffe34ba0fc47db1e7189759b9fb233c5b05ab388ea'
        },
        {
          # Same key=1 with long message
          key: '0000000000000000000000000000000000000000000000000000000000000001',
          msg: 'All those moments will be lost in time, like tears in rain. Time to die...',
          der: '30450221008600dbd41e348fe5c9465ab92d23e3db8b98b873beecd930736488696438cb6b' \
               '0220547fe64427496db33bf66019dacbf0039c04199abb0122918601db38a72cfc21'
        },
        {
          key: 'e91671c46231f833a6406ccbea0e3e392c76c167bac1cb013f6f1013980455c2',
          msg: "There is a computer disease that anybody who works with computers knows about. It's a very " \
               'serious disease and it interferes completely with the work. The trouble with computers is ' \
               "that you 'play' with them!",
          der: '3045022100b552edd27580141f3b2a5463048cb7cd3e047b97c9f98076c32dbdf85a68718b' \
               '0220279fa72dd19bfae05577e06c7c0c1900c371fcd5893f7e1d56a37d30174671f6'
        }
      ]

      vectors.each_with_index do |v, i|
        priv = OpenSSL::BN.new(v[:key], 16)
        hash = BSV::Primitives::Digest.sha256(v[:msg])
        sig = described_class.sign(hash, priv)

        expect(sig.to_hex).to eq(v[:der]),
                              "Vector #{i} (#{v[:msg][0, 20]}...): DER mismatch"
      end
    end
  end

  describe '.sign with force_low_s' do
    it 'produces a low-S signature when force_low_s is false (default)' do
      hash = BSV::Primitives::Digest.sha256('force_low_s test')
      sig = described_class.sign(hash, privkey_bn, force_low_s: false)
      # sign_raw already normalises to low-S, so this should be low-S regardless
      expect(sig.low_s?).to be true
    end

    it 'produces a low-S signature when force_low_s is true' do
      hash = BSV::Primitives::Digest.sha256('force_low_s true')
      sig = described_class.sign(hash, privkey_bn, force_low_s: true)
      expect(sig.low_s?).to be true
    end

    it 'force_low_s: true and force_low_s: false produce equal signatures for same inputs' do
      # Both paths normalise via sign_raw, so results are identical.
      hash = BSV::Primitives::Digest.sha256('idempotent')
      sig_default = described_class.sign(hash, privkey_bn)
      sig_forced  = described_class.sign(hash, privkey_bn, force_low_s: true)
      expect(sig_forced).to eq(sig_default)
    end
  end

  describe '.sign_recoverable' do
    it 'returns a [Signature, Integer] pair' do
      hash = BSV::Primitives::Digest.sha256('hello')
      result = described_class.sign_recoverable(hash, privkey_bn)

      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
      expect(result[0]).to be_a(BSV::Primitives::Signature)
      expect(result[1]).to be_an(Integer)
      expect(result[1]).to be_between(0, 3)
    end

    it 'produces the same signature as sign' do
      hash = BSV::Primitives::Digest.sha256('hello')
      sig = described_class.sign(hash, privkey_bn)
      sig_r, _recovery_id = described_class.sign_recoverable(hash, privkey_bn)

      expect(sig_r).to eq(sig)
    end

    it 'always produces low-S signatures' do
      10.times do |i|
        hash = BSV::Primitives::Digest.sha256("recoverable #{i}")
        sig, _id = described_class.sign_recoverable(hash, privkey_bn)
        expect(sig.low_s?).to be true
      end
    end
  end

  describe '.recover_public_key' do
    it 'recovers the correct public key from a signature' do
      hash = BSV::Primitives::Digest.sha256('hello recovery')
      sig, recovery_id = described_class.sign_recoverable(hash, privkey_bn)

      recovered = described_class.recover_public_key(hash, sig, recovery_id)
      expected = BSV::Primitives::PublicKey.new(pubkey_point)

      expect(recovered).to eq(expected)
    end

    it 'round-trips with multiple key/message combinations' do
      keys = %w[
        0000000000000000000000000000000000000000000000000000000000000001
        eaf02ca348c524e6392655ba4d29603cd1a7347d9d65cfe93ce1ebffdca22694
        cca9fbcc1b41e5a95d369eaa6ddcff73b61a4efaa279cfc6567e8daa39cbaf50
      ]
      messages = ['test', 'another message', 'hello world']

      keys.each do |key_hex|
        priv = OpenSSL::BN.new(key_hex, 16)
        expected_pub = BSV::Primitives::PublicKey.new(BSV::Primitives::Curve.multiply_generator(priv))

        messages.each do |msg|
          hash = BSV::Primitives::Digest.sha256(msg)
          sig, recovery_id = described_class.sign_recoverable(hash, priv)
          recovered = described_class.recover_public_key(hash, sig, recovery_id)

          expect(recovered).to eq(expected_pub),
                               "failed for key=#{key_hex[0, 8]}..., msg=#{msg.inspect}"
        end
      end
    end
  end

  describe '.verify' do
    it 'verifies a valid signature' do
      hash = BSV::Primitives::Digest.sha256('hello world')
      sig = described_class.sign(hash, privkey_bn)
      expect(described_class.verify(hash, sig, pubkey_point)).to be true
    end

    it 'rejects a signature with wrong hash' do
      hash = BSV::Primitives::Digest.sha256('hello world')
      wrong_hash = BSV::Primitives::Digest.sha256('wrong message')
      sig = described_class.sign(hash, privkey_bn)
      expect(described_class.verify(wrong_hash, sig, pubkey_point)).to be false
    end

    it 'rejects a signature with wrong public key' do
      hash = BSV::Primitives::Digest.sha256('hello world')
      sig = described_class.sign(hash, privkey_bn)

      wrong_priv = OpenSSL::BN.new('deadbeef' * 8, 16)
      wrong_pub = BSV::Primitives::Curve.multiply_generator(wrong_priv)
      expect(described_class.verify(hash, sig, wrong_pub)).to be false
    end

    it 'rejects a forged signature' do
      hash = BSV::Primitives::Digest.sha256('hello world')
      forged = BSV::Primitives::Signature.new(OpenSSL::BN.new('1234', 16), OpenSSL::BN.new('5678', 16))
      expect(described_class.verify(hash, forged, pubkey_point)).to be false
    end

    it 'rejects R or S out of range' do
      hash = BSV::Primitives::Digest.sha256('test')
      zero = OpenSSL::BN.new('0')
      n = BSV::Primitives::Curve::N

      expect(described_class.verify(hash, BSV::Primitives::Signature.new(zero, OpenSSL::BN.new('1')), pubkey_point))
        .to be false
      expect(described_class.verify(hash, BSV::Primitives::Signature.new(n, OpenSSL::BN.new('1')), pubkey_point))
        .to be false
    end
  end

  describe 'sign then verify round-trip' do
    it 'works with various key/message combinations' do
      keys = %w[
        0000000000000000000000000000000000000000000000000000000000000001
        eaf02ca348c524e6392655ba4d29603cd1a7347d9d65cfe93ce1ebffdca22694
        cca9fbcc1b41e5a95d369eaa6ddcff73b61a4efaa279cfc6567e8daa39cbaf50
      ]
      messages = ['', 'a', 'abc', 'hello world', 'The quick brown fox jumps over the lazy dog']

      keys.each do |key_hex|
        priv = OpenSSL::BN.new(key_hex, 16)
        pub = BSV::Primitives::Curve.multiply_generator(priv)

        messages.each do |msg|
          hash = BSV::Primitives::Digest.sha256(msg)
          sig = described_class.sign(hash, priv)
          expect(described_class.verify(hash, sig, pub)).to be(true),
                                                            "failed for key=#{key_hex[0, 8]}..., msg=#{msg.inspect}"
        end
      end
    end
  end
end
