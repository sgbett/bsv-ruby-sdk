# frozen_string_literal: true

require 'spec_helper'
require 'json'

WYCHEPROOF_VECTORS_PATH = File.join(__dir__, 'vectors', 'wycheproof_ecdsa_secp256k1.json')

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Wycheproof ECDSA secp256k1 vectors' do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    skip 'Wycheproof vectors not vendored' unless File.exist?(WYCHEPROOF_VECTORS_PATH)
  end

  data = JSON.parse(File.read(WYCHEPROOF_VECTORS_PATH))

  data['testGroups'].each do |group|
    captured_pub_key_hex = group['publicKey']['uncompressed'] # rubocop:disable RSpec/LeakyLocalVariable

    context "public key #{captured_pub_key_hex[0, 20]}..." do
      let(:pub_key_hex) { captured_pub_key_hex }

      group['tests'].each do |tc|
        it "tcId #{tc['tcId']}: #{tc['comment']}" do
          msg_bytes = [tc['msg']].pack('H*')
          hash = BSV::Primitives::Digest.sha256(msg_bytes)
          sig_bytes = [tc['sig']].pack('H*')

          case tc['result']
          when 'valid'
            sig = BSV::Primitives::Signature.from_der(sig_bytes)
            pub = BSV::Primitives::PublicKey.from_hex(pub_key_hex)
            expect(BSV::Primitives::ECDSA.verify(hash, sig, pub.point)).to be true
          when 'invalid'
            begin
              sig = BSV::Primitives::Signature.from_der(sig_bytes)
              pub = BSV::Primitives::PublicKey.from_hex(pub_key_hex)
              expect(BSV::Primitives::ECDSA.verify(hash, sig, pub.point)).to be false
            rescue ArgumentError
              # Expected — malformed DER or invalid public key encoding
            end
          when 'acceptable'
            # BER/non-canonical DER — BSV uses strict BIP-66 DER, so rejection is correct
            begin
              sig = BSV::Primitives::Signature.from_der(sig_bytes)
              pub = BSV::Primitives::PublicKey.from_hex(pub_key_hex)
              BSV::Primitives::ECDSA.verify(hash, sig, pub.point)
            rescue ArgumentError
              # Expected — strict DER rejects BER encoding
            end
          end
        end
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
