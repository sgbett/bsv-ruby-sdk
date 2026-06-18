# frozen_string_literal: true

require 'spec_helper'

# Static conformance vectors generated from the TS SDK reference:
# ts-sdk/src/compat/__tests/ECIES.test.ts — key pair (PrivateKey(42), PrivateKey(88))
# Inputs verified byte-for-byte against ECIES.bitcoreEncrypt in ts-sdk.
ECIES_BITCORE_SENDER_PRIV_HEX = '000000000000000000000000000000000000000000000000000000000000002a'
ECIES_BITCORE_RECIPIENT_PRIV_HEX = '0000000000000000000000000000000000000000000000000000000000000058'
# sha256("my message is the hash of this string")
ECIES_BITCORE_PLAINTEXT_HEX = '59cbda0066876e83ed87f63763bd4092ad9134c95e6882717fc699af3b663c0b'
ECIES_BITCORE_IV_HEX = '00000000000000000000000000000000'
# Full 129-byte ciphertext: ephemeral_pub(33) + IV(16) + ciphertext(48) + HMAC(32)
ECIES_BITCORE_CIPHERTEXT_HEX = '02fe8d1eb1bcb3432b1db5833ff5f2226d9cb5e65cee430558c18ed3a3c86ce1af' \
                               '00000000000000000000000000000000' \
                               'df8b7f0c15301e76f3f6ecf99518592242032778e3aa97ad80e5d50d2dfe103a' \
                               '09ba6d7693435738304a7c90b79cc56f' \
                               '6002f1c0811504d49693b4b21e775c4fee51cfc48a854a49b7739d3901c71037'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Primitives::ECIES.bitcore_encrypt conformance' do
  # rubocop:enable RSpec/DescribeClass

  let(:sender_priv)    { BSV::Primitives::PrivateKey.from_hex(ECIES_BITCORE_SENDER_PRIV_HEX) }
  let(:recipient_priv) { BSV::Primitives::PrivateKey.from_hex(ECIES_BITCORE_RECIPIENT_PRIV_HEX) }
  let(:plaintext)      { [ECIES_BITCORE_PLAINTEXT_HEX].pack('H*') }
  let(:fixed_iv)       { [ECIES_BITCORE_IV_HEX].pack('H*') }
  let(:expected_ct)    { [ECIES_BITCORE_CIPHERTEXT_HEX].pack('H*') }

  context 'with TS conformance vector' do
    it 'produces the expected ciphertext for fixed inputs' do
      ct = BSV::Primitives::ECIES.bitcore_encrypt(
        plaintext,
        recipient_priv.public_key,
        private_key: sender_priv,
        iv: fixed_iv
      )
      expect(ct.unpack1('H*')).to eq(ECIES_BITCORE_CIPHERTEXT_HEX)
    end

    it 'decrypts the TS-generated ciphertext to the expected plaintext' do
      result = BSV::Primitives::ECIES.bitcore_decrypt(expected_ct, recipient_priv)
      expect(result.unpack1('H*')).to eq(ECIES_BITCORE_PLAINTEXT_HEX)
    end
  end

  describe '.bitcore_encrypt iv parameter' do
    it 'uses the supplied IV verbatim when provided' do
      ct1 = BSV::Primitives::ECIES.bitcore_encrypt(
        plaintext, recipient_priv.public_key,
        private_key: sender_priv, iv: fixed_iv
      )
      ct2 = BSV::Primitives::ECIES.bitcore_encrypt(
        plaintext, recipient_priv.public_key,
        private_key: sender_priv, iv: fixed_iv
      )
      expect(ct1).to eq(ct2)
    end

    it 'falls back to a random IV when iv is omitted' do
      ct1 = BSV::Primitives::ECIES.bitcore_encrypt(plaintext, recipient_priv.public_key)
      ct2 = BSV::Primitives::ECIES.bitcore_encrypt(plaintext, recipient_priv.public_key)
      expect(ct1).not_to eq(ct2)
    end

    it 'raises ArgumentError when iv is not 16 bytes' do
      expect do
        BSV::Primitives::ECIES.bitcore_encrypt(plaintext, recipient_priv.public_key, iv: "\x00" * 15)
      end.to raise_error(ArgumentError, /16 bytes/)
    end

    it 'raises ArgumentError when iv is empty' do
      expect do
        BSV::Primitives::ECIES.bitcore_encrypt(plaintext, recipient_priv.public_key, iv: ''.b)
      end.to raise_error(ArgumentError, /16 bytes/)
    end

    it 'raises ArgumentError when iv is too long' do
      expect do
        BSV::Primitives::ECIES.bitcore_encrypt(plaintext, recipient_priv.public_key, iv: "\x00" * 17)
      end.to raise_error(ArgumentError, /16 bytes/)
    end

    it 'round-trips: encrypt with explicit iv, decrypt recovers plaintext' do
      ct = BSV::Primitives::ECIES.bitcore_encrypt(
        plaintext, recipient_priv.public_key,
        private_key: sender_priv, iv: fixed_iv
      )
      recovered = BSV::Primitives::ECIES.bitcore_decrypt(ct, recipient_priv)
      expect(recovered).to eq(plaintext)
    end
  end
end
