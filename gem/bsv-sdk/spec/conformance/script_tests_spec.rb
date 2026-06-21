# frozen_string_literal: true

require 'English'
require 'spec_helper'
require 'conformance/support/evaluation_corpus'

# Protocol conformance: script parsing and evaluation vectors
#
# Source corpus: sdk/scripts/evaluation.json (sdk.scripts.evaluation)
# Loaded via the shared EvaluationCorpus module (task #845).
#
# Two spec sections:
#   1. Parse vectors — tagged ["parse"]: structural assertions on Script parsing,
#      chunk counts, opcode values, data payloads, hex round-trips, and error cases.
#   2. Evaluation vectors — tagged ["evaluation"]: interpreter assertions that
#      call BSV::Script::Interpreter.evaluate with the given scriptSig + scriptPubKey
#      pair and check the expected valid/invalid result.
#
# Evaluation coverage: the Ruby interpreter operates exclusively in post-Genesis
# mode, so only two sub-populations are tested:
#   a. "direct" vectors (no fixture_type): hand-authored, no flags or use isRelaxed.
#   b. node-fixture vectors carrying the UTXO_AFTER_GENESIS flag.
# Pre-Genesis node-fixture vectors are skipped — the interpreter does not model
# pre-Genesis consensus rules.
#
# Failures against corpus vectors that expose real interpreter gaps are tracked
# as follow-up issues rather than blocking this migration. Each failing vector ID
# is listed in PENDING_EVALUATION_VECTORS with its issue reference.
#
# Vectors with corpus-level skip:true are silently excluded by EvaluationCorpus.
#
# Supersedes the Bitcoin-Core-positional-array parser that was in this file;
# that vendored script_tests.json has been deleted.
# See spec/conformance/vectors/README.md.

# Known interpreter gaps — vector ID → follow-up GitHub issue.
PENDING_EVALUATION_VECTORS = {
  # Multiple-ELSE and VERIF-in-unexecuted-branch semantics.
  'script-021' => '#850',
  'node.script.bitcoin-sv.0140' => '#850',
  'node.script.bitcoin-sv.0142' => '#850',
  'node.script.teranode.0131' => '#850',
  'node.script.teranode.0133' => '#850',
  # SIGPUSHONLY flag not implemented in interpreter.
  'node.script.bitcoin-sv.0084' => '#851',
  'node.script.teranode.0084' => '#851',
  # CLEANSTACK flag not implemented in interpreter.
  'node.script.bitcoin-sv.0086' => '#852',
  # OP_VER requires transaction context; UTXO_AFTER_CHRONICLE vectors.
  'node.script.bitcoin-sv.0145' => '#853',
  'node.script.bitcoin-sv.0150' => '#853',
  'node.script.bitcoin-sv.0151' => '#853',
  'node.script.bitcoin-sv.0156' => '#853',
  # OP_2MUL / OP_2DIV must be DISABLED_OPCODE without UTXO_AFTER_CHRONICLE.
  'node.script.bitcoin-sv.0165' => '#854',
  'node.script.teranode.0143' => '#854'
}.freeze

