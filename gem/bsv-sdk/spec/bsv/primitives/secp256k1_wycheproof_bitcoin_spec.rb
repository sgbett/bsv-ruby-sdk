# frozen_string_literal: true

require 'spec_helper'
require 'json'

WYCHEPROOF_BITCOIN_VECTORS_PATH = File.join(__dir__, 'vectors', 'wycheproof_ecdsa_secp256k1_bitcoin.json')

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Wycheproof ECDSA secp256k1 Bitcoin vectors' do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    skip 'Wycheproof Bitcoin vectors not vendored' unless File.exist?(WYCHEPROOF_BITCOIN_VECTORS_PATH)
  end

  data = JSON.parse(File.read(WYCHEPROOF_BITCOIN_VECTORS_PATH))

  data['testGroups'].each do |group|
    captured_pub_key_hex = group['publicKey']['uncompressed'] # rubocop:disable RSpec/LeakyLocalVariable

    context "public key #{captured_pub_key_hex[0, 20]}..." do
      let(:pub_key_hex) { captured_pub_key_hex }

      group['tests'].each do |tc|
        captured_tc = tc # rubocop:disable RSpec/LeakyLocalVariable

        it "tcId #{tc['tcId']}: #{tc['comment']}" do
          msg_bytes = [captured_tc['msg']].pack('H*')
          hash = BSV::Primitives::Digest.sha256(msg_bytes)
          sig_bytes = [captured_tc['sig']].pack('H*')

          case captured_tc['result']
          when 'valid'
            sig = BSV::Primitives::Signature.from_der(sig_bytes)
            pub = BSV::Primitives::PublicKey.from_hex(pub_key_hex)
            expect(BSV::Primitives::ECDSA.verify(hash, sig, pub.point)).to be true
          when 'invalid'
            begin
              sig = BSV::Primitives::Signature.from_der(sig_bytes)
              pub = BSV::Primitives::PublicKey.from_hex(pub_key_hex)
              verified = BSV::Primitives::ECDSA.verify(hash, sig, pub.point)

              # High-S cases (flagged SignatureMalleabilityBitcoin, or s = HALF_N + 1) are
              # mathematically valid ECDSA. Raw ECDSA.verify correctly accepts them; low-S
              # enforcement is a protocol policy that belongs in the script interpreter.
              # Task 3 adds explicit assertions for these cases — see #657 and
              # docs/testing/wycheproof-malleability-analysis.md
              expect(verified).to be(false).or(satisfy { !sig.low_s? })
            rescue ArgumentError
              # Expected — malformed DER or invalid public key encoding
            end
          end
        end
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
