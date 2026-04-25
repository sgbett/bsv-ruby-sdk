# frozen_string_literal: true

require 'spec_helper'

# Vectors from Trezor/CoreBitcoin, canonical for secp256k1.
# Source: https://github.com/trezor/trezor-crypto and
#         https://github.com/oleganza/CoreBitcoin
# Also used by the Go SDK reference implementation.
SECP256K1_RFC6979_VECTORS = [
  {
    private_key: 'cca9fbcc1b41e5a95d369eaa6ddcff73b61a4efaa279cfc6567e8daa39cbaf50',
    message: 'sample',
    expected_der: '3045022100af340daf02cc15c8d5d08d7735dfe6b98a474ed373bdb5fbecf7571be52b3842' \
                  '02205009fb27f37034a9b24b707b7c6b79ca23ddef9e25f7282e8a797efe53a8f124'
  },
  {
    # Private key = 1 (leading zero bytes). S > half-order tests canonicalisation.
    private_key: '0000000000000000000000000000000000000000000000000000000000000001',
    message: 'Satoshi Nakamoto',
    expected_der: '3045022100934b1ea10a4b3c1757e2b0c017d0b6143ce3c9a7e6a4a49860d7a6ab210ee3d8' \
                  '02202442ce9d2b916064108014783e923ec36b49743e2ffa1c4496f01a512aafd9e5'
  },
  {
    # Private key = N-1 (maximum valid key)
    private_key: 'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140',
    message: 'Satoshi Nakamoto',
    expected_der: '3045022100fd567d121db66e382991534ada77a6bd3106f0a1098c231e47993447cd6af2d0' \
                  '02206b39cd0eb1bc8603e159ef5c20a5c8ad685a45b06ce9bebed3f153d10d93bed5'
  },
  {
    private_key: 'f8b8af8ce3c7cca5e300d33939540c10d45ce001b8f252bfbc57ba0342904181',
    message: 'Alan Turing',
    expected_der: '304402207063ae83e7f62bbb171798131b4a0564b956930092b33b07b395615d9ec7e15c' \
                  '022058dfcc1e00a35e1572f366ffe34ba0fc47db1e7189759b9fb233c5b05ab388ea'
  },
  {
    # Same key=1 with long message
    private_key: '0000000000000000000000000000000000000000000000000000000000000001',
    message: 'All those moments will be lost in time, like tears in rain. Time to die...',
    expected_der: '30450221008600dbd41e348fe5c9465ab92d23e3db8b98b873beecd930736488696438cb6b' \
                  '0220547fe64427496db33bf66019dacbf0039c04199abb0122918601db38a72cfc21'
  },
  {
    private_key: 'e91671c46231f833a6406ccbea0e3e392c76c167bac1cb013f6f1013980455c2',
    message: "There is a computer disease that anybody who works with computers knows about. It's a very " \
             'serious disease and it interferes completely with the work. The trouble with computers is ' \
             "that you 'play' with them!",
    expected_der: '3045022100b552edd27580141f3b2a5463048cb7cd3e047b97c9f98076c32dbdf85a68718b' \
                  '0220279fa72dd19bfae05577e06c7c0c1900c371fcd5893f7e1d56a37d30174671f6'
  }
].freeze

RSpec.describe 'RFC 6979 deterministic ECDSA compliance' do # rubocop:disable RSpec/DescribeClass
  SECP256K1_RFC6979_VECTORS.each_with_index do |v, i|
    context "vector #{i}: #{v[:message][0, 30].inspect}" do
      let(:key)  { BSV::Primitives::PrivateKey.from_hex(v[:private_key]) }
      let(:hash) { BSV::Primitives::Digest.sha256(v[:message]) }
      let(:sig)  { key.sign(hash) }

      it 'produces the expected DER signature' do
        expect(sig.to_der.unpack1('H*')).to eq(v[:expected_der])
      end

      it 'has low-S normalisation' do
        expect(sig.s).to be <= BSV::Primitives::Curve::HALF_N
      end

      it 'verifies against the public key' do
        expect(BSV::Primitives::ECDSA.verify(hash, sig, key.public_key.point)).to be true
      end
    end
  end
end
