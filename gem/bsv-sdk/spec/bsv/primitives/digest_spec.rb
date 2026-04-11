# frozen_string_literal: true

RSpec.describe BSV::Primitives::Digest do
  describe '.sha256' do
    it 'hashes "abc" correctly' do
      result = described_class.sha256('abc')
      expect(result.unpack1('H*')).to eq('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
    end

    it 'returns ASCII-8BIT encoded binary' do
      expect(described_class.sha256('test').encoding).to eq(Encoding::ASCII_8BIT)
    end
  end

  describe '.sha256d' do
    it 'double-hashes correctly' do
      result = described_class.sha256d('abc')
      single = described_class.sha256('abc')
      expect(result).to eq(described_class.sha256(single))
    end
  end

  describe '.sha512' do
    it 'hashes "abc" correctly' do
      result = described_class.sha512('abc')
      expected = 'ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a' \
                 '2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f'
      expect(result.unpack1('H*')).to eq(expected)
    end
  end

  describe '.ripemd160' do
    it 'hashes empty string correctly' do
      result = described_class.ripemd160('')
      expect(result.unpack1('H*')).to eq('9c1185a5c5e9fc54612808977ee8f548b2258d31')
    end

    it 'hashes "abc" correctly' do
      result = described_class.ripemd160('abc')
      expect(result.unpack1('H*')).to eq('8eb208f7e05d987a9b044a8e98c6b087f15a0bfc')
    end
  end

  describe '.hash160' do
    it 'computes RIPEMD160(SHA256(data))' do
      data = ['0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798'].pack('H*')
      result = described_class.hash160(data)
      # Hash160 of the generator point compressed pubkey
      expect(result.unpack1('H*')).to eq('751e76e8199196d454941c45d1b3a323f1433bd6')
    end
  end

  describe '.hmac_sha256' do
    it 'computes HMAC-SHA256' do
      key = ['0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b'].pack('H*')
      data = 'Hi There'
      result = described_class.hmac_sha256(key, data)
      expect(result.unpack1('H*')).to eq('b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7')
    end
  end

  describe '.hmac_sha512' do
    it 'computes HMAC-SHA512' do
      key = ['0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b'].pack('H*')
      data = 'Hi There'
      result = described_class.hmac_sha512(key, data)
      expected = '87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cde' \
                 'daa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854'
      expect(result.unpack1('H*')).to eq(expected)
    end
  end

  describe '.pbkdf2_hmac_sha512' do
    it 'derives key with BIP-39 defaults' do
      password = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about'
      salt = 'mnemonicTREZOR'
      result = described_class.pbkdf2_hmac_sha512(password, salt)
      expected = 'c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04'
      expect(result.unpack1('H*')).to eq(expected)
    end

    it 'returns 64 bytes with ASCII-8BIT encoding' do
      result = described_class.pbkdf2_hmac_sha512('password', 'salt')
      expect(result.length).to eq(64)
      expect(result.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it 'accepts custom iterations and key length' do
      result = described_class.pbkdf2_hmac_sha512('password', 'salt', iterations: 1, key_length: 32)
      expect(result.length).to eq(32)
    end
  end
end
