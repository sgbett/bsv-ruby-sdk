# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::MCP::Tools::AddressInput do
  let(:private_key) do
    BSV::Primitives::PrivateKey.from_hex('0101010101010101010101010101010101010101010101010101010101010101')
  end
  let(:mainnet_wif) { private_key.to_wif }
  let(:testnet_wif) { private_key.to_wif(network: :testnet) }
  # U+0100, the first character past Base58::DECODE_MAP's 256 entries (TypeError path)
  let(:beyond_latin1) { 0x100.chr(Encoding::UTF_8) }
  # Ten 2-byte characters make a 20-byte String, which Script.p2pkh_lock would take as a raw hash
  let(:twenty_byte_text) { 0xE9.chr(Encoding::UTF_8) * 10 }
  # A mainnet address whose hash is the literal below.
  let(:known_address) { '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa' }
  let(:known_hash_hex) { '62e907b15cbf27d5425399ebf6f0fb50ebb88f18' }
  let(:known_testnet_address) do
    BSV::Primitives::Base58.check_encode("\x6f".b + [known_hash_hex].pack('H*'))
  end

  # Valid checksum and version byte, +length+ payload bytes.
  def encoded(version, length)
    BSV::Primitives::Base58.check_encode(version.b + ("\x11".b * length))
  end

  describe '.pubkey_hash' do
    it 'returns the literal hash of a mainnet address' do
      expect(described_class.pubkey_hash(known_address, :mainnet).unpack1('H*')).to eq(known_hash_hex)
    end

    it 'returns the same hash for the testnet address of that hash' do
      expect(described_class.pubkey_hash(known_testnet_address, :testnet).unpack1('H*')).to eq(known_hash_hex)
    end

    it 'keeps an all-zero hash' do
      address = '1111111111111111111114oLvT2'
      expect(described_class.pubkey_hash(address, :mainnet)).to eq("\x00".b * 20)
    end

    it 'returns a frozen, 20-byte, binary String' do
      hash = described_class.pubkey_hash(known_address, :mainnet)
      expect(hash).to be_frozen
      expect(hash.bytesize).to eq(20)
      expect(hash.encoding).to eq(Encoding::BINARY)
    end

    it 'returns the hash of an address derived from a key' do
      address = private_key.public_key.address(network: :testnet)
      expect(described_class.pubkey_hash(address, :testnet)).to eq(private_key.public_key.hash160)
    end

    it 'names the argument in the error' do
      expect { described_class.pubkey_hash('nope', :mainnet, name: 'to_address') }
        .to raise_error(ArgumentError, 'to_address is not a P2PKH address for mainnet')
    end

    it 'defaults the argument name to input' do
      expect { described_class.pubkey_hash('nope', :testnet) }
        .to raise_error(ArgumentError, 'input is not a P2PKH address for testnet')
    end

    it 'checks the length before decoding' do
      expect { described_class.pubkey_hash('1' * 65, :mainnet, name: 'to_address') }
        .to raise_error(ArgumentError, 'to_address is longer than 64 characters')
    end

    describe 'with malformed input' do
      let(:message) { 'input is not a P2PKH address for mainnet' }

      # 17GuhfEA8T1Zvj872QAa is 0x00 plus ten 0x11 bytes; the second is 0x00
      # plus thirteen zero bytes. Script.p2pkh_lock would take either as a raw
      # 20-byte hash.
      %w[17GuhfEA8T1Zvj872QAa 111111111111114xynwY].each do |short|
        it "rejects the 20-character short-payload address #{short}" do
          expect(short.length).to eq(20)
          expect { described_class.pubkey_hash(short, :mainnet) }.to raise_error(ArgumentError, message)
        end
      end

      [0, 9, 11, 19, 21, 33].each do |length|
        it "rejects a mainnet payload of #{length} bytes" do
          expect { described_class.pubkey_hash(encoded("\x00", length), :mainnet) }
            .to raise_error(ArgumentError, message)
        end
      end

      [0, 9, 10, 19, 21].each do |length|
        it "rejects a testnet payload of #{length} bytes" do
          expect { described_class.pubkey_hash(encoded("\x6f", length), :testnet) }
            .to raise_error(ArgumentError, 'input is not a P2PKH address for testnet')
        end
      end

      it 'rejects a P2SH address' do
        p2sh = encoded("\x05", 10)
        expect(p2sh.length).to eq(20)
        expect { described_class.pubkey_hash(p2sh, :mainnet) }.to raise_error(ArgumentError, message)
      end

      it 'rejects a P2SH address with a 20-byte hash' do
        expect { described_class.pubkey_hash(encoded("\x05", 20), :mainnet) }.to raise_error(ArgumentError, message)
      end

      it 'rejects an address for the other network' do
        expect { described_class.pubkey_hash(known_testnet_address, :mainnet) }.to raise_error(ArgumentError, message)
        expect { described_class.pubkey_hash(known_address, :testnet) }
          .to raise_error(ArgumentError, 'input is not a P2PKH address for testnet')
      end

      it 'rejects a WIF as an address' do
        expect { described_class.pubkey_hash(mainnet_wif, :mainnet) }.to raise_error(ArgumentError, message)
      end

      it 'rejects non-strings' do
        [nil, 42, [known_address], { a: 1 }].each do |value|
          expect { described_class.pubkey_hash(value, :mainnet) }.to raise_error(ArgumentError, message)
        end
      end

      it 'rejects 20 raw binary bytes' do
        expect { described_class.pubkey_hash("\x11".b * 20, :mainnet) }.to raise_error(ArgumentError, message)
      end

      it 'rejects non-ASCII text' do
        expect { described_class.pubkey_hash(twenty_byte_text, :mainnet) }.to raise_error(ArgumentError, message)
      end

      it 'rejects a character above U+00FF' do
        expect { described_class.pubkey_hash("#{known_address[0, 19]}#{beyond_latin1}", :mainnet) }
          .to raise_error(ArgumentError, message)
      end

      it 'rejects a paymail' do
        expect { described_class.pubkey_hash('alice@example.com', :mainnet) }.to raise_error(ArgumentError, message)
      end

      it 'rejects surrounding whitespace' do
        expect { described_class.pubkey_hash(" #{known_address}", :mainnet) }.to raise_error(ArgumentError, message)
        expect { described_class.pubkey_hash("#{known_address}\n", :mainnet) }.to raise_error(ArgumentError, message)
      end

      it 'rejects an empty string' do
        expect { described_class.pubkey_hash('', :mainnet) }.to raise_error(ArgumentError, message)
      end

      it 'rejects a bad checksum' do
        expect { described_class.pubkey_hash("#{known_address[0..-2]}x", :mainnet) }
          .to raise_error(ArgumentError, message)
        expect { described_class.pubkey_hash('1' * 20, :mainnet) }.to raise_error(ArgumentError, message)
      end

      it 'never echoes the input' do
        bad = "#{known_address[0..-2]}x"
        expect { described_class.pubkey_hash(bad, :mainnet) }
          .to raise_error(ArgumentError) { |error| expect(error.message).not_to include(bad) }
      end
    end
  end

  # The fixed message, with no 4-character run of the input in it.
  def expect_fixed_uncompressed_message(error, name, input)
    expect(error.message).to eq("#{name} is an uncompressed WIF private key; only compressed WIFs are supported")
    expect(input.chars.each_cons(4).map(&:join).select { |run| error.message.include?(run) }).to be_empty
  end

  describe '.private_key' do
    let(:message) { 'wif is not a valid WIF private key for mainnet' }

    def wif_with_payload(version, bytes)
      BSV::Primitives::Base58.check_encode(version.b + bytes.b)
    end

    it 'returns the key of a mainnet WIF' do
      expect(described_class.private_key(mainnet_wif, :mainnet).to_hex).to eq(private_key.to_hex)
    end

    it 'returns the key of a testnet WIF' do
      expect(described_class.private_key(testnet_wif, :testnet).to_hex).to eq(private_key.to_hex)
    end

    it 'rejects an uncompressed WIF on either network without echoing it' do
      { "\x80" => :mainnet, "\xef" => :testnet }.each do |version, net_sym|
        wif = wif_with_payload(version, private_key.to_bytes)
        expect { described_class.private_key(wif, net_sym) }
          .to raise_error(ArgumentError) { |error| expect_fixed_uncompressed_message(error, 'wif', wif) }
      end
    end

    it 'keeps the network-mismatch error' do
      expect { described_class.private_key(testnet_wif, :mainnet) }
        .to raise_error(ArgumentError, 'WIF private key is not for mainnet')
      expect { described_class.private_key(mainnet_wif, :testnet) }
        .to raise_error(ArgumentError, 'WIF private key is not for testnet')
    end

    it 'names the argument in the error' do
      expect { described_class.private_key('nope', :testnet, name: 'key') }
        .to raise_error(ArgumentError, 'key is not a valid WIF private key for testnet')
    end

    it 'checks the length before decoding' do
      expect { described_class.private_key('1' * 65, :mainnet) }
        .to raise_error(ArgumentError, 'wif is longer than 64 characters')
    end

    {
      'an invalid Base58 character' => ->(wif) { "0#{wif[1..]}" },
      'a bad checksum' => ->(wif) { "#{wif[0..-2]}#{wif[-1] == '2' ? '3' : '2'}" },
      'a character above U+00FF' => ->(wif) { "#{0x100.chr(Encoding::UTF_8)}#{wif[1..]}" },
      'whitespace' => ->(wif) { " #{wif}" },
      'an empty string' => ->(_wif) { '' }
    }.each do |label, mutate|
      it "rejects a WIF with #{label}" do
        input = mutate.call(mainnet_wif)
        expect { described_class.private_key(input, :mainnet) }
          .to raise_error(ArgumentError, message)
      end
    end

    it 'rejects wrong-length payloads' do
      ["\x11".b * 31, "\x11".b * 34, ''].each do |bytes|
        expect { described_class.private_key(wif_with_payload("\x80", bytes), :mainnet) }
          .to raise_error(ArgumentError, message)
      end
    end

    it 'rejects a bad compression flag' do
      ["\x02".b, "\x11".b].each do |flag|
        wif = wif_with_payload("\x80", private_key.to_bytes + flag)
        expect { described_class.private_key(wif, :mainnet) }.to raise_error(ArgumentError, message)
      end
    end

    it 'rejects an unknown prefix, such as an address' do
      expect { described_class.private_key(known_address, :mainnet) }.to raise_error(ArgumentError, message)
    end

    it 'rejects a zero key and one above the curve order' do
      [("\x00".b * 32), ("\xff".b * 32)].each do |bytes|
        expect { described_class.private_key(wif_with_payload("\x80", "#{bytes}\x01"), :mainnet) }
          .to raise_error(ArgumentError, message)
      end
    end

    it 'rejects non-strings' do
      [nil, 42, [mainnet_wif]].each do |value|
        expect { described_class.private_key(value, :mainnet) }.to raise_error(ArgumentError, message)
      end
    end
  end

  describe '.resolve' do
    it 'returns a mainnet address as is' do
      expect(described_class.resolve(known_address, :mainnet)).to eq(known_address)
    end

    it 'returns a testnet address as is' do
      expect(described_class.resolve(known_testnet_address, :testnet)).to eq(known_testnet_address)
    end

    it 'derives the address of a WIF for the network when allowed' do
      expect(described_class.resolve(mainnet_wif, :mainnet, allow_wif: true))
        .to eq(private_key.public_key.address(network: :mainnet))
      expect(described_class.resolve(testnet_wif, :testnet, allow_wif: true))
        .to eq(private_key.public_key.address(network: :testnet))
    end

    it 'rejects an uncompressed WIF on either network without echoing it' do
      { "\x80" => :mainnet, "\xef" => :testnet }.each do |version, net_sym|
        wif = BSV::Primitives::Base58.check_encode(version.b + private_key.to_bytes)
        expect { described_class.resolve(wif, net_sym, allow_wif: true) }
          .to raise_error(ArgumentError) { |error| expect_fixed_uncompressed_message(error, 'input', wif) }
      end
    end

    it 'names the argument in the uncompressed WIF error' do
      wif = BSV::Primitives::Base58.check_encode("\x80".b + private_key.to_bytes)
      expect { described_class.resolve(wif, :mainnet, allow_wif: true, name: 'key') }
        .to raise_error(ArgumentError, /\Akey is an uncompressed WIF/)
    end

    it 'rejects a WIF unless allowed' do
      expect { described_class.resolve(mainnet_wif, :mainnet) }
        .to raise_error(ArgumentError, 'input is not a P2PKH address for mainnet')
    end

    it 'rejects a WIF for the other network' do
      expect { described_class.resolve(testnet_wif, :mainnet, allow_wif: true) }
        .to raise_error(ArgumentError, 'input is not a P2PKH address or WIF private key for mainnet')
    end

    it 'names the argument when asked' do
      expect { described_class.resolve('nope', :mainnet, name: 'address') }
        .to raise_error(ArgumentError, 'address is not a P2PKH address for mainnet')
    end

    it 'checks the length before decoding' do
      expect { described_class.resolve('1' * 65, :mainnet, name: 'address') }
        .to raise_error(ArgumentError, 'address is longer than 64 characters')
    end

    it 'rejects the 20-character short-payload strings' do
      %w[17GuhfEA8T1Zvj872QAa 111111111111114xynwY].each do |short|
        expect { described_class.resolve(short, :mainnet) }
          .to raise_error(ArgumentError, 'input is not a P2PKH address for mainnet')
      end
    end

    it 'rejects a character above U+00FF and non-strings' do
      ["#{known_address[0, 19]}#{beyond_latin1}", nil, 42].each do |value|
        expect { described_class.resolve(value, :mainnet) }
          .to raise_error(ArgumentError, 'input is not a P2PKH address for mainnet')
      end
    end

    it 'rejects P2SH' do
      expect { described_class.resolve(encoded("\x05", 20), :mainnet) }
        .to raise_error(ArgumentError, 'input is not a P2PKH address for mainnet')
    end
  end
end
