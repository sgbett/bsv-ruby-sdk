# frozen_string_literal: true

FAKE_SCRIPT_BYTES = 'fake script'

# Go SDK cross-SDK conformance vectors (from go-sdk/script/bip276_test.go)
BIP276_GO_VECTORS = [
  {
    label: 'mainnet script',
    encoded: 'bitcoin-script:010166616b65207363726970746f0cd86a',
    prefix: 'bitcoin-script',
    version: 1,
    network: 1,
    data: FAKE_SCRIPT_BYTES
  },
  {
    label: 'testnet script (proves version-then-network field order)',
    encoded: 'bitcoin-script:010266616b652073637269707494becee6',
    prefix: 'bitcoin-script',
    version: 1,
    network: 2,
    data: FAKE_SCRIPT_BYTES
  },
  {
    label: 'template prefix',
    encoded: 'bitcoin-template:010166616b65207363726970749e31aa72',
    prefix: 'bitcoin-template',
    version: 1,
    network: 1,
    data: FAKE_SCRIPT_BYTES
  },
  {
    label: 'custom prefix',
    encoded: 'different-prefix:010166616b6520736372697074effdb090',
    prefix: 'different-prefix',
    version: 1,
    network: 1,
    data: FAKE_SCRIPT_BYTES
  }
].freeze

