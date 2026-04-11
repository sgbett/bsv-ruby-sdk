# frozen_string_literal: true

require 'spec_helper'

# Protocol conformance: legacy (pre-BIP143) sighash vectors
#
# Vector file: `spec/conformance/vectors/sighash_legacy.json`
# Source: go-sdk `script/interpreter/data/sighash_legacy.json` (vendored
# byte-identical; see `spec/conformance/vectors/README.md` for provenance).
#
# These vectors are Bitcoin Core's legacy (pre-BIP143, pre-UAHF) sighash
# fixtures. BSV does not support legacy sighash on the wire — every BSV
# signature must set the FORKID bit — so these vectors are not executable
# against the Ruby SDK's sighash path.
#
# The file is vendored here purely as a historical reference and in case
# the A2/A3 cluster adds a read-only legacy sighash recogniser (e.g. for
# parsing historical transactions). See the BIP-143 spec's sibling file
# `sighash_bip143_spec.rb` for the modern equivalent.

RSpec.describe 'legacy sighash vectors' do
  it 'vectors are vendored and loadable' do
    rows = ConformanceVectors.load_rows('sighash_legacy.json')
    expect(rows).not_to be_empty
    expect(rows.first.length).to eq(5)
  end

  skip 'legacy sighash is not supported on BSV — vectors kept for reference only'
end
