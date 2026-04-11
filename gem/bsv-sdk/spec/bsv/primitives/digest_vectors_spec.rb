# frozen_string_literal: true

# Cross-validation of BSV::Primitives::Digest against authoritative
# standard test vectors (NIST CAVP, RFC 4231, ISO/IEC 10118-3).

RSpec.describe BSV::Primitives::Digest do
  # ---------------------------------------------------------------------------
  # SHA-256 — NIST FIPS 180-4 / CAVP short message vectors
  # ---------------------------------------------------------------------------
  describe '.sha256 (NIST vectors)' do
    vectors = [
      {
        name: 'empty string',
        input: '',
        expected: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
      },
      {
        name: 'abc',
        input: 'abc',
        expected: 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
      },
      {
        name: '448-bit message',
        input: 'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
        expected: '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1'
      },
      {
        name: '896-bit message',
        input: 'abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu',
        expected: 'cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1'
      }
    ]

    vectors.each do |v|
      it "computes correct hash for #{v[:name]}" do
        result = described_class.sha256(v[:input])
        expect(result.unpack1('H*')).to eq(v[:expected])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # SHA-256d (double SHA-256) — Bitcoin-specific, verified against known txids
  # ---------------------------------------------------------------------------
  describe '.sha256d' do
    it 'computes correct double hash for empty string' do
      # SHA-256(SHA-256(""))
      result = described_class.sha256d('')
      expect(result.unpack1('H*')).to eq('5df6e0e2761359d30a8275058e299fcc0381534545f55cf43e41983f5d4c9456')
    end

    it 'computes correct double hash for "abc"' do
      result = described_class.sha256d('abc')
      expect(result.unpack1('H*')).to eq('4f8b42c22dd3729b519ba6f68d2da7cc5b2d606d05daed5ad5128cc03e6c6358')
    end
  end

  # ---------------------------------------------------------------------------
  # SHA-1 — NIST FIPS 180-4
  # ---------------------------------------------------------------------------
  describe '.sha1 (NIST vectors)' do
    vectors = [
      {
        name: 'empty string',
        input: '',
        expected: 'da39a3ee5e6b4b0d3255bfef95601890afd80709'
      },
      {
        name: 'abc',
        input: 'abc',
        expected: 'a9993e364706816aba3e25717850c26c9cd0d89d'
      },
      {
        name: '448-bit message',
        input: 'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
        expected: '84983e441c3bd26ebaae4aa1f95129e5e54670f1'
      }
    ]

    vectors.each do |v|
      it "computes correct hash for #{v[:name]}" do
        result = described_class.sha1(v[:input])
        expect(result.unpack1('H*')).to eq(v[:expected])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # SHA-512 — NIST FIPS 180-4
  # ---------------------------------------------------------------------------
  describe '.sha512 (NIST vectors)' do
    vectors = [
      {
        name: 'empty string',
        input: '',
        expected: 'cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce' \
                  '47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e'
      },
      {
        name: 'abc',
        input: 'abc',
        expected: 'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a' \
                  '2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f'
      }
    ]

    vectors.each do |v|
      it "computes correct hash for #{v[:name]}" do
        result = described_class.sha512(v[:input])
        expect(result.unpack1('H*')).to eq(v[:expected])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # RIPEMD-160 — ISO/IEC 10118-3 test vectors
  # https://homes.esat.kuleuven.be/~bosMDselaers/ripemd160.html
  # ---------------------------------------------------------------------------
  describe '.ripemd160 (ISO vectors)' do
    vectors = [
      {
        name: 'empty string',
        input: '',
        expected: '9c1185a5c5e9fc54612808977ee8f548b2258d31'
      },
      {
        name: 'a',
        input: 'a',
        expected: '0bdc9d2d256b3ee9daae347be6f4dc835a467ffe'
      },
      {
        name: 'abc',
        input: 'abc',
        expected: '8eb208f7e05d987a9b044a8e98c6b087f15a0bfc'
      },
      {
        name: 'message digest',
        input: 'message digest',
        expected: '5d0689ef49d2fae572b881b123a85ffa21595f36'
      },
      {
        name: 'a-z',
        input: 'abcdefghijklmnopqrstuvwxyz',
        expected: 'f71c27109c692c1b56bbdceb5b9d2865b3708dbc'
      }
    ]

    vectors.each do |v|
      it "computes correct hash for #{v[:name]}" do
        result = described_class.ripemd160(v[:input])
        expect(result.unpack1('H*')).to eq(v[:expected])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Hash160 — RIPEMD-160(SHA-256(x)), verified against known Bitcoin values
  # ---------------------------------------------------------------------------
  describe '.hash160' do
    it 'computes correct Hash160 for a compressed public key' do
      # Satoshi's genesis coinbase public key
      pubkey = ['04678afdb0fe5548271967f1a67130b7105cd6a828e03909a67962e0ea1f61de' \
                'b649f6bc3f4cef38c4f35504e51ec112de5c384df7ba0b8d578a4c702b6bf11d5f'].pack('H*')
      result = described_class.hash160(pubkey)
      expect(result.unpack1('H*')).to eq('62e907b15cbf27d5425399ebf6f0fb50ebb88f18')
    end
  end

  # ---------------------------------------------------------------------------
  # HMAC-SHA256 — RFC 4231 test vectors
  # ---------------------------------------------------------------------------
  describe '.hmac_sha256 (RFC 4231)' do
    vectors = [
      {
        name: 'test case 1 (20-byte key)',
        key: ['0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b'].pack('H*'),
        data: 'Hi There',
        expected: 'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7'
      },
      {
        name: 'test case 2 (Jefe)',
        key: 'Jefe',
        data: 'what do ya want for nothing?',
        expected: '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843'
      },
      {
        name: 'test case 3 (20-byte 0xaa key)',
        key: "\xaa" * 20,
        data: "\xdd" * 50,
        expected: '773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe'
      }
    ]

    vectors.each do |v|
      it "computes correct HMAC for #{v[:name]}" do
        result = described_class.hmac_sha256(v[:key], v[:data])
        expect(result.unpack1('H*')).to eq(v[:expected])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # HMAC-SHA512 — RFC 4231 test vectors
  # ---------------------------------------------------------------------------
  describe '.hmac_sha512 (RFC 4231)' do
    vectors = [
      {
        name: 'test case 1 (20-byte key)',
        key: ['0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b'].pack('H*'),
        data: 'Hi There',
        expected: '87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cde' \
                  'daa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854'
      },
      {
        name: 'test case 2 (Jefe)',
        key: 'Jefe',
        data: 'what do ya want for nothing?',
        expected: '164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea250554' \
                  '9758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737'
      },
      {
        name: 'test case 3 (20-byte 0xaa key)',
        key: "\xaa" * 20,
        data: "\xdd" * 50,
        expected: 'fa73b0089d56a284efb0f0756c890be9b1b5dbdd8ee81a3655f83e33b2279d39' \
                  'bf3e848279a722c806b485a47e67c807b946a337bee8942674278859e13292fb'
      }
    ]

    vectors.each do |v|
      it "computes correct HMAC for #{v[:name]}" do
        result = described_class.hmac_sha512(v[:key], v[:data])
        expect(result.unpack1('H*')).to eq(v[:expected])
      end
    end
  end
end
