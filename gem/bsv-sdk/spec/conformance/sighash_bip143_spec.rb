# frozen_string_literal: true

require 'spec_helper'
require 'conformance/support/evaluation_corpus'

# Protocol conformance: BIP-143 (FORKID) sighash vectors
#
# Source corpus: sdk/scripts/evaluation.json (sdk.scripts.evaluation)
# Filter: vectors tagged ["sighash"] where the low byte of hash_type has the
#         FORKID bit (0x40) set AND either the CHRONICLE bit (0x20) is NOT set,
#         OR the source is "teranode" (teranode vectors always use BIP143
#         regardless of the CHRONICLE bit — see ignoreChronicle in the TS runner).
#
# Expected values: the corpus stores sighash digests in reversed (display) byte
# order, consistent with how the TS runner reverses the result before asserting.
#
# Non-FORKID vectors and FORKID+CHRONICLE vectors from bitcoin-sv sources use the
# original transaction digest algorithm (OTDA / legacy). BSV requires FORKID on
# all signatures; the Ruby SDK does not implement OTDA. Those vectors are filtered
# out here — they are exercised only in the TS reference runner.

# Sighash type flag constants (copied from BSV::Transaction::Sighash to avoid
# coupling the filter logic to an SDK constant).
SIGHASH_FORKID_BIT = 0x40
SIGHASH_CHRONICLE_BIT = 0x20

RSpec.describe 'sdk.scripts.evaluation — FORKID sighash vectors' do
  # Collect matching vectors once at describe-time so the count is available
  # in the description and the loop is fast.
  let(:forkid_vectors) do
    collected = []
    EvaluationCorpus.each(tags: %w[sighash]) do |_envelope, vector|
      low_byte = vector['input']['hash_type'] & 0xFF
      is_teranode = vector['input']['sources'].include?('teranode')

      has_forkid    = low_byte.anybits?(SIGHASH_FORKID_BIT)
      has_chronicle = low_byte.anybits?(SIGHASH_CHRONICLE_BIT)

      # BIP143 path: FORKID set, and either no CHRONICLE or teranode source.
      collected << vector if has_forkid && (!has_chronicle || is_teranode)
    end
    collected
  end

  it 'loads at least 700 FORKID sighash vectors from the canonical corpus' do
    expect(forkid_vectors.length).to be >= 700
  end

  it 'computes the correct BIP-143 sighash for every FORKID vector' do
    pass_count = 0
    failures   = []

    forkid_vectors.each do |vector|
      input    = vector['input']
      expected = vector['expected']

      hash_type_u32 = input['hash_type'] & 0xFFFFFFFF

      begin
        tx        = BSV::Transaction::Tx.from_hex(input['tx_hex'])
        subscript = BSV::Script::Script.from_hex(input['script_hex'])

        tx_input = tx.inputs[input['input_index']]
        tx_input.source_satoshis = 0
        tx_input.source_locking_script = subscript

        result = tx.sighash(input['input_index'], hash_type_u32, subscript: subscript)
        # Expected values are in reversed (display) byte order — see corpus README.
        actual_hex = result.reverse.unpack1('H*')

        if actual_hex == expected['regular_hash']
          pass_count += 1
        else
          failures << "#{vector['id']}: expected #{expected['regular_hash']}, got #{actual_hex}"
        end
      rescue StandardError => e
        failures << "#{vector['id']}: #{e.class}: #{e.message}"
      end
    end

    aggregate_failures "FORKID sighash (#{pass_count} passed, #{failures.length} failed of #{forkid_vectors.length})" do
      expect(failures).to be_empty, "#{failures.length} vector(s) failed:\n#{failures.first(20).join("\n")}"
    end
  end
end
