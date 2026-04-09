# frozen_string_literal: true

RSpec.describe BSV::Primitives::Signature do
  # Known DER signature from Go SDK test vectors
  let(:der_hex) do
    '3045022100af340daf02cc15c8d5d08d7735dfe6b98a474ed373bdb5fbecf7571be52b3842' \
      '02205009fb27f37034a9b24b707b7c6b79ca23ddef9e25f7282e8a797efe53a8f124'
  end
  let(:der_bytes) { [der_hex].pack('H*') }

  describe '.from_der / #to_der' do
    it 'round-trips a valid DER signature' do
      sig = described_class.from_der(der_bytes)
      expect(sig.to_der).to eq(der_bytes)
    end

    it 'parses R and S correctly' do
      sig = described_class.from_der(der_bytes)
      expect(sig.r.to_s(16)).to eq('AF340DAF02CC15C8D5D08D7735DFE6B98A474ED373BDB5FBECF7571BE52B3842')
      expect(sig.s.to_s(16)).to eq('5009FB27F37034A9B24B707B7C6B79CA23DDEF9E25F7282E8A797EFE53A8F124')
    end

    it 'raises on invalid sequence tag' do
      expect { described_class.from_der("\x31\x06\x02\x01\x01\x02\x01\x01".b) }
        .to raise_error(ArgumentError, /invalid sequence tag/)
    end

    it 'raises on truncated input' do
      expect { described_class.from_der("\x30\x04\x02\x01".b) }
        .to raise_error(ArgumentError)
    end

    it 'raises on trailing bytes' do
      expect { described_class.from_der("#{der_bytes}\u0000") }
        .to raise_error(ArgumentError)
    end

    it 'rejects multi-byte DER length encoding (BIP-66 strict DER, 0x81 prefix)' do
      # 0x81 as the length byte signals "1 extra length byte follows" in ASN.1.
      # BIP-66 strict DER forbids multi-byte lengths entirely.
      # Sequence: 0x30 0x81 0x06 0x02 0x01 0x01 0x02 0x01 0x01
      der = "\x30\x81\x06\x02\x01\x01\x02\x01\x01".b
      expect { described_class.from_der(der) }
        .to raise_error(ArgumentError, /non-canonical DER length/)
    end

    it 'rejects DER length with 0x82 (two-byte extended length)' do
      # 0x82 means "2 extra length bytes follow". Also forbidden.
      der = "\x30\x82\x00\x06\x02\x01\x01\x02\x01\x01".b
      expect { described_class.from_der(der) }
        .to raise_error(ArgumentError, /non-canonical DER length/)
    end

    it 'raises on negative R' do
      expect { described_class.from_der("\x30\x06\x02\x01\x80\x02\x01\x01".b) }
        .to raise_error(ArgumentError, /negative/)
    end

    it 'raises on excessive padding in R' do
      expect { described_class.from_der("\x30\x07\x02\x02\x00\x01\x02\x01\x01".b) }
        .to raise_error(ArgumentError, /excessive padding/)
    end

    it 'accepts valid zero-padded R when high bit is set' do
      # R = 0x0080 is valid: the 0x00 prefix is required because 0x80 has high bit set
      der = "\x30\x07\x02\x02\x00\x80\x02\x01\x01".b
      sig = described_class.from_der(der)
      expect(sig.r).to eq(OpenSSL::BN.new('128'))
      expect(sig.to_der).to eq(der)
    end

    it 'raises on excessive padding in S' do
      # S = 0x0001 is invalid: 0x01 has high bit clear, so the 0x00 prefix is excessive
      expect { described_class.from_der("\x30\x07\x02\x01\x01\x02\x02\x00\x01".b) }
        .to raise_error(ArgumentError, /excessive padding/)
    end
  end

  describe '.from_hex / #to_hex' do
    it 'round-trips via hex' do
      sig = described_class.from_hex(der_hex)
      expect(sig.to_hex).to eq(der_hex)
    end
  end

  describe '#low_s? / #to_low_s' do
    it 'reports low S as low' do
      sig = described_class.from_der(der_bytes)
      expect(sig.low_s?).to be true
    end

    it 'returns self when already low-S' do
      sig = described_class.from_der(der_bytes)
      expect(sig.to_low_s).to eq(sig)
    end

    it 'converts high-S to low-S' do
      n = BSV::Primitives::Curve::N
      half_n = BSV::Primitives::Curve::HALF_N
      high_s = half_n + OpenSSL::BN.new('1')
      sig = described_class.new(OpenSSL::BN.new('1234', 16), high_s)

      expect(sig.low_s?).to be false

      low = sig.to_low_s
      expect(low.low_s?).to be true
      expect(low.s).to eq(n - high_s)
    end
  end

  describe '#==' do
    it 'compares two identical signatures' do
      sig1 = described_class.from_der(der_bytes)
      sig2 = described_class.from_der(der_bytes)
      expect(sig1).to eq(sig2)
    end

    it 'compares two different signatures' do
      sig1 = described_class.new(OpenSSL::BN.new('1'), OpenSSL::BN.new('2'))
      sig2 = described_class.new(OpenSSL::BN.new('3'), OpenSSL::BN.new('4'))
      expect(sig1).not_to eq(sig2)
    end
  end

  describe '#to_der encoding' do
    it 'pads R with zero byte when high bit set' do
      r = OpenSSL::BN.new('FF' * 32, 16) # High bit set
      s = OpenSSL::BN.new('01', 16)
      sig = described_class.new(r, s)
      reparsed = described_class.from_der(sig.to_der)
      expect(reparsed.r).to eq(r)
      expect(reparsed.s).to eq(s)
    end

    it 'encodes small values correctly' do
      sig = described_class.new(OpenSSL::BN.new('1'), OpenSSL::BN.new('2'))
      der = sig.to_der
      expect(der.unpack1('H*')).to eq('3006020101020102')
    end
  end
end
