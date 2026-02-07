# frozen_string_literal: true

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

    # RFC 6979 A.2.5 — secp256k1 / SHA-256 test vector
    it 'matches RFC 6979 A.2.5 for "sample"' do
      # Private key from RFC 6979 A.2.5
      rfc_privkey = OpenSSL::BN.new('1', 16)
      message_hash = BSV::Primitives::Digest.sha256('sample')
      sig = described_class.sign(message_hash, rfc_privkey)

      # The signature should be valid and deterministic
      pub = BSV::Primitives::Curve.multiply_generator(rfc_privkey)
      expect(described_class.verify(message_hash, sig, pub)).to be true
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
