# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::Wallet::Wire Reader/Writer' do # rubocop:disable RSpec/DescribeClass
  let(:writer) { BSV::Wallet::Wire::Writer.new }

  def round_trip(&)
    yield writer
    BSV::Wallet::Wire::Reader.new(writer.buf)
  end

  # --- varint ---

  describe 'write_varint / read_varint' do
    [0, 1, 0xFC, 0xFD, 0xFF, 0xFFFF, 0xFFFF + 1, 0xFFFFFFFF, 0xFFFFFFFF + 1].each do |n|
      it "round-trips varint #{n}" do
        reader = round_trip { |w| w.write_varint(n) }
        expect(reader.read_varint).to eq(n)
      end
    end
  end

  # --- str_with_varint_len ---

  describe 'write_str_with_varint_len / read_str_with_varint_len' do
    it 'round-trips an ASCII string' do
      reader = round_trip { |w| w.write_str_with_varint_len('hello') }
      expect(reader.read_str_with_varint_len).to eq('hello')
    end

    it 'round-trips a UTF-8 string' do
      reader = round_trip { |w| w.write_str_with_varint_len('héllo') }
      expect(reader.read_str_with_varint_len).to eq('héllo')
    end

    it 'round-trips an empty string' do
      reader = round_trip { |w| w.write_str_with_varint_len('') }
      expect(reader.read_str_with_varint_len).to eq('')
    end

    it 'uses byte length for the varint prefix (UTF-8 multi-byte chars)' do
      str = "\xC3\xA9" * 10 # 'é' × 10 = 20 bytes, 10 chars
      writer.write_str_with_varint_len(str)
      expect(writer.buf.getbyte(0)).to eq(20)
    end
  end

  # --- optional_bool ---

  describe 'write_optional_bool / read_optional_bool' do
    { nil => 0xFF, false => 0x00, true => 0x01 }.each do |value, byte|
      it "#{value.inspect} encodes as byte 0x#{byte.to_s(16).upcase.rjust(2, '0')}" do
        round_trip { |w| w.write_optional_bool(value) }
        raw_byte = BSV::Wallet::Wire::Reader.new(writer.buf).read_byte
        expect(raw_byte).to eq(byte)
      end

      it "byte 0x#{byte.to_s(16).upcase.rjust(2, '0')} decodes back to #{value.inspect}" do
        reader = round_trip { |w| w.write_optional_bool(value) }
        expect(reader.read_optional_bool).to eq(value)
      end
    end
  end

  # --- satoshis ---

  describe 'write_satoshis / read_satoshis' do
    [0, 1, 1000, 21_000_000 * (10**8)].each do |n|
      it "round-trips satoshi value #{n}" do
        reader = round_trip { |w| w.write_satoshis(n) }
        expect(reader.read_satoshis).to eq(n)
      end
    end

    it 'writes exactly 8 bytes' do
      writer.write_satoshis(42)
      expect(writer.buf.bytesize).to eq(8)
    end

    it 'uses little-endian encoding' do
      writer.write_satoshis(1)
      expect(writer.buf.unpack1('H*')).to eq('0100000000000000')
    end
  end

  # --- outpoint ---

  describe 'write_outpoint / read_outpoint' do
    let(:display_txid) { 'ab' * 32 }

    it 'round-trips an outpoint' do
      reader = round_trip { |w| w.write_outpoint(display_txid, 3) }
      result = reader.read_outpoint
      expect(result[:txid_hex]).to eq(display_txid)
      expect(result[:vout]).to eq(3)
    end

    it 'writes the txid in wire order (reversed from display hex)' do
      writer.write_outpoint(display_txid, 0)
      wire_txid_hex = writer.buf.byteslice(0, 32).unpack1('H*')
      expect(wire_txid_hex).to eq(display_txid.scan(/../).reverse.join)
    end

    it 'writes vout as 4-byte little-endian' do
      writer.write_outpoint(display_txid, 0x0102)
      vout_bytes = writer.buf.byteslice(32, 4).unpack1('H*')
      expect(vout_bytes).to eq('02010000')
    end

    it 'rejects invalid display txid' do
      expect { writer.write_outpoint('not-a-txid', 0) }.to raise_error(ArgumentError)
    end

    it 'round-trips vout 0' do
      reader = round_trip { |w| w.write_outpoint(display_txid, 0) }
      expect(reader.read_outpoint[:vout]).to eq(0)
    end

    it 'round-trips max uint32 vout' do
      reader = round_trip { |w| w.write_outpoint(display_txid, 0xFFFFFFFF) }
      expect(reader.read_outpoint[:vout]).to eq(0xFFFFFFFF)
    end
  end

  # --- multiple fields in sequence ---

  describe 'sequential read/write' do
    it 'reads fields in the same order they were written' do
      writer.write_byte(42)
      writer.write_str_with_varint_len('hello')
      writer.write_optional_bool(true)
      writer.write_satoshis(1000)
      writer.write_varint(0xFF)

      reader = BSV::Wallet::Wire::Reader.new(writer.buf)
      expect(reader.read_byte).to eq(42)
      expect(reader.read_str_with_varint_len).to eq('hello')
      expect(reader.read_optional_bool).to be(true)
      expect(reader.read_satoshis).to eq(1000)
      expect(reader.read_varint).to eq(0xFF)
      expect(reader.remaining).to eq(0)
    end
  end

  # --- read_remaining ---

  describe 'Reader#read_remaining' do
    it 'returns remaining bytes after partial read' do
      writer.write_byte(1)
      writer.write_bytes("\x02\x03\x04")
      reader = BSV::Wallet::Wire::Reader.new(writer.buf)
      reader.read_byte
      expect(reader.read_remaining).to eq("\x02\x03\x04".b)
    end

    it 'returns empty string when already at end' do
      writer.write_byte(1)
      reader = BSV::Wallet::Wire::Reader.new(writer.buf)
      reader.read_byte
      expect(reader.read_remaining).to eq(''.b)
    end
  end

  describe 'Reader error handling' do
    it 'raises ArgumentError when reading past end of data' do
      reader = BSV::Wallet::Wire::Reader.new("\x01")
      reader.read_byte
      expect { reader.read_byte }.to raise_error(ArgumentError, /end of data/)
    end

    it 'raises ArgumentError when reading more bytes than available' do
      reader = BSV::Wallet::Wire::Reader.new("\x01\x02")
      expect { reader.read_bytes(10) }.to raise_error(ArgumentError, /need 10 bytes/)
    end
  end

  # --- optional_bool wire conformance (Go/BRC-103 encoding) ---
  #
  # Byte-level assertions pinning the canonical BRC-103 wire encoding for
  # optional bool. This catches any future regression at the wire layer rather
  # than in a higher-level conformance suite.

  describe 'optional_bool wire conformance' do
    it 'nil writes the byte 0xFF' do
      writer.write_optional_bool(nil)
      expect(writer.buf.getbyte(0)).to eq(0xFF)
    end

    it 'false writes the byte 0x00' do
      writer.write_optional_bool(false)
      expect(writer.buf.getbyte(0)).to eq(0x00)
    end

    it 'true writes the byte 0x01' do
      writer.write_optional_bool(true)
      expect(writer.buf.getbyte(0)).to eq(0x01)
    end

    it 'reads 0xFF as nil' do
      expect(BSV::Wallet::Wire::Reader.new("\xFF".b).read_optional_bool).to be_nil
    end

    it 'reads 0x00 as false' do
      expect(BSV::Wallet::Wire::Reader.new("\x00".b).read_optional_bool).to be(false)
    end

    it 'reads 0x01 as true' do
      expect(BSV::Wallet::Wire::Reader.new("\x01".b).read_optional_bool).to be(true)
    end

    it 'round-trips nil / false / true in sequence' do
      writer.write_optional_bool(nil)
      writer.write_optional_bool(false)
      writer.write_optional_bool(true)
      reader = BSV::Wallet::Wire::Reader.new(writer.buf)
      expect(reader.read_optional_bool).to be_nil
      expect(reader.read_optional_bool).to be(false)
      expect(reader.read_optional_bool).to be(true)
      expect(reader.remaining).to eq(0)
    end
  end
end
