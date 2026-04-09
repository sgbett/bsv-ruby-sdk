# frozen_string_literal: true

require 'spec_helper'

# Protocol conformance: BUMP (BRC-74 BSV Unified Merkle Path) parsing
#
# Vectors are loaded from `spec/conformance/vectors/bump.vectors.json`
# (transliterated from go-sdk `transaction/testdata/bump.go`). See the
# vectors README for provenance notes.

RSpec.describe BSV::Transaction::MerklePath do
  vectors = ConformanceVectors.load('bump.vectors.json')

  describe 'valid BUMPs — parse and round-trip' do
    vectors['valid'].each do |v|
      it "parses and re-serialises #{v['label']}" do
        bump = described_class.from_hex(v['bump'])
        expect(bump.to_hex).to eq(v['bump'])
      end
    end
  end

  describe 'invalid BUMPs — parser rejects' do
    vectors['invalid'].each do |v|
      it "rejects #{v['label']} (#{v['error']})" do
        expect { described_class.from_hex(v['bump']) }.to raise_error(StandardError)
      end
    end
  end
end