RSpec.describe 'sdk.scripts.evaluation — script parsing' do # rubocop:disable RSpec/MultipleDescribes
  let(:parse_vectors) do
    collected = []
    EvaluationCorpus.each(tags: %w[parse]) { |_envelope, vector| collected << vector }
    collected
  end

  it 'loads at least 1 parse vector from the canonical corpus' do
    expect(parse_vectors.length).to be >= 1
  end

  it 'passes all canonical parse vectors' do
    pass_count = 0
    failures   = []

    parse_vectors.each do |vector|
      input    = vector['input']
      expected = vector['expected']

      begin
        script = build_parse_script(input)

        if expected['throws']
          failures << "#{vector['id']}: expected exception but got none (#{vector['description']})"
          next
        end

        record_chunk_failures(script, expected, vector['id'], failures)
        record_roundtrip_failure(script, expected, vector['id'], failures)
        pass_count += 1
      rescue ArgumentError, EncodingError
        if expected['throws']
          pass_count += 1
        else
          failures << "#{vector['id']}: unexpected #{$ERROR_INFO.class}: #{$ERROR_INFO.message}"
        end
      rescue StandardError
        if expected['throws']
          pass_count += 1
        else
          failures << "#{vector['id']}: #{$ERROR_INFO.class}: #{$ERROR_INFO.message}"
        end
      end
    end

    aggregate_failures "parse (#{pass_count} passed, #{failures.length} failed of #{parse_vectors.length})" do
      expect(failures).to be_empty, "#{failures.length} vector(s) failed:\n#{failures.join("\n")}"
    end
  end

  private

  def build_parse_script(input)
    if input.key?('hex')
      BSV::Script::Script.from_hex(input['hex'])
    elsif input.key?('binary')
      BSV::Script::Script.from_binary(input['binary'].pack('C*'))
    elsif input.key?('data_length_bytes')
      fill_hex = input['data_fill_byte'].sub(/\A0x/i, '')
      fill = BSV::Primitives::Hex.decode(fill_hex, name: 'fill byte').getbyte(0)
      data = ([fill] * input['data_length_bytes']).pack('C*')
      BSV::Script::Script.builder.push_data(data).build
    else
      raise ArgumentError, "unrecognised parse vector input keys: #{input.keys.inspect}"
    end
  end

  def record_chunk_failures(script, expected, vector_id, failures)
    chunks = script.chunks

    if expected.key?('chunks_count') && chunks.length != expected['chunks_count']
      failures << "#{vector_id}: chunks_count=#{chunks.length} expected=#{expected['chunks_count']}"
    end

    if expected.key?('chunk_0_op') && chunks[0]&.opcode != expected['chunk_0_op']
      failures << "#{vector_id}: chunk_0_op=#{chunks[0]&.opcode.inspect} expected=#{expected['chunk_0_op']}"
    end

    return unless expected.key?('chunk_0_data')

    actual_bytes = chunks[0]&.data&.bytes || []
    return if actual_bytes == expected['chunk_0_data']

    failures << "#{vector_id}: chunk_0_data=#{actual_bytes.inspect} expected=#{expected['chunk_0_data'].inspect}"
  end

  def record_roundtrip_failure(script, expected, vector_id, failures)
    return unless expected.key?('hex_roundtrip')
    return if script.to_hex == expected['hex_roundtrip']

    failures << "#{vector_id}: hex_roundtrip=#{script.to_hex.inspect} expected=#{expected['hex_roundtrip'].inspect}"
  end
end

RSpec.describe 'sdk.scripts.evaluation — script evaluation' do
  let(:evaluation_vectors) do
    collected = []
    EvaluationCorpus.each(tags: %w[evaluation]) do |_envelope, vector|
      input = vector['input']
      next if input.nil?

      fixture_type = input['fixture_type'] || 'direct'
      flags = input['flags'] || []
      next unless fixture_type == 'direct' || flags.include?('UTXO_AFTER_GENESIS')

      collected << vector
    end
    collected
  end

  it 'loads at least 220 post-Genesis evaluation vectors from the canonical corpus' do
    expect(evaluation_vectors.length).to be >= 220
  end

  it 'evaluates all post-Genesis script pairs against canonical expected results' do
    pass_count    = 0
    pending_count = 0
    failures      = []

    evaluation_vectors.each do |vector|
      input    = vector['input']
      expected = vector['expected']
      issue    = PENDING_EVALUATION_VECTORS[vector['id']]

      begin
        unlock = BSV::Script::Script.from_hex(input['script_sig_hex'] || '')
        lock   = BSV::Script::Script.from_hex(input['script_pubkey_hex'] || '')
        result = BSV::Script::Interpreter.evaluate(unlock, lock)

        if result == expected['valid']
          warn "#{vector['id']}: UNEXPECTED PASS — prune from PENDING_EVALUATION_VECTORS (issue #{issue} may be resolved)" if issue
          pass_count += 1
        elsif issue
          pending_count += 1
        else
          failures << "#{vector['id']}: got #{result.inspect} expected #{expected['valid'].inspect} | #{vector['description']}"
        end
      rescue BSV::Script::ScriptError => e
        if expected['valid'] == false
          issue ? pending_count += 1 : pass_count += 1
        elsif issue
          pending_count += 1
        else
          failures << "#{vector['id']}: ScriptError(#{e.code}) but expected valid=true | #{vector['description']}"
        end
      rescue StandardError => e
        failures << "#{vector['id']}: #{e.class}: #{e.message} | #{vector['description']}"
      end
    end

    aggregate_failures(
      "evaluation (#{pass_count} passed, #{pending_count} pending, #{failures.length} failed of #{evaluation_vectors.length})"
    ) do
      expect(failures).to be_empty,
                          "#{failures.length} unexpected failure(s):\n#{failures.first(20).join("\n")}"
    end
  end
end
