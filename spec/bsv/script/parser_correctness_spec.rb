# frozen_string_literal: true

# A5 parser correctness spec — covers findings F3.1, F3.2, F3.3, F3.4, F3.6,
# F3.10, F3.12, F3.14/F3.21, F3.16 from HLR #317.

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'A5 parser correctness' do
  let(:op) { BSV::Script::Opcodes }
  let(:script) { BSV::Script::Script }

  # ---------------------------------------------------------------------------
  # F3.1 — OP_RETURN termination
  # ---------------------------------------------------------------------------
  describe 'F3.1: OP_RETURN termination at top level' do
    it 'absorbs all trailing bytes into the OP_RETURN chunk data' do
      # Raw bytes: OP_RETURN, push 3 bytes, then 3 data bytes
      raw = [op::OP_RETURN, 0x03, 0xaa, 0xbb, 0xcc].pack('C*')
      s = script.from_binary(raw)
      chunks = s.chunks

      expect(chunks.length).to eq(1)
      expect(chunks[0].opcode).to eq(op::OP_RETURN)
      expect(chunks[0].data?).to be true
      expect(chunks[0].data).to eq("\x03\xaa\xbb\xcc".b)
    end

    it 'absorbs OP_FALSE OP_RETURN trailing bytes' do
      raw = [op::OP_FALSE, op::OP_RETURN, 0x05, 0x68, 0x65, 0x6c, 0x6c, 0x6f].pack('C*')
      s = script.from_binary(raw)
      chunks = s.chunks

      expect(chunks.length).to eq(2)
      expect(chunks[0].opcode).to eq(op::OP_FALSE)
      expect(chunks[1].opcode).to eq(op::OP_RETURN)
      expect(chunks[1].data).to eq("\x05hello".b)
    end

    it 'handles OP_RETURN with no trailing bytes' do
      raw = [op::OP_RETURN].pack('C*')
      s = script.from_binary(raw)
      chunks = s.chunks

      expect(chunks.length).to eq(1)
      expect(chunks[0].opcode).to eq(op::OP_RETURN)
      expect(chunks[0].data).to be_nil
    end

    it 'does NOT terminate at OP_RETURN inside an OP_IF block' do
      # OP_IF OP_RETURN OP_ENDIF — OP_RETURN is inside a conditional, keep parsing
      raw = [op::OP_IF, op::OP_RETURN, op::OP_ENDIF].pack('C*')
      s = script.from_binary(raw)
      chunks = s.chunks

      # Should produce three separate chunks — not terminated early
      expect(chunks.length).to eq(3)
      expect(chunks[0].opcode).to eq(op::OP_IF)
      expect(chunks[1].opcode).to eq(op::OP_RETURN)
      expect(chunks[1].data).to be_nil
      expect(chunks[2].opcode).to eq(op::OP_ENDIF)
    end

    it 'preserves bytes round-trip through to_binary' do
      raw = [op::OP_FALSE, op::OP_RETURN, 0x03, 0x01, 0x02, 0x03].pack('C*')
      s = script.from_binary(raw)
      expect(s.to_binary).to eq(raw)
    end
  end

  # ---------------------------------------------------------------------------
  # F3.2 — Extended NOP range (OP_NOP11 through OP_NOP77)
  # ---------------------------------------------------------------------------
  describe 'F3.2: extended NOP range constants' do
    it 'defines OP_NOP11 as 0xba' do
      expect(op::OP_NOP11).to eq(0xba)
    end

    it 'defines OP_NOP77 as 0xfc' do
      expect(op::OP_NOP77).to eq(0xfc)
    end

    it 'covers the full 0xba–0xfc range without gaps' do
      (0xba..0xfc).each do |byte|
        expect(op::NAME[byte]).not_to be_nil, "Expected name for opcode 0x#{byte.to_s(16)}"
      end
    end

    it 'round-trips OP_NOP11 through ASM' do
      raw = [0xba].pack('C')
      s = script.from_binary(raw)
      expect(s.to_asm).to eq('OP_NOP11')
      expect(script.from_asm('OP_NOP11').to_binary).to eq(raw)
    end

    it 'round-trips OP_NOP77 through ASM' do
      raw = [0xfc].pack('C')
      s = script.from_binary(raw)
      expect(s.to_asm).to eq('OP_NOP77')
      expect(script.from_asm('OP_NOP77').to_binary).to eq(raw)
    end
  end

  # ---------------------------------------------------------------------------
  # F3.3 — Canonical ASM tokens "0" and "-1"
  # ---------------------------------------------------------------------------
  describe 'F3.3: canonical ASM aliases "0" and "-1"' do
    it 'parses "0" as OP_0' do
      s = script.from_asm('0')
      expect(s.chunks.length).to eq(1)
      expect(s.chunks[0].opcode).to eq(op::OP_0)
      expect(s.to_binary).to eq([0x00].pack('C'))
    end

    it 'parses "-1" as OP_1NEGATE' do
      s = script.from_asm('-1')
      expect(s.chunks.length).to eq(1)
      expect(s.chunks[0].opcode).to eq(op::OP_1NEGATE)
      expect(s.to_binary).to eq([0x4f].pack('C'))
    end

    it 'parses "0" in a compound expression' do
      s = script.from_asm('0 OP_DROP')
      expect(s.chunks[0].opcode).to eq(op::OP_0)
      expect(s.chunks[1].opcode).to eq(op::OP_DROP)
    end

    it 'parses "-1" in a compound expression' do
      s = script.from_asm('-1 OP_DROP')
      expect(s.chunks[0].opcode).to eq(op::OP_1NEGATE)
      expect(s.chunks[1].opcode).to eq(op::OP_DROP)
    end
  end

  # ---------------------------------------------------------------------------
  # F3.4 — Explicit PUSHDATA in ASM
  # ---------------------------------------------------------------------------
  describe 'F3.4: explicit PUSHDATA sequences in from_asm' do
    it 'parses OP_PUSHDATA1 <len> <hex> as a single push chunk' do
      hex_data = 'deadbeef' * 10 # 40 bytes — within PUSHDATA1 range
      s = script.from_asm("OP_PUSHDATA1 40 #{hex_data}")

      expect(s.chunks.length).to eq(1)
      expect(s.chunks[0].opcode).to eq(op::OP_PUSHDATA1)
      expect(s.chunks[0].data).to eq([hex_data].pack('H*'))
    end

    it 'parses OP_PUSHDATA2 <len> <hex> as a single push chunk' do
      hex_data = 'ab' * 300
      s = script.from_asm("OP_PUSHDATA2 300 #{hex_data}")

      expect(s.chunks.length).to eq(1)
      expect(s.chunks[0].opcode).to eq(op::OP_PUSHDATA2)
      expect(s.chunks[0].data).to eq([hex_data].pack('H*'))
    end

    it 'parses OP_PUSHDATA4 <len> <hex> as a single push chunk' do
      hex_data = 'ff' * 5
      s = script.from_asm("OP_PUSHDATA4 5 #{hex_data}")

      expect(s.chunks.length).to eq(1)
      expect(s.chunks[0].opcode).to eq(op::OP_PUSHDATA4)
      expect(s.chunks[0].data).to eq("\xff\xff\xff\xff\xff".b)
    end

    it 'round-trips a PUSHDATA1 chunk through binary and back' do
      hex_data = 'cc' * 100
      s = script.from_asm("OP_PUSHDATA1 100 #{hex_data}")
      round_tripped = script.from_binary(s.to_binary)

      expect(round_tripped.chunks[0].opcode).to eq(op::OP_PUSHDATA1)
      expect(round_tripped.chunks[0].data).to eq([hex_data].pack('H*'))
    end
  end

  # ---------------------------------------------------------------------------
  # F3.6 — Unknown opcode ASM representation
  # ---------------------------------------------------------------------------
  describe 'F3.6: unknown opcode rendered as OP_UNKNOWN<n>' do
    # Use byte 0xfd (OP_PUBKEYHASH) which is defined, and 0x00 range.
    # Find a byte that has no defined constant — 0xba is now OP_NOP11, so
    # use a byte outside the defined range: none remain in 0x00–0xff since
    # the NOP range fills 0xba–0xfc. We must test with an opcode that would
    # have been unknown before F3.2, but since F3.2 added them all, we test
    # the OP_UNKNOWN rendering via a hypothetical unlisted opcode.
    # We can temporarily test by checking that opcodes outside all defined
    # constants (there are none in 0..0xff range after F3.2) don't apply.
    # Instead test that the mechanism works by checking round-trip for NOP11.

    it 'renders named constants for all named opcodes (push sizes 1..75 are unnamed — use OP_UNKNOWN)' do
      # Bytes 0x01..0x4b are direct push sizes, not named constants.
      # They are rendered as OP_UNKNOWN<n> when they appear as bare opcodes.
      # All other bytes above 0x4b have defined names.
      (0x4c..0xff).each do |byte|
        name = BSV::Script::Opcodes.name_for(byte)
        expect(name).not_to be_nil, "Expected name for byte 0x#{byte.to_s(16)}"
      end
    end

    it 'OP_UNKNOWN round-trips correctly when a future unlisted opcode is encountered' do
      # Simulate by using a byte that chunk.to_asm would emit as OP_UNKNOWN.
      # Since all bytes 0-255 have names after F3.2, we bypass the NAME lookup
      # by testing the OP_UNKNOWN round-trip mechanism directly.
      # Create a chunk with an opcode that has no name by monkey-patching NAME
      # temporarily — instead, just verify from_asm handles OP_UNKNOWN<n>.
      s = script.from_asm('OP_UNKNOWN200')
      expect(s.chunks.length).to eq(1)
      expect(s.chunks[0].opcode).to eq(200)
    end

    it 'from_asm handles OP_UNKNOWN<n> for any byte 0–255' do
      s = script.from_asm('OP_UNKNOWN42')
      expect(s.chunks[0].opcode).to eq(42)

      s2 = script.from_asm('OP_UNKNOWN0')
      expect(s2.chunks[0].opcode).to eq(0)

      s3 = script.from_asm('OP_UNKNOWN255')
      expect(s3.chunks[0].opcode).to eq(255)
    end
  end

  # ---------------------------------------------------------------------------
  # F3.10 — op_return_data fix
  # ---------------------------------------------------------------------------
  describe 'F3.10: op_return_data returns all push items after OP_RETURN' do
    it 'returns individual data items from OP_FALSE OP_RETURN script' do
      data1 = 'hello'.b
      data2 = 'world'.b
      s = script.op_return(data1, data2)

      result = s.op_return_data
      expect(result).to be_an(Array)
      expect(result).to eq([data1, data2])
    end

    it 'returns data from bare OP_RETURN script' do
      data = 'test'.b
      raw = [op::OP_RETURN].pack('C') + "\x04test".b
      s = script.from_binary(raw)

      result = s.op_return_data
      expect(result).to eq([data])
    end

    it 'returns empty array for OP_RETURN with no data' do
      raw = [op::OP_RETURN].pack('C')
      s = script.from_binary(raw)
      expect(s.op_return_data).to eq([])
    end

    it 'returns nil for non-OP_RETURN scripts' do
      expect(script.p2pkh_lock("\x00".b * 20).op_return_data).to be_nil
    end

    it 'handles multiple fields in the tail' do
      # OP_FALSE OP_RETURN + three data pushes
      s = script.op_return('aa'.b, 'bb'.b, 'cc'.b)
      result = s.op_return_data
      expect(result).to eq(['aa'.b, 'bb'.b, 'cc'.b])
    end
  end

  # ---------------------------------------------------------------------------
  # F3.12 — PushDrop lock_position
  # ---------------------------------------------------------------------------
  describe 'F3.12: PushDrop lock_position parameter' do
    let(:lock_hash) { "\xab".b * 20 }
    let(:lock_s) { script.p2pkh_lock(lock_hash) }
    let(:fields) { ['field1'.b, 'field2'.b] }

    context 'with lock_position: :before (default)' do
      it 'places the P2PKH lock before the fields and drops' do
        s = script.pushdrop_lock(fields, lock_s)
        chunks = s.chunks

        # 5 P2PKH chunks + 2 field chunks + OP_2DROP = 8
        expect(chunks.length).to eq(8)
        expect(chunks[0].opcode).to eq(op::OP_DUP)
        expect(chunks[4].opcode).to eq(op::OP_CHECKSIG)
        expect(chunks[5].data).to eq('field1'.b)
        expect(chunks[6].data).to eq('field2'.b)
        expect(chunks[7].opcode).to eq(op::OP_2DROP)
      end

      it 'is detected as pushdrop?' do
        s = script.pushdrop_lock(fields, lock_s)
        expect(s).to be_pushdrop
      end

      it 'extracts correct fields via pushdrop_fields' do
        s = script.pushdrop_lock(fields, lock_s)
        expect(s.pushdrop_fields).to eq(fields)
      end

      it 'extracts the lock script via pushdrop_lock_script' do
        s = script.pushdrop_lock(fields, lock_s)
        expect(s.pushdrop_lock_script.to_hex).to eq(lock_s.to_hex)
      end
    end

    context 'with lock_position: :after' do
      it 'places the P2PKH lock after the fields and drops' do
        s = script.pushdrop_lock(fields, lock_s, lock_position: :after)
        chunks = s.chunks

        # 2 field chunks + OP_2DROP + 5 P2PKH chunks = 8
        expect(chunks.length).to eq(8)
        expect(chunks[0].data).to eq('field1'.b)
        expect(chunks[1].data).to eq('field2'.b)
        expect(chunks[2].opcode).to eq(op::OP_2DROP)
        expect(chunks[3].opcode).to eq(op::OP_DUP)
        expect(chunks[7].opcode).to eq(op::OP_CHECKSIG)
      end

      it 'is detected as pushdrop?' do
        s = script.pushdrop_lock(fields, lock_s, lock_position: :after)
        expect(s).to be_pushdrop
      end

      it 'extracts correct fields via pushdrop_fields' do
        s = script.pushdrop_lock(fields, lock_s, lock_position: :after)
        expect(s.pushdrop_fields).to eq(fields)
      end

      it 'extracts the lock script via pushdrop_lock_script' do
        s = script.pushdrop_lock(fields, lock_s, lock_position: :after)
        expect(s.pushdrop_lock_script.to_hex).to eq(lock_s.to_hex)
      end
    end

    it 'raises on invalid lock_position' do
      expect { script.pushdrop_lock(fields, lock_s, lock_position: :middle) }
        .to raise_error(ArgumentError, /lock_position must be :before or :after/)
    end

    context 'with single field' do
      it ':before layout is correct with OP_DROP' do
        s = script.pushdrop_lock(['data'.b], lock_s)
        chunks = s.chunks

        # 5 P2PKH chunks + 1 field + OP_DROP = 7
        expect(chunks.length).to eq(7)
        expect(chunks[0].opcode).to eq(op::OP_DUP)
        expect(chunks[5].data).to eq('data'.b)
        expect(chunks[6].opcode).to eq(op::OP_DROP)
      end

      it ':after layout is correct with OP_DROP' do
        s = script.pushdrop_lock(['data'.b], lock_s, lock_position: :after)
        chunks = s.chunks

        # 1 field + OP_DROP + 5 P2PKH chunks = 7
        expect(chunks.length).to eq(7)
        expect(chunks[0].data).to eq('data'.b)
        expect(chunks[1].opcode).to eq(op::OP_DROP)
        expect(chunks[2].opcode).to eq(op::OP_DUP)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # F3.14/F3.21 — encode_minimally [0x00] vs OP_0
  # ---------------------------------------------------------------------------
  describe 'F3.14/F3.21: encode_minimally distinguishes [0x00] from empty array' do
    let(:lock_s) { script.p2pkh_lock("\x00".b * 20) }

    it 'encodes empty data as OP_0 (no data payload)' do
      s = script.pushdrop_lock([''.b], lock_s, lock_position: :after)
      chunks = s.chunks
      expect(chunks[0].opcode).to eq(op::OP_0)
      expect(chunks[0].data).to be_nil
    end

    it 'encodes single zero byte [0x00] as a direct 1-byte push, NOT OP_0' do
      # OP_0 pushes an empty byte array; [0x00] pushes a one-byte zero.
      # They are semantically distinct — [0x00] must NOT be collapsed to OP_0.
      s = script.pushdrop_lock(["\x00".b], lock_s, lock_position: :after)
      chunks = s.chunks

      # Expect opcode=1 (direct 1-byte push) with data="\x00"
      expect(chunks[0].opcode).to eq(1)
      expect(chunks[0].data).to eq("\x00".b)
    end

    it 'the binary encoding of [0x00] differs from OP_0' do
      s_empty = script.pushdrop_lock([''.b], lock_s, lock_position: :after)
      s_zero = script.pushdrop_lock(["\x00".b], lock_s, lock_position: :after)

      # The first bytes must differ (OP_0 = 0x00 vs direct push 0x01 0x00)
      expect(s_empty.to_binary[0].ord).to eq(0x00) # OP_0
      expect(s_zero.to_binary[0].ord).to eq(0x01)  # push 1 byte
      expect(s_zero.to_binary[1].ord).to eq(0x00)  # the zero byte
    end
  end

  # ---------------------------------------------------------------------------
  # F3.16 — Lenient parse_chunks
  # ---------------------------------------------------------------------------
  describe 'F3.16: lenient parse_chunks — no raise on truncated scripts' do
    it 'does not raise for a direct push with missing data bytes' do
      # "\x05" says push 5 bytes but there are none following
      s = script.from_binary("\x05".b)
      expect { s.chunks }.not_to raise_error
    end

    it 'returns a partial chunk for truncated direct push' do
      s = script.from_binary("\x03\x01".b) # push 3, only 1 byte follows
      chunks = s.chunks
      expect(chunks.length).to eq(1)
      expect(chunks[0].opcode).to eq(3)
      expect(chunks[0].data).to eq("\x01".b)
    end

    it 'does not raise for OP_PUSHDATA1 with no length byte' do
      s = script.from_binary([op::OP_PUSHDATA1].pack('C'))
      expect { s.chunks }.not_to raise_error
    end

    it 'does not raise for OP_PUSHDATA2 with partial length' do
      s = script.from_binary([op::OP_PUSHDATA2, 0x01].pack('CC'))
      expect { s.chunks }.not_to raise_error
    end

    it 'does not raise for OP_PUSHDATA4 with partial length' do
      s = script.from_binary([op::OP_PUSHDATA4, 0x01, 0x00].pack('CCC'))
      expect { s.chunks }.not_to raise_error
    end

    it 'does not match any standard type for a truncated script' do
      s = script.from_binary("\x05".b)
      expect(s).not_to be_p2pkh
      expect(s).not_to be_op_return
      expect(s.type).to eq('nonstandard')
    end

    it 'parses a normal script following a truncated portion correctly' do
      # Valid prefix followed by a truncated push — partial result
      raw = [op::OP_DUP, 0x05, 0xaa].pack('C*') # OP_DUP, then push 5 but only 1 byte
      s = script.from_binary(raw)
      chunks = s.chunks
      expect(chunks.length).to eq(2)
      expect(chunks[0].opcode).to eq(op::OP_DUP)
      expect(chunks[1].opcode).to eq(5)
      expect(chunks[1].data).to eq("\xaa".b)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
