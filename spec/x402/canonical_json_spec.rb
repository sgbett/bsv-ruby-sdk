# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'BSV::X402::CanonicalJSON' do
  subject(:encode) { BSV::X402::CanonicalJSON.method(:encode) }

  describe 'key ordering' do
    it 'sorts keys in ascending byte order' do
      result = BSV::X402::CanonicalJSON.encode('z' => 1, 'a' => 2)
      expect(result).to eq('{"a":2,"z":1}')
    end

    it 'sorts nested object keys independently' do
      result = BSV::X402::CanonicalJSON.encode('b' => { 'z' => 9, 'a' => 1 }, 'a' => 2)
      expect(result).to eq('{"a":2,"b":{"a":1,"z":9}}')
    end

    it 'sorts by byte value, not locale (uppercase before lowercase in ASCII)' do
      # 'Z' (90) < 'a' (97) in ASCII byte order
      result = BSV::X402::CanonicalJSON.encode('a' => 1, 'Z' => 2)
      expect(result).to eq('{"Z":2,"a":1}')
    end
  end

  describe 'integer encoding' do
    it 'emits integers without decimal points' do
      expect(BSV::X402::CanonicalJSON.encode('n' => 42)).to eq('{"n":42}')
    end

    it 'emits zero correctly' do
      expect(BSV::X402::CanonicalJSON.encode('n' => 0)).to eq('{"n":0}')
    end

    it 'emits negative integers correctly' do
      expect(BSV::X402::CanonicalJSON.encode('n' => -7)).to eq('{"n":-7}')
    end
  end

  describe 'boolean encoding' do
    it 'emits true as the JSON literal true' do
      expect(BSV::X402::CanonicalJSON.encode('b' => true)).to eq('{"b":true}')
    end

    it 'emits false as the JSON literal false' do
      expect(BSV::X402::CanonicalJSON.encode('b' => false)).to eq('{"b":false}')
    end
  end

  describe 'null encoding' do
    it 'emits nil as null' do
      expect(BSV::X402::CanonicalJSON.encode('x' => nil)).to eq('{"x":null}')
    end
  end

  describe 'string encoding' do
    it 'encodes plain ASCII strings' do
      expect(BSV::X402::CanonicalJSON.encode('s' => 'hello')).to eq('{"s":"hello"}')
    end

    it 'escapes double-quote characters' do
      expect(BSV::X402::CanonicalJSON.encode('s' => 'say "hi"')).to eq('{"s":"say \\"hi\\""}')
    end

    it 'escapes backslash characters' do
      expect(BSV::X402::CanonicalJSON.encode('s' => 'back\\slash')).to eq('{"s":"back\\\\slash"}')
    end

    it 'passes UTF-8 strings through unchanged' do
      # RFC 8785 does not escape printable Unicode — café passes through as-is.
      # "\u00E9" is é in Ruby double-quoted strings.
      expect(BSV::X402::CanonicalJSON.encode('s' => "caf\u00E9")).to eq("{\"s\":\"caf\u00E9\"}")
    end
  end

  describe 'no whitespace' do
    it 'emits no spaces or newlines' do
      result = BSV::X402::CanonicalJSON.encode('a' => 1, 'b' => 'two', 'c' => { 'd' => 3 })
      expect(result).not_to match(/\s/)
    end
  end

  describe 'symbol keys' do
    it 'treats symbol keys the same as string keys' do
      result = BSV::X402::CanonicalJSON.encode(z: 1, a: 2)
      expect(result).to eq('{"a":2,"z":1}')
    end
  end

  describe 'unsupported types' do
    it 'raises EncodingError for arrays' do
      expect { BSV::X402::CanonicalJSON.encode([1, 2, 3]) }
        .to raise_error(BSV::X402::EncodingError, /unsupported type/)
    end

    it 'raises EncodingError for floats' do
      expect { BSV::X402::CanonicalJSON.encode('f' => 1.5) }
        .to raise_error(BSV::X402::EncodingError, /unsupported type/)
    end
  end
end