RSpec.describe 'BSV::Script::BIP276' do
  subject(:mod) { BSV::Script::BIP276 }

  describe '.encode' do
    it 'encodes the spec example correctly (matches Go mainnet vector)' do
      result = mod.encode(FAKE_SCRIPT_BYTES,
                          prefix: BSV::Script::BIP276::PREFIX_SCRIPT,
                          version: 1,
                          network: 1)
      expect(result).to eq('bitcoin-script:010166616b65207363726970746f0cd86a')
    end

    it 'encodes with testnet network in the correct field order (version-then-network)' do
      result = mod.encode(FAKE_SCRIPT_BYTES,
                          prefix: BSV::Script::BIP276::PREFIX_SCRIPT,
                          version: 1,
                          network: 2)
      # 01 = version, 02 = network; if reversed this would be 0201 instead of 0102
      expect(result).to eq('bitcoin-script:010266616b652073637269707494becee6')
    end

    it 'encodes template prefix' do
      result = mod.encode(FAKE_SCRIPT_BYTES,
                          prefix: BSV::Script::BIP276::PREFIX_TEMPLATE,
                          version: 1,
                          network: 1)
      expect(result).to eq('bitcoin-template:010166616b65207363726970749e31aa72')
    end

    it 'encodes custom prefix' do
      result = mod.encode(FAKE_SCRIPT_BYTES,
                          prefix: 'different-prefix',
                          version: 1,
                          network: 1)
      expect(result).to eq('different-prefix:010166616b6520736372697074effdb090')
    end

    it 'encodes empty data' do
      result = mod.encode('', prefix: BSV::Script::BIP276::PREFIX_SCRIPT, version: 1, network: 1)
      expect(result).to eq('bitcoin-script:0101f8648dd7')
    end

    it 'encodes version 255 and network 255 (max boundary)' do
      result = mod.encode('x', prefix: 'p', version: 255, network: 255)
      expect(result).to start_with('p:ffff78')
    end

    it 'rejects version 0' do
      expect { mod.encode('x', version: 0) }.to raise_error(ArgumentError, /version/)
    end

    it 'rejects version greater than 255' do
      expect { mod.encode('x', version: 256) }.to raise_error(ArgumentError, /version/)
    end

    it 'rejects network 0' do
      expect { mod.encode('x', network: 0) }.to raise_error(ArgumentError, /network/)
    end

    it 'rejects network greater than 255' do
      expect { mod.encode('x', network: 256) }.to raise_error(ArgumentError, /network/)
    end
  end

  describe '.decode' do
    it 'decodes the Go SDK mainnet vector' do
      result = mod.decode('bitcoin-script:010166616b65207363726970746f0cd86a')
      expect(result.prefix).to  eq('bitcoin-script')
      expect(result.version).to eq(1)
      expect(result.network).to eq(1)
      expect(result.data).to    eq(FAKE_SCRIPT_BYTES)
    end

    it 'decodes the Go SDK testnet vector and proves version-then-network field order' do
      result = mod.decode('bitcoin-script:010266616b652073637269707494becee6')
      # The second byte (02) must land in network, not version.
      expect(result.version).to eq(1)
      expect(result.network).to eq(2)
      expect(result.data).to    eq(FAKE_SCRIPT_BYTES)
    end

    it 'decodes a vector with A-F hex digits in version and network' do
      encoded = mod.encode('test', prefix: 'bitcoin-script', version: 170, network: 255)
      result  = mod.decode(encoded)
      expect(result.version).to eq(170) # 0xAA
      expect(result.network).to eq(255) # 0xFF
      expect(result.data).to    eq('test')
    end

    it 'decodes empty data' do
      encoded = mod.encode('', prefix: 'bitcoin-script', version: 1, network: 1)
      result  = mod.decode(encoded)
      expect(result.data).to eq('')
    end

    it 'returns an immutable Result value object' do
      result = mod.decode('bitcoin-script:010166616b65207363726970746f0cd86a')
      expect(result).to be_a(BSV::Script::BIP276::Result)
      expect { result.data = 'x' }.to raise_error(NoMethodError)
    end

    it 'raises InvalidFormat on missing colon separator' do
      expect { mod.decode('bitcoin-script010166616b65207363726970746f0cd86a') }
        .to raise_error(BSV::Script::BIP276::InvalidFormat)
    end

    it 'raises InvalidFormat on a short (truncated) string' do
      expect { mod.decode('bitcoin-script:01') }
        .to raise_error(BSV::Script::BIP276::InvalidFormat)
    end

    it 'raises InvalidFormat on non-hex characters in data' do
      expect { mod.decode('bitcoin-script:0101ZZ00000000') }
        .to raise_error(BSV::Script::BIP276::InvalidFormat)
    end

    it 'raises InvalidFormat on odd-length data hex' do
      # 'bitcoin-script:0101abc0cd86a' — regex matches with data="a" (1 hex char, odd length).
      # The explicit parity check catches this before reaching checksum verification.
      expect { mod.decode('bitcoin-script:0101abc0cd86a') }
        .to raise_error(BSV::Script::BIP276::InvalidFormat)
    end

    it 'raises InvalidChecksum on a tampered checksum' do
      expect { mod.decode('bitcoin-script:010166616b65207363726970740000ffff') }
        .to raise_error(BSV::Script::BIP276::InvalidChecksum)
    end

    it 'accepts mixed-case checksum hex' do
      result = mod.decode('bitcoin-script:010166616b65207363726970746F0CD86A')
      expect(result.data).to eq(FAKE_SCRIPT_BYTES)
    end

    it 'accepts uppercase payload from a producer that hashed the uppercase preimage' do
      # Regression: an earlier implementation rebuilt the preimage from the
      # parsed data, normalising the hex to lowercase, which broke verification
      # for spec-conformant producers that emit uppercase. The checksum is
      # defined over the exact preimage; we now compute it over the input.
      preimage_upper = "bitcoin-script:0101#{FAKE_SCRIPT_BYTES.unpack1('H*').upcase}"
      checksum_hex   = BSV::Primitives::Digest.sha256d(preimage_upper)[0, 4].unpack1('H*')
      result = mod.decode(preimage_upper + checksum_hex)
      expect(result.data).to eq(FAKE_SCRIPT_BYTES)
    end
  end

  describe 'convenience helpers' do
    describe '.encode_script / .decode_script' do
      it 'round-trips a payload through encode_script and decode_script' do
        encoded = mod.encode_script('my script data')
        result  = mod.decode_script(encoded)
        expect(result.prefix).to eq(BSV::Script::BIP276::PREFIX_SCRIPT)
        expect(result.data).to   eq('my script data')
      end

      it 'decode_script raises InvalidFormat on non-script prefix' do
        encoded = mod.encode_template('x')
        expect { mod.decode_script(encoded) }
          .to raise_error(BSV::Script::BIP276::InvalidFormat, /bitcoin-script/)
      end
    end

    describe '.encode_template / .decode_template' do
      it 'round-trips a payload through encode_template and decode_template' do
        encoded = mod.encode_template('my template')
        result  = mod.decode_template(encoded)
        expect(result.prefix).to eq(BSV::Script::BIP276::PREFIX_TEMPLATE)
        expect(result.data).to   eq('my template')
      end

      it 'decode_template raises InvalidFormat on non-template prefix' do
        encoded = mod.encode_script('x')
        expect { mod.decode_template(encoded) }
          .to raise_error(BSV::Script::BIP276::InvalidFormat, /bitcoin-template/)
      end
    end
  end

  describe 'cross-SDK conformance (Go SDK vectors)' do
    BIP276_GO_VECTORS.each do |vec|
      context vec[:label] do
        it "encodes to #{vec[:encoded]}" do
          result = mod.encode(vec[:data], prefix: vec[:prefix], version: vec[:version], network: vec[:network])
          expect(result).to eq(vec[:encoded])
        end

        it "decodes #{vec[:encoded]} correctly" do
          result = mod.decode(vec[:encoded])
          expect(result.prefix).to  eq(vec[:prefix])
          expect(result.version).to eq(vec[:version])
          expect(result.network).to eq(vec[:network])
          expect(result.data).to    eq(vec[:data])
        end
      end
    end
  end

  describe 'round-trip' do
    [
      { prefix: 'bitcoin-script',   version: 1,   network: 1,   data: 'test' },
      { prefix: 'bitcoin-script',   version: 1,   network: 2,   data: 'test' },
      { prefix: 'bitcoin-template', version: 255, network: 255, data: "\x00\xff".b },
      { prefix: 'custom',           version: 100, network: 200, data: 'data' },
      { prefix: 'bitcoin-script',   version: 1,   network: 1,   data: '' }
    ].each do |tc|
      it "preserves all fields for v#{tc[:version]}/n#{tc[:network]}/prefix=#{tc[:prefix]}" do
        encoded = mod.encode(tc[:data], prefix: tc[:prefix], version: tc[:version], network: tc[:network])
        result  = mod.decode(encoded)
        expect(result.prefix).to  eq(tc[:prefix])
        expect(result.version).to eq(tc[:version])
        expect(result.network).to eq(tc[:network])
        expect(result.data).to    eq(tc[:data])
      end
    end
  end
end
