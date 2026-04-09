# frozen_string_literal: true

require 'spec_helper'
require 'base64'

# Protocol conformance: AES-256-GCM symmetric key decryption
#
# Vectors vendored verbatim from go-sdk
# (primitives/ec/testdata/SymmetricKey.vectors.json). Each vector is a
# known ciphertext/key/plaintext triple — the Ruby SDK must produce the
# same plaintext that go-sdk and ts-sdk do for the same inputs.
#
# In the source vectors:
#   - `key` is base64-encoded (32 bytes once decoded)
#   - `ciphertext` is base64-encoded binary (IV + ciphertext + 16-byte tag)
#   - `plaintext` is the raw expected byte string; may be printable ASCII,
#     random-looking bytes, or UTF-8 (e.g. vector 5 contains non-ASCII)

RSpec.describe BSV::Primitives::SymmetricKey do
  describe '#decrypt — canonical vectors' do
    ConformanceVectors.load('SymmetricKey.vectors.json').each_with_index do |v, i|
      it "vector #{i + 1}" do
        key_bytes = Base64.strict_decode64(v['key'])
        ciphertext = Base64.strict_decode64(v['ciphertext'])
        expected_plaintext = v['plaintext'].b

        key = described_class.new(key_bytes)
        decrypted = key.decrypt(ciphertext)

        expect(decrypted.b).to eq(expected_plaintext)
      end
    end
  end
end
