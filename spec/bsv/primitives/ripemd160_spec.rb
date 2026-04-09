# frozen_string_literal: true

# Official test vectors from the RIPEMD-160 specification:
# https://homes.esat.kuleuven.be/~bosselae/ripemd160/
RIPEMD160_VECTORS = [
  ['',                                                              '9c1185a5c5e9fc54612808977ee8f548b2258d31'],
  ['a',                                                             '0bdc9d2d256b3ee9daae347be6f4dc835a467ffe'],
  ['abc',                                                           '8eb208f7e05d987a9b044a8e98c6b087f15a0bfc'],
  ['message digest',                                                '5d0689ef49d2fae572b881b123a85ffa21595f36'],
  ['abcdefghijklmnopqrstuvwxyz',                                    'f71c27109c692c1b56bbdceb5b9d2865b3708dbc'],
  ['abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq', '12a053384a9c0c88e405a06c27dcf49ada62eb2b'],
  ['ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789', 'b0e20b6e3116640286ed3a87a5713079b21f5189'],
  ['1234567890' * 8,                                                '9b752e45573d4b39f4dbd3323cab82bf63326bfb'],
  ['a' * 1_000_000,                                                 '52783243c1697bdbe16d37f97f68f08325dc1528']
].freeze

RSpec.describe BSV::Primitives::Ripemd160 do
  describe '.digest' do
    RIPEMD160_VECTORS.each do |input, expected_hex|
      label = if input.length > 40
                "#{input[0, 20]}... (#{input.length} chars)"
              else
                input.inspect
              end

      it "hashes #{label} correctly" do
        result = described_class.digest(input)
        expect(result.unpack1('H*')).to eq(expected_hex)
      end
    end

    it 'returns a 20-byte binary string' do
      result = described_class.digest('test')
      expect(result.bytesize).to eq(20)
      expect(result.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it 'accepts binary (ASCII-8BIT) input' do
      binary = "\x00\xFF\xAB\xCD".b
      expect { described_class.digest(binary) }.not_to raise_error
    end

    it 'accepts UTF-8 input and treats it as binary' do
      # Consistent with OpenSSL behaviour: UTF-8 content hashed bytewise.
      result = described_class.digest('abc')
      expect(result.unpack1('H*')).to eq('8eb208f7e05d987a9b044a8e98c6b087f15a0bfc')
    end
  end

  describe 'BSV::Primitives::Digest integration' do
    it 'Digest.ripemd160 delegates to Ripemd160.digest' do
      RIPEMD160_VECTORS.each do |input, expected_hex|
        result = BSV::Primitives::Digest.ripemd160(input)
        expect(result.unpack1('H*')).to eq(expected_hex)
      end
    end

    it 'Digest.hash160 still produces correct output (RIPEMD160 of SHA256)' do
      # Hash160 of the secp256k1 generator point compressed public key.
      pubkey = ['0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798'].pack('H*')
      result = BSV::Primitives::Digest.hash160(pubkey)
      expect(result.unpack1('H*')).to eq('751e76e8199196d454941c45d1b3a323f1433bd6')
    end
  end
end
