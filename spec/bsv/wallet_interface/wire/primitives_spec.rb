# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

# Helper: write a value with Writer, read it back with Reader and return the result.
def wire_roundtrip(write_method, read_method, *args)
  w = BSV::Wallet::Wire::Writer.new
  w.public_send(write_method, *args)
  r = BSV::Wallet::Wire::Reader.new(w.to_binary)
  r.public_send(read_method)
end

RSpec.describe 'BRC-100 wire protocol primitives' do
  describe 'write_byte / read_byte' do
    it 'round-trips 0' do
      expect(wire_roundtrip(:write_byte, :read_byte, 0)).to eq(0)
    end

    it 'round-trips 255' do
      expect(wire_roundtrip(:write_byte, :read_byte, 255)).to eq(255)
    end

    it 'round-trips 127' do
      expect(wire_roundtrip(:write_byte, :read_byte, 127)).to eq(127)
    end

    it 'encodes a single byte (1 byte total)' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_byte(42)
      expect(w.to_binary.bytesize).to eq(1)
    end
  end

  describe 'write_int8 / read_int8' do
    it 'round-trips 0' do
      expect(wire_roundtrip(:write_int8, :read_int8, 0)).to eq(0)
    end

    it 'round-trips 127 (max positive)' do
      expect(wire_roundtrip(:write_int8, :read_int8, 127)).to eq(127)
    end

    it 'round-trips -128 (min negative)' do
      expect(wire_roundtrip(:write_int8, :read_int8, -128)).to eq(-128)
    end

    it 'round-trips -1' do
      expect(wire_roundtrip(:write_int8, :read_int8, -1)).to eq(-1)
    end

    it 'encodes a single byte (1 byte total)' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_int8(-1)
      expect(w.to_binary.bytesize).to eq(1)
    end
  end

  describe 'write_varint / read_varint' do
    it 'round-trips 0' do
      expect(wire_roundtrip(:write_varint, :read_varint, 0)).to eq(0)
    end

    it 'round-trips 252 (largest 1-byte varint)' do
      expect(wire_roundtrip(:write_varint, :read_varint, 252)).to eq(252)
    end

    it 'round-trips 253 using 3-byte encoding' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_varint(253)
      expect(w.to_binary.bytesize).to eq(3)
      r = BSV::Wallet::Wire::Reader.new(w.to_binary)
      expect(r.read_varint).to eq(253)
    end

    it 'round-trips 0xFFFF using 3-byte encoding' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_varint(0xFFFF)
      expect(w.to_binary.bytesize).to eq(3)
      r = BSV::Wallet::Wire::Reader.new(w.to_binary)
      expect(r.read_varint).to eq(0xFFFF)
    end

    it 'round-trips 0x10000 using 5-byte encoding' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_varint(0x10000)
      expect(w.to_binary.bytesize).to eq(5)
      r = BSV::Wallet::Wire::Reader.new(w.to_binary)
      expect(r.read_varint).to eq(0x10000)
    end

    it 'round-trips 0xFFFF_FFFF using 5-byte encoding' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_varint(0xFFFF_FFFF)
      expect(w.to_binary.bytesize).to eq(5)
      r = BSV::Wallet::Wire::Reader.new(w.to_binary)
      expect(r.read_varint).to eq(0xFFFF_FFFF)
    end

    it 'round-trips a large 9-byte value' do
      val = 0x1_0000_0000
      w = BSV::Wallet::Wire::Writer.new
      w.write_varint(val)
      expect(w.to_binary.bytesize).to eq(9)
      r = BSV::Wallet::Wire::Reader.new(w.to_binary)
      expect(r.read_varint).to eq(val)
    end
  end

  describe 'write_signed_varint / read_signed_varint' do
    it 'round-trips 0' do
      expect(wire_roundtrip(:write_signed_varint, :read_signed_varint, 0)).to eq(0)
    end

    it 'round-trips positive values identically to varint' do
      expect(wire_roundtrip(:write_signed_varint, :read_signed_varint, 1000)).to eq(1000)
    end

    it 'round-trips -1 as the 9-byte MaxUint64 sentinel' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_signed_varint(-1)
      expect(w.to_binary.bytesize).to eq(9)
      expect(w.to_binary).to eq("\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF".b)
      r = BSV::Wallet::Wire::Reader.new(w.to_binary)
      expect(r.read_signed_varint).to eq(-1)
    end
  end

  describe 'write_byte_array / read_byte_array' do
    it 'round-trips an empty byte array' do
      result = wire_roundtrip(:write_byte_array, :read_byte_array, ''.b)
      expect(result).to eq(''.b)
    end

    it 'round-trips binary data' do
      data = "\x00\x01\xFE\xFF".b
      result = wire_roundtrip(:write_byte_array, :read_byte_array, data)
      expect(result).to eq(data)
    end

    it 'round-trips 32 bytes (typical hash length)' do
      data = ('ab' * 16).b
      result = wire_roundtrip(:write_byte_array, :read_byte_array, data)
      expect(result).to eq(data)
    end

    it 'prefixes with a varint length' do
      data = 'hello'.b
      w = BSV::Wallet::Wire::Writer.new
      w.write_byte_array(data)
      expect(w.to_binary.bytesize).to eq(1 + data.bytesize)
    end
  end

  describe 'write_optional_byte_array / read_optional_byte_array' do
    it 'round-trips nil as the -1 sentinel' do
      result = wire_roundtrip(:write_optional_byte_array, :read_optional_byte_array, nil)
      expect(result).to be_nil
    end

    it 'round-trips an empty byte array as distinct from nil' do
      result = wire_roundtrip(:write_optional_byte_array, :read_optional_byte_array, ''.b)
      expect(result).to eq(''.b)
    end

    it 'round-trips binary data' do
      data = "\xDE\xAD\xBE\xEF".b
      result = wire_roundtrip(:write_optional_byte_array, :read_optional_byte_array, data)
      expect(result).to eq(data)
    end
  end

  describe 'write_utf8_string / read_utf8_string' do
    it 'round-trips an empty string' do
      result = wire_roundtrip(:write_utf8_string, :read_utf8_string, '')
      expect(result).to eq('')
    end

    it 'round-trips an ASCII string' do
      result = wire_roundtrip(:write_utf8_string, :read_utf8_string, 'hello world')
      expect(result).to eq('hello world')
    end

    it 'round-trips a UTF-8 string with multibyte characters' do
      str = "caf\u00E9"
      result = wire_roundtrip(:write_utf8_string, :read_utf8_string, str)
      expect(result).to eq(str)
    end

    it 'returns a UTF-8 encoded string' do
      result = wire_roundtrip(:write_utf8_string, :read_utf8_string, 'test')
      expect(result.encoding).to eq(Encoding::UTF_8)
    end
  end

  describe 'write_optional_utf8_string / read_optional_utf8_string' do
    it 'round-trips nil as the -1 sentinel' do
      result = wire_roundtrip(:write_optional_utf8_string, :read_optional_utf8_string, nil)
      expect(result).to be_nil
    end

    it 'round-trips an empty string as distinct from nil' do
      result = wire_roundtrip(:write_optional_utf8_string, :read_optional_utf8_string, '')
      expect(result).to eq('')
    end

    it 'round-trips a present string' do
      result = wire_roundtrip(:write_optional_utf8_string, :read_optional_utf8_string, 'basket-name')
      expect(result).to eq('basket-name')
    end
  end

  describe 'write_optional_bool / read_optional_bool' do
    it 'round-trips true as Int8 value 1' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_optional_bool(true)
      expect(w.to_binary).to eq("\x01".b)
      r = BSV::Wallet::Wire::Reader.new(w.to_binary)
      expect(r.read_optional_bool).to be(true)
    end

    it 'round-trips false as Int8 value 0' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_optional_bool(false)
      expect(w.to_binary).to eq("\x00".b)
      r = BSV::Wallet::Wire::Reader.new(w.to_binary)
      expect(r.read_optional_bool).to be(false)
    end

    it 'round-trips nil as Int8 value -1' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_optional_bool(nil)
      expect(w.to_binary).to eq("\xFF".b)
      r = BSV::Wallet::Wire::Reader.new(w.to_binary)
      expect(r.read_optional_bool).to be_nil
    end
  end

  describe 'write_outpoint / read_outpoint' do
    let(:txid_hex) { 'ab' * 32 }

    it 'round-trips a txid and index' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_outpoint(txid_hex, 3)
      r = BSV::Wallet::Wire::Reader.new(w.to_binary)
      txid_out, index_out = r.read_outpoint
      expect(txid_out).to eq(txid_hex)
      expect(index_out).to eq(3)
    end

    it 'round-trips index 0' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_outpoint(txid_hex, 0)
      r = BSV::Wallet::Wire::Reader.new(w.to_binary)
      _txid, index_out = r.read_outpoint
      expect(index_out).to eq(0)
    end

    it 'encodes 32 bytes txid + 1 byte index (33 bytes total for small index)' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_outpoint(txid_hex, 0)
      expect(w.to_binary.bytesize).to eq(33)
    end

    it 'preserves txid display order (not reversed)' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_outpoint(txid_hex, 0)
      # First 32 bytes should be the raw txid hex decoded
      expect(w.to_binary.byteslice(0, 32).unpack1('H*')).to eq(txid_hex)
    end
  end

  describe 'write_counterparty / read_counterparty' do
    it 'round-trips "self" as byte 11' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_counterparty('self')
      expect(w.to_binary).to eq("\x0B".b)
      r = BSV::Wallet::Wire::Reader.new(w.to_binary)
      expect(r.read_counterparty).to eq('self')
    end

    it 'round-trips "anyone" as byte 12' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_counterparty('anyone')
      expect(w.to_binary).to eq("\x0C".b)
      r = BSV::Wallet::Wire::Reader.new(w.to_binary)
      expect(r.read_counterparty).to eq('anyone')
    end

    it 'round-trips nil as byte 0' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_counterparty(nil)
      expect(w.to_binary).to eq("\x00".b)
      r = BSV::Wallet::Wire::Reader.new(w.to_binary)
      expect(r.read_counterparty).to be_nil
    end

    it 'round-trips a compressed hex pubkey (33 bytes)' do
      pubkey_hex = BSV::Primitives::PrivateKey.generate.public_key.to_hex
      w = BSV::Wallet::Wire::Writer.new
      w.write_counterparty(pubkey_hex)
      expect(w.to_binary.bytesize).to eq(33)
      r = BSV::Wallet::Wire::Reader.new(w.to_binary)
      expect(r.read_counterparty).to eq(pubkey_hex)
    end
  end

  describe 'write_protocol_id / read_protocol_id' do
    it 'round-trips [0, "hello world"]' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_protocol_id([0, 'hello world'])
      r = BSV::Wallet::Wire::Reader.new(w.to_binary)
      level, name = r.read_protocol_id
      expect(level).to eq(0)
      expect(name).to eq('hello world')
    end

    it 'round-trips [2, "hello world"] (security level 2)' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_protocol_id([2, 'hello world'])
      r = BSV::Wallet::Wire::Reader.new(w.to_binary)
      level, name = r.read_protocol_id
      expect(level).to eq(2)
      expect(name).to eq('hello world')
    end

    it 'encodes: 1 byte level + varint name length + name bytes' do
      w = BSV::Wallet::Wire::Writer.new
      w.write_protocol_id([1, 'ab'])
      # 1 (level) + 1 (varint len=2) + 2 (bytes)
      expect(w.to_binary.bytesize).to eq(4)
    end
  end

  describe 'write_string_array / read_string_array' do
    it 'round-trips nil as the -1 sentinel' do
      result = wire_roundtrip(:write_string_array, :read_string_array, nil)
      expect(result).to be_nil
    end

    it 'round-trips an empty array as distinct from nil' do
      result = wire_roundtrip(:write_string_array, :read_string_array, [])
      expect(result).to eq([])
    end

    it 'round-trips a populated array' do
      arr = %w[alpha beta gamma]
      result = wire_roundtrip(:write_string_array, :read_string_array, arr)
      expect(result).to eq(arr)
    end

    it 'round-trips an array with a single element' do
      result = wire_roundtrip(:write_string_array, :read_string_array, ['only'])
      expect(result).to eq(['only'])
    end
  end

  describe 'write_map / read_map' do
    it 'round-trips nil as the -1 sentinel' do
      result = wire_roundtrip(:write_map, :read_map, nil)
      expect(result).to be_nil
    end

    it 'round-trips an empty hash as distinct from nil' do
      result = wire_roundtrip(:write_map, :read_map, {})
      expect(result).to eq({})
    end

    it 'round-trips a populated hash' do
      map = { 'key1' => 'value1', 'key2' => 'value2' }
      result = wire_roundtrip(:write_map, :read_map, map)
      expect(result).to eq(map)
    end

    it 'coerces symbol keys to strings on write' do
      map = { foo: 'bar' }
      result = wire_roundtrip(:write_map, :read_map, map)
      expect(result).to eq({ 'foo' => 'bar' })
    end
  end
end
