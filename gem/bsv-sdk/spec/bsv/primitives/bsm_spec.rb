# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Primitives::BSM do
  # Go SDK test vectors — compressed key signatures
  let(:go_vectors) do
    [
      {
        key_hex: '0499f8239bfe10eb0f5e53d543635a423c96529dd85fa4bad42049a0b435ebdd',
        message: 'test message',
        expected: 'IFxPx8JHsCiivB+DW/RgNpCLT6yG3j436cUNWKekV3ORBrHNChIjeVReyAco7PVmmDtVD3POs9FhDlm/nk5I6O8='
      },
      {
        key_hex: 'ef0b8bad0be285099534277fde328f8f19b3be9cadcd4c08e6ac0b5f863745ac',
        message: 'This is a test message',
        expected: 'H+zZagsyz7ioC/ZOa5EwsaKice0vs2BvZ0ljgkFHxD3vGsMlGeD4sXHEcfbI4h8lP29VitSBdf4A+nHXih7svf4='
      },
      {
        key_hex: '93596babb564cbbdc84f2370c710b9bcc94333495b60af719b5fcf9ba00ba82c',
        message: 'This is a test message',
        expected: 'IIuDw09ffPgEDuxEw5yHVp1+mi4QpuhAwLyQdpMTfsHCOkMqTKXuP7dSNWMEJqZsiQ8eKMDRvf2wZ4e5bxcu4O0='
      },
      {
        key_hex: '50381cf8f52936faae4a05a073a03d688a9fa206d005e87a39da436c75476d78',
        message: 'This is a test message',
        expected: 'ILBmbjCY2Z7eSXGXZoBI3x2ZRaYUYOGtEaDjXetaY+zNDtMOvagsOGEHnVT3f5kXlEbuvmPydHqLnyvZP3cDOWk='
      },
      {
        key_hex: 'c7726663147afd1add392d129086e57c0b05aa66a6ded564433c04bd55741434',
        message: 'This is a test message',
        expected: 'IOI207QUnTLr2Ll+s4kUxNgLgorkc/Z5Pc+XNvUBYLy2TxaU6oHEJ2TTJ1mZVrtUyHm6e315v1tIjeosW3Odfqw='
      },
      {
        key_hex: 'c7726663147afd1add392d129086e57c0b05aa66a6ded564433c04bd55741434',
        message: '1',
        expected: 'IMcRFG1VNN9TDGXpCU+9CqKLNOuhwQiXI5hZpkTOuYHKBDOWayNuAABofYLqUHYTMiMf9mYFQ0sPgFJZz3F7ELQ='
      },
      {
        key_hex: '0499f8239bfe10eb0f5e53d543635a423c96529dd85fa4bad42049a0b435ebdd',
        message: "This time I'm writing a new message that is obnixiously long af. " \
                 "This time I'm writing a new message that is obnixiously long af. " \
                 "This time I'm writing a new message that is obnixiously long af. " \
                 "This time I'm writing a new message that is obnixiously long af. " \
                 "This time I'm writing a new message that is obnixiously long af. " \
                 "This time I'm writing a new message that is obnixiously long af. " \
                 "This time I'm writing a new message that is obnixiously long af. " \
                 "This time I'm writing a new message that is obnixiously long af. " \
                 "This time I'm writing a new message that is obnixiously long af. " \
                 "This time I'm writing a new message that is obnixiously long af. " \
                 "This time I'm writing a new message that is obnixiously long af. " \
                 "This time I'm writing a new message that is obnixiously long af. " \
                 "This time I'm writing a new message that is obnixiously long af. " \
                 "This time I'm writing a new message that is obnixiously long af.",
        expected: 'HxRcFXQc7LHxFNpK5lzhR+LF5ixIvhB089bxYzTAV02yGHm/3ALxltz/W4lGp77Q5UTxdj+TU+96mdAcJ5b/fGs='
      }
    ]
  end

  describe '.sign' do
    it 'produces signatures matching all Go SDK test vectors' do
      go_vectors.each do |vec|
        priv = BSV::Primitives::PrivateKey.from_hex(vec[:key_hex])
        result = described_class.sign(vec[:message], priv)

        expect(result).to eq(vec[:expected]),
                          "mismatch for key=#{vec[:key_hex][0, 8]}..., msg=#{vec[:message].inspect}"
      end
    end

    it 'returns a base64 string that decodes to 65 bytes' do
      priv = BSV::Primitives::PrivateKey.from_hex(go_vectors.first[:key_hex])
      sig = described_class.sign('test', priv)

      decoded = sig.unpack1('m0')
      expect(decoded.bytesize).to eq(65)
    end
  end

  describe '.verify' do
    it 'verifies all Go SDK test vectors against the derived address' do
      go_vectors.each do |vec|
        priv = BSV::Primitives::PrivateKey.from_hex(vec[:key_hex])
        address = priv.public_key.address

        result = described_class.verify(vec[:message], vec[:expected], address)
        expect(result).to be(true),
                          "verification failed for key=#{vec[:key_hex][0, 8]}..., msg=#{vec[:message].inspect}"
      end
    end

    it 'returns false for wrong address' do
      vec = go_vectors.first
      wrong_address = '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa'

      expect(described_class.verify(vec[:message], vec[:expected], wrong_address)).to be false
    end

    it 'returns false for wrong message' do
      vec = go_vectors.first
      priv = BSV::Primitives::PrivateKey.from_hex(vec[:key_hex])
      address = priv.public_key.address

      expect(described_class.verify('wrong message', vec[:expected], address)).to be false
    end

    it 'returns false for a tampered signature' do
      vec = go_vectors.first
      priv = BSV::Primitives::PrivateKey.from_hex(vec[:key_hex])
      address = priv.public_key.address

      # Flip a byte in the decoded signature, re-encode
      raw = vec[:expected].unpack1('m0').dup
      raw.setbyte(10, raw.getbyte(10) ^ 0xFF)
      tampered = [raw].pack('m0')

      expect(described_class.verify(vec[:message], tampered, address)).to be false
    end
  end

  describe 'sign then verify round-trip' do
    let(:priv) { BSV::Primitives::PrivateKey.generate }
    let(:address) { priv.public_key.address }

    it 'works with a simple message' do
      sig = described_class.sign('hello world', priv)
      expect(described_class.verify('hello world', sig, address)).to be true
    end

    it 'works with an empty message' do
      sig = described_class.sign('', priv)
      expect(described_class.verify('', sig, address)).to be true
    end

    it 'works with a unicode message' do
      msg = "\u{1F600} Bitcoin \u00A3100"
      sig = described_class.sign(msg, priv)
      expect(described_class.verify(msg, sig, address)).to be true
    end

    it 'works with a long message (>252 bytes, exercises 3-byte varint)' do
      msg = 'A' * 300
      sig = described_class.sign(msg, priv)
      expect(described_class.verify(msg, sig, address)).to be true
    end
  end

  describe '.magic_hash' do
    it 'returns a 32-byte hash' do
      hash = described_class.magic_hash('test')
      expect(hash.bytesize).to eq(32)
    end

    it 'is deterministic' do
      h1 = described_class.magic_hash('hello')
      h2 = described_class.magic_hash('hello')
      expect(h1).to eq(h2)
    end

    it 'differs for different messages' do
      h1 = described_class.magic_hash('hello')
      h2 = described_class.magic_hash('world')
      expect(h1).not_to eq(h2)
    end
  end

  describe 'error handling' do
    let(:priv) { BSV::Primitives::PrivateKey.generate }
    let(:address) { priv.public_key.address }

    it 'raises ArgumentError for invalid base64' do
      expect { described_class.verify('test', '!!!not-base64!!!', address) }
        .to raise_error(ArgumentError, /invalid base64/)
    end

    it 'raises ArgumentError for wrong signature length' do
      too_short = ['FF' * 32].pack('H*')
      encoded = [too_short].pack('m0')

      expect { described_class.verify('test', encoded, address) }
        .to raise_error(ArgumentError, /invalid signature length/)
    end

    it 'raises ArgumentError for flag byte out of range' do
      # Flag = 0x00, which is outside 27-34
      raw = "\x00".b + ("\x01".b * 64)
      encoded = [raw].pack('m0')

      expect { described_class.verify('test', encoded, address) }
        .to raise_error(ArgumentError, /flag byte.*out of range/)
    end
  end
end
