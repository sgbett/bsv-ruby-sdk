# frozen_string_literal: true

require 'spec_helper'

# Protocol conformance: SHA-256 hashing
#
# Test vectors from the canonical conformance corpus:
#   tmp/conformance-vectors/conformance/vectors/sdk/crypto/sha256.json
#
# Covers single SHA-256 and double-SHA-256 (hash256) across UTF-8 and hex-encoded inputs.

RSpec.describe 'SDK SHA-256 conformance (sdk.crypto.sha256)' do
  ConformanceVectors.each_canonical_vector('sdk.crypto.sha256') do |_envelope, v|
    it "#{v['id']}: #{v['description']}" do
      message_hex = v.dig('input', 'encoding') == 'hex' ? v.dig('input', 'message') : nil
      message_utf8 = v.dig('input', 'encoding') == 'utf8' ? v.dig('input', 'message') : nil
      double_hash = v.dig('input', 'double') == true

      data = if message_hex
               [message_hex].pack('H*')
             else
               message_utf8.encode('BINARY')
             end

      result = if double_hash
                 BSV::Primitives::Digest.hash256(data)
               else
                 BSV::Primitives::Digest.sha256(data)
               end

      expect(result.unpack1('H*')).to eq(v.dig('expected', 'hash'))
    end
  end
end
