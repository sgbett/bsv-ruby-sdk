# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Primitives::SymmetricKey do
  describe '.from_random' do
    it 'generates a 32-byte key' do
      key = described_class.from_random
      expect(key.to_bytes.bytesize).to eq(32)
    end

    it 'generates unique keys' do
      keys = Array.new(10) { described_class.from_random.to_bytes }
      expect(keys.uniq.size).to eq(10)
    end
  end

  describe '.new' do
    it 'accepts a 32-byte key' do
      key_bytes = SecureRandom.random_bytes(32)
      key = described_class.new(key_bytes)
      expect(key.to_bytes).to eq(key_bytes)
    end

    it 'left-zero-pads short keys (31 bytes)' do
      short = SecureRandom.random_bytes(31)
      key = described_class.new(short)
      expect(key.to_bytes).to eq("\x00".b + short)
      expect(key.to_bytes.bytesize).to eq(32)
    end

    it 'left-zero-pads a 1-byte key' do
      key = described_class.new("\x42".b)
      expect(key.to_bytes).to eq(("\x00".b * 31) + "\x42".b)
    end

    it 'raises on empty key' do
      expect { described_class.new('') }.to raise_error(ArgumentError, /empty/)
    end

    it 'raises on key longer than 32 bytes' do
      expect { described_class.new(SecureRandom.random_bytes(33)) }.to raise_error(ArgumentError, /at most/)
    end
  end

  describe '#encrypt / #decrypt' do
    let(:key) { described_class.from_random }

    it 'round-trips a simple message' do
      encrypted = key.encrypt('hello world')
      expect(key.decrypt(encrypted)).to eq('hello world'.b)
    end

    it 'round-trips an empty message' do
      encrypted = key.encrypt('')
      expect(key.decrypt(encrypted)).to eq(''.b)
    end

    it 'round-trips a long message' do
      msg = SecureRandom.random_bytes(10_000)
      encrypted = key.encrypt(msg)
      expect(key.decrypt(encrypted)).to eq(msg)
    end

    it 'round-trips UTF-8 text' do
      msg = 'üñîçø∂é'
      encrypted = key.encrypt(msg)
      expect(key.decrypt(encrypted)).to eq(msg.b)
    end

    it 'produces different ciphertext each time (unique IV)' do
      msg = 'deterministic?'
      ct1 = key.encrypt(msg)
      ct2 = key.encrypt(msg)
      expect(ct1).not_to eq(ct2)
    end

    it 'produces ciphertext with correct structure (IV + ct + tag)' do
      encrypted = key.encrypt('test')
      # Minimum size: 32 IV + 4 ciphertext + 16 tag = 52
      expect(encrypted.bytesize).to eq(32 + 4 + 16)
    end
  end

  describe '#decrypt error handling' do
    let(:key) { described_class.from_random }
    let(:other_key) { described_class.from_random }

    it 'raises on wrong key' do
      encrypted = key.encrypt('secret')
      expect { other_key.decrypt(encrypted) }.to raise_error(OpenSSL::Cipher::CipherError)
    end

    it 'raises on tampered ciphertext' do
      encrypted = key.encrypt('secret')
      tampered = encrypted.dup
      # Flip a byte in the ciphertext region (between IV and tag)
      tampered.setbyte(40, tampered.getbyte(40) ^ 0xFF)
      expect { key.decrypt(tampered) }.to raise_error(OpenSSL::Cipher::CipherError)
    end

    it 'raises on tampered auth tag' do
      encrypted = key.encrypt('secret')
      tampered = encrypted.dup
      # Flip last byte (within auth tag)
      tampered.setbyte(-1, tampered.getbyte(-1) ^ 0xFF)
      expect { key.decrypt(tampered) }.to raise_error(OpenSSL::Cipher::CipherError)
    end

    it 'raises on truncated ciphertext' do
      expect { key.decrypt("\x00".b * 47) }.to raise_error(ArgumentError, /too short/)
    end

    it 'raises on minimum-length input (48 bytes = IV + tag, empty plaintext)' do
      # 48 bytes should work (empty plaintext)
      encrypted = key.encrypt('')
      expect(encrypted.bytesize).to eq(48)
      expect(key.decrypt(encrypted)).to eq(''.b)
    end
  end

  describe 'short key round-trip' do
    it 'encrypts/decrypts with a 31-byte key' do
      key = described_class.new(SecureRandom.random_bytes(31))
      encrypted = key.encrypt('ECDH derived')
      expect(key.decrypt(encrypted)).to eq('ECDH derived'.b)
    end
  end

  describe 'cross-SDK test vectors (Go SDK)' do
    # From go-sdk/primitives/ec/testdata/SymmetricKey.vectors.json
    # Key and ciphertext are base64-encoded binary. Plaintext is a literal string.
    vectors = [
      {
        key: 'LIe9CoVXxDDDKt9F4j2lE+GP4oPcMElwyX+LVsuRLqw=',
        ciphertext: '1cf74FpvW0koFZk5e1VQcCtF7UdLj9mtN/L9loFlXwhf6w/06THwVirsvDShuT/KlOjO/HFALj8AcGLU1KRs4zNJDaX2wNebuPkH+qp5N/0cp3fZxgFzHJB3jBPDcdFi8O9WXIBLx9jUQ5KFQk0mZCB2k90VniInWuzqqOQAQQlBy2rgBWp4xg==',
        plaintext: '5+w9tts+i14GDfPSEJwcaAfce7zVLC7wsRAMnCBqIczkqL08I05FZTl7n14H9hnPkS7HBm3EGWNDKCZ64ckCGg=='
      },
      {
        key: 'Di30+CTH8yKVJfXmbkRU6DOesD042IkjZCbFL1lnNqY=',
        ciphertext: 'IFh45HxwvK7wgIZr5UDxvUiEkvjsXVV6VIksaEQoTNCPleaRxE1CE1eZj5ZSPa/Mo2HXa2kvEmVAMslY12gMb7qHAHT2fSORB8TJKubKcjwGUrRxqOWvk24lv7QKhq3uhKkJxZSkPBZS6UM+xX+x7Mb53CoC8Z+7Ork50wGRAA415C+T8FIluA==',
        plaintext: '6pHqDrkIuGmWIpB1spu30PP848D04WlERSjrEZ/JD0jfdS814cOjs4MFkePT1IHeM4+qGFwAMk7HKgWShOKFDQ=='
      },
      {
        key: 'v7kFn4JdB3OVVjy8lk7UTvWe0vY5Qyzn64Q0EVoezlU=',
        ciphertext: 'JeUMCTX3hW7uH7Njfqjtjxd/8jB0Uj4eLLbLNBSMqF3XJmtq2oyX/WWS1po8cwn7jrcK0k8mVxHax/DctH6CIDMc0udBxWYLDyftvIYr448otWmn2IKQN4d3Bh2PKdiIQOo36DO2wOy+T2OJSmJ2XvAkenSZIckCdPIQVpeIi7Bt2ZpHmkObkg==',
        plaintext: 'bSYHdJn15pcsaI8CNmfjKQ3ZvMg7zBaxuxBqyWBmCLdqj29bK54C26G1mx5e605hDrFpuJoNSDTECrk67ebffA=='
      },
      {
        key: 'qIgnjD0FfGVMiWo107bP0oHsLA402lhC7AYUFIKY1KQ=',
        ciphertext: 'ktpzKolKsvtWrvLl0yMdGvh5ngd1hiaNcC1b5yuzo2DEKO/4S7gePO/CWOmW/dloHhzfbBQH9rKDFKK7xHHgqYRc',
        plaintext: 'A cat and a mouse.'
      },
      {
        key: 'K7E/bf3wp6hrVeW0V1KvFJS5JZMhyxwPHCIW6wKBTb0=',
        ciphertext: 'vremTalPp+NxN/loEtLMB94tEymdFk2TfBoTWNYcf4sQqYSNkx2WPdJ4LxrIsGuIg9KMOt7FOcIpDb6rRVpP',
        plaintext: 'üñîçø∂é'
      }
    ]

    vectors.each_with_index do |v, i|
      it "decrypts Go SDK vector #{i + 1}" do
        key = described_class.new(v[:key].unpack1('m0'))
        ct = v[:ciphertext].unpack1('m0')
        expect(key.decrypt(ct)).to eq(v[:plaintext].b)
      end
    end

    # Cross-compatibility vectors from Go SDK compatibility tests (hex-encoded)
    # Tests both 31-byte and 32-byte keys derived from WIF private keys
    context 'with Go/TS bidirectional vectors' do
      bidirectional = [
        {
          wif: 'L4B2postXdaP7TiUrUBYs53Fqzheu7WhSoQVPuY8qBdoBeEwbmZx',
          key_length: 31,
          ciphertexts: %w[
            c374d70a4623036f1dd7b971dbeeea375630dc1da40e7068f4c4aa03487d3b19de3afb26a29173deccfbb1ece4fee6c92406b25948e6fe9cb53383057cb826d0a20269e290bd
            7604d5bdb0eb843051d21873c871c9b1507c3de7ba222e1b407c163c2c166277df95de73be9534a2caf9d4b72157f78e5e2e69d97bc25b18ff4cfbd61a1306c02c0b8b2d165e
          ]
        },
        {
          wif: 'KyLGEhYicSoGchHKmVC2fUx2MRrHzWqvwBFLLT4DZB93Nv5DxVR9',
          key_length: 32,
          ciphertexts: %w[
            2059fc32910bef280d89c4c7edbbc587b31be22339e609fdcc23319bf458840a91ad1b2da87aea13a5dc5cb3469b41c52001070b8003863843978acbdf57755b24491581a059
            d7744c85ad3dafcb9fc5752ab0d04c40f87084e8a466f6b6013ebe0fc5170daab8184aaef66ab2c2733f01c0dc3de322ba3ddeea976499548bc6ec166581181f919c69aa2de5
          ]
        }
      ]

      bidirectional.each do |test|
        context "with #{test[:key_length]}-byte key" do
          let(:private_key) { BSV::Primitives::PrivateKey.from_wif(test[:wif]) }
          let(:key_bytes) { private_key.public_key.point.to_bn(:compressed).to_s(2)[1, 32] }
          let(:sym_key) { described_class.new(key_bytes) }

          it "has a #{test[:key_length]}-byte X coordinate" do
            # X coordinate from the public key
            x_bytes = private_key.public_key.point.to_bn(:compressed).to_s(2)[1, 32]
            # Strip leading zero byte from compressed point format
            x_bytes = x_bytes.sub(/\A\x00+/, ''.b) if test[:key_length] < 32
            expect(x_bytes.bytesize).to eq(test[:key_length])
          end

          test[:ciphertexts].each_with_index do |hex, ci|
            it "decrypts TS/Go ciphertext #{ci + 1}" do
              ct = [hex].pack('H*')
              expect(sym_key.decrypt(ct)).to eq('cross-sdk test message'.b)
            end
          end
        end
      end
    end
  end
end
