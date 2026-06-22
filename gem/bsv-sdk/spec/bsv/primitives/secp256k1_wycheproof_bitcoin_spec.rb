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

              if verified && !sig.low_s?
                # High-S signature malleability case. The !sig.low_s? check (not hardcoded
                # tcIds) is used so this categorisation generalises to future vector updates.
                #
                # These vectors are marked `invalid` by Wycheproof because Bitcoin's
                # non-malleability policy rejects high-S signatures (BIP-62 rule 5). However,
                # a high-S signature is mathematically valid ECDSA — the verification equation
                # holds for any s in (0, N). Raw ECDSA.verify correctly returns true.
                #
                # Low-S enforcement is a protocol policy decision that belongs in the script
                # interpreter (BSV::Script::Interpreter), gated on the appropriate script
                # flags — matching the Go SDK's architecture. It must NOT be embedded in the
                # cryptographic primitive.
                #
                # Known cases in this vector set:
                #   tcId 1   — flagged SignatureMalleabilityBitcoin; s is the high-S form of
                #              a valid signature (s > N/2)
                #   tcId 388 — flagged ArithmeticError; s = HALF_N + 1 (boundary edge case)
                #
                # See: docs/reference/wycheproof-malleability-analysis.md
                expect(verified).to be true
                expect(sig.low_s?).to be false
              else
                # Genuinely invalid: malformed values, out-of-range components, or arithmetic
                # error unrelated to high-S malleability. ECDSA.verify correctly returns false.
                expect(verified).to be false
              end
            rescue ArgumentError
              # Expected — malformed DER or invalid public key encoding makes the vector
              # genuinely unverifiable at the parsing level, not merely a policy rejection.
            end
          end
        end
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
