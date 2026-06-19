# frozen_string_literal: true

require 'spec_helper'

# Bitcoin Core script test vectors from the Go SDK.
# Source: bsv-blockchain/go-sdk script/interpreter/data/script_tests.json
#
# Format: [scriptSig_asm, scriptPubKey_asm, flags, expected_result, optional_comment]
# Comment-only entries (1-element arrays) and witness vectors are skipped.
#
# The Ruby SDK interpreter runs in BSV post-Genesis mode without configurable
# flags. Vectors requiring flag-specific behaviour may produce different results.
# Mismatches are reported as pending gaps rather than hard failures.

require 'json'

RSpec.describe 'Bitcoin Core script vectors' do
  # Build a reverse mapping: name (without OP_ prefix) → opcode byte
  OPCODE_MAP = {}.tap do |h|
    BSV::Script::Opcodes.constants.select { |c| c.to_s.start_with?('OP_') }.each do |c|
      val = BSV::Script::Opcodes.const_get(c)
      name = c.to_s
      h[name] = val                    # OP_DUP → 0x76
      h[name.sub('OP_', '')] = val     # DUP → 0x76
    end
  end.freeze

  # Encode a Ruby integer as a Bitcoin script number (CScriptNum).
  def self.encode_script_number(num)
    return ''.b if num == 0

    negative = num < 0
    abs_num = num.abs
    bytes = []
    while abs_num > 0
      bytes << (abs_num & 0xFF)
      abs_num >>= 8
    end

    # If the top bit is set, add a sign byte
    if bytes.last.anybits?(0x80)
      bytes << (negative ? 0x80 : 0x00)
    elsif negative
      bytes[-1] |= 0x80
    end

    bytes.pack('C*')
  end

  # Encode data as a minimal push in script binary.
  def self.encode_push(data)
    len = data.bytesize
    if len == 0
      [BSV::Script::Opcodes::OP_0].pack('C')
    elsif len == 1 && data.getbyte(0) >= 1 && data.getbyte(0) <= 16
      [BSV::Script::Opcodes::OP_1 + data.getbyte(0) - 1].pack('C')
    elsif len == 1 && data.getbyte(0) == 0x81
      [BSV::Script::Opcodes::OP_1NEGATE].pack('C')
    elsif len <= 75
      [len].pack('C') + data
    elsif len <= 0xFF
      [BSV::Script::Opcodes::OP_PUSHDATA1, len].pack('CC') + data
    elsif len <= 0xFFFF
      [BSV::Script::Opcodes::OP_PUSHDATA2].pack('C') + [len].pack('v') + data
    else
      [BSV::Script::Opcodes::OP_PUSHDATA4].pack('C') + [len].pack('V') + data
    end
  end

  # Parse Bitcoin Core test assembly format into raw script binary.
  # Returns [binary_string, true] on success or [error_msg, false] on failure.
  def self.parse_bitcoin_asm(asm_str)
    return [''.b, true] if asm_str.nil? || asm_str.strip.empty?

    buf = ''.b
    tokens = asm_str.strip.split(/\s+/)
    i = 0

    while i < tokens.length
      token = tokens[i]

      if token.start_with?("'") && token.end_with?("'") && token.length >= 2
        # Quoted string: push ASCII bytes
        str = token[1..-2]
        buf << encode_push(str.b)
      elsif token.start_with?('0x', '0X')
        # Raw hex bytes — appended directly to the script buffer
        hex = token[2..]
        return ["invalid hex: #{token}", false] if hex.empty? || hex.length.odd?

        buf << [hex].pack('H*')
      elsif token =~ /\A-?\d+\z/
        # Decimal number
        num = token.to_i
        if num == 0
          buf << [BSV::Script::Opcodes::OP_0].pack('C')
        elsif num.between?(1, 16)
          buf << [BSV::Script::Opcodes::OP_1 + num - 1].pack('C')
        elsif num == -1
          buf << [BSV::Script::Opcodes::OP_1NEGATE].pack('C')
        else
          data = encode_script_number(num)
          buf << encode_push(data)
        end
      elsif %w[PUSHDATA1 OP_PUSHDATA1].include?(token)
        # PUSHDATA1 <len_hex> <data_hex>
        return ['PUSHDATA1: missing args', false] if i + 2 >= tokens.length

        len_hex = tokens[i + 1].sub(/\A0x/i, '')
        data_hex = tokens[i + 2].sub(/\A0x/i, '')
        len = [len_hex].pack('H*').unpack1('C')
        buf << [BSV::Script::Opcodes::OP_PUSHDATA1, len].pack('CC')
        buf << [data_hex].pack('H*') unless data_hex.empty?
        i += 2
      elsif %w[PUSHDATA2 OP_PUSHDATA2].include?(token)
        return ['PUSHDATA2: missing args', false] if i + 2 >= tokens.length

        len_hex = tokens[i + 1].sub(/\A0x/i, '')
        data_hex = tokens[i + 2].sub(/\A0x/i, '')
        len = [len_hex].pack('H*').unpack1('v')
        buf << ([BSV::Script::Opcodes::OP_PUSHDATA2].pack('C') + [len].pack('v'))
        buf << [data_hex].pack('H*') unless data_hex.empty?
        i += 2
      elsif %w[PUSHDATA4 OP_PUSHDATA4].include?(token)
        return ['PUSHDATA4: missing args', false] if i + 2 >= tokens.length

        len_hex = tokens[i + 1].sub(/\A0x/i, '')
        data_hex = tokens[i + 2].sub(/\A0x/i, '')
        len = [len_hex].pack('H*').unpack1('V')
        buf << ([BSV::Script::Opcodes::OP_PUSHDATA4].pack('C') + [len].pack('V'))
        buf << [data_hex].pack('H*') unless data_hex.empty?
        i += 2
      elsif OPCODE_MAP.key?(token)
        buf << [OPCODE_MAP[token]].pack('C')
      elsif OPCODE_MAP.key?("OP_#{token}")
        buf << [OPCODE_MAP["OP_#{token}"]].pack('C')
      else
        return ["unknown token: #{token}", false]
      end

      i += 1
    end

    [buf, true]
  rescue StandardError => e
    [e.message, false]
  end

  # Flags that indicate features BSV doesn't support or the interpreter can't toggle
  UNSUPPORTED_FLAGS = %w[
    WITNESS TAPROOT DISCOURAGE_UPGRADABLE_WITNESS_PROGRAM DISCOURAGE_UPGRADABLE_NOPS
  ].freeze

  let(:all_vectors) do
    JSON.parse(File.read(File.expand_path('../../../fixtures/script_tests.json', __dir__)))
  end

  let(:test_vectors) do
    all_vectors.select do |v|
      # Must be a test vector (4 or 5 elements), not a comment
      next false unless v.is_a?(Array) && v.length >= 4

      # Skip witness vectors (first element is an array)
      next false if v[0].is_a?(Array)

      # All elements should be strings
      v[0..3].all?(String)
    end
  end

  let(:known_failures) do
    JSON.parse(
      File.read(File.expand_path('../../../fixtures/script_vectors_known_failures.json', __dir__))
    )
  end

  it 'loads the fixture file with test vectors' do
    expect(all_vectors).to be_an(Array)
    expect(test_vectors.length).to be > 100
  end

  it 'evaluates Bitcoin Core script vectors' do
    pass_count = 0
    expected_fail_pass = 0
    known_fail_count = 0
    unexpected_mismatches = []
    stale_known_failures = []
    parse_error_count = 0
    skipped_count = 0

    test_vectors.each_with_index do |vec, idx|
      sig_asm = vec[0]
      pubkey_asm = vec[1]
      flags_str = vec[2]
      expected = vec[3]
      comment = vec[4] || ''
      flags = flags_str.split(',')

      if flags.any? { |f| UNSUPPORTED_FLAGS.include?(f) }
        skipped_count += 1
        next
      end

      sig_bin, sig_ok = self.class.parse_bitcoin_asm(sig_asm)
      pub_bin, pub_ok = self.class.parse_bitcoin_asm(pubkey_asm)

      unless sig_ok && pub_ok
        parse_error_count += 1
        next
      end

      unlock = BSV::Script::Script.new(sig_bin)
      lock = BSV::Script::Script.new(pub_bin)

      begin
        result = BSV::Script::Interpreter.evaluate(unlock, lock)
        actual_ok = result ? true : false
      rescue StandardError
        actual_ok = false
      end

      expected_ok = (expected == 'OK')

      if actual_ok == expected_ok
        if known_failures.key?(idx.to_s)
          # Vector matches expectation but is still tagged as a known failure —
          # the interpreter has improved past the recorded gap. Surface so the
          # known-failures list can be trimmed back to truth (T3, #806).
          stale_known_failures << "[#{idx}] now matches expected (#{expected}): " \
                                  "remove entry — was '#{known_failures[idx.to_s]}'"
        else
          expected_ok ? pass_count += 1 : expected_fail_pass += 1
        end
      elsif known_failures.key?(idx.to_s)
        known_fail_count += 1
      else
        direction = expected_ok ? 'should pass but failed' : 'should fail but passed'
        unexpected_mismatches << "[#{idx}] #{direction}: sig=#{sig_asm.inspect[0, 40]} " \
                                 "pub=#{pubkey_asm.inspect[0, 40]} flags=#{flags_str} #{comment}"
      end
    end

    total = pass_count + expected_fail_pass + known_fail_count +
            unexpected_mismatches.length + stale_known_failures.length

    # Report known failures count for visibility
    warn "Script vectors: #{pass_count + expected_fail_pass} pass, " \
         "#{known_fail_count} known failures, " \
         "#{parse_error_count} parse errors, #{skipped_count} skipped"

    # Any vector NOT in the known-failures list is a hard failure
    expect(unexpected_mismatches).to eq([]),
                                     "#{unexpected_mismatches.length} unexpected mismatches out of #{total} vectors:\n" \
                                     "#{unexpected_mismatches.join("\n")}"

    # And any vector tagged as a known failure that has started passing is also
    # a hard failure — forces the known-failures list to stay honest about
    # what's still broken vs. what has been fixed.
    expect(stale_known_failures).to eq([]),
                                    "#{stale_known_failures.length} known-failure entries now pass " \
                                    "and must be removed from script_vectors_known_failures.json:\n" \
                                    "#{stale_known_failures.join("\n")}"
  end
end
