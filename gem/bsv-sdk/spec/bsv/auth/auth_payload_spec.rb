# frozen_string_literal: true

require 'spec_helper'

# Top-level constants to avoid Lint/ConstantDefinitionInBlock
REQUEST_NONCE_BYTES = ("\x01" * 32).b
REQUEST_ID_BYTES    = ("\x02" * 32).b

RSpec.describe 'BSV::Auth::AuthPayload' do
  subject(:mod) { BSV::Auth::AuthPayload }

  let(:absent) { BSV::Auth::AuthPayload::ABSENT }

  describe 'ABSENT constant' do
    it 'equals VarInt MAX_UINT64' do
      expect(absent).to eq(BSV::Transaction::VarInt::MAX_UINT64)
    end

    it 'encodes to 9 bytes of 0xFF' do
      encoded = BSV::Transaction::VarInt.encode(absent)
      expect(encoded.bytesize).to eq(9)
      expect(encoded.bytes).to all(eq(0xFF))
    end
  end

  describe '.serialize_request / .deserialize_request round-trip' do
    it 'round-trips a simple GET request' do
      nonce = ("\xAB" * 32).b
      result = mod.deserialize_request(
        mod.serialize_request(
          request_nonce: nonce,
          method: 'GET',
          path: '/hello',
          query: nil,
          headers: [['content-type', 'application/json']],
          body: nil
        )
      )
      expect(result[:request_nonce]).to eq(nonce)
      expect(result[:method]).to eq('GET')
      expect(result[:path]).to eq('/hello')
      expect(result[:query]).to be_nil
      expect(result[:headers]).to eq([['content-type', 'application/json']])
      expect(result[:body]).to be_nil
    end

    it 'round-trips a POST request with body' do
      nonce = ("\xCD" * 32).b
      body = '{"name":"Alice"}'
      result = mod.deserialize_request(
        mod.serialize_request(
          request_nonce: nonce,
          method: 'POST',
          path: '/users',
          query: nil,
          headers: [['content-type', 'application/json']],
          body: body
        )
      )
      expect(result[:method]).to eq('POST')
      expect(result[:body]).to eq(body.b)
    end

    it 'round-trips query string' do
      nonce = ("\x00" * 32).b
      result = mod.deserialize_request(
        mod.serialize_request(
          request_nonce: nonce,
          method: 'GET',
          path: '/search',
          query: '?q=hello&page=1',
          headers: [],
          body: nil
        )
      )
      expect(result[:query]).to eq('?q=hello&page=1')
    end

    it 'round-trips multiple headers in sorted order' do
      nonce = ("\x00" * 32).b
      headers = [['authorization', 'Bearer tok'], ['x-bsv-custom', 'val']]
      result = mod.deserialize_request(
        mod.serialize_request(
          request_nonce: nonce,
          method: 'GET',
          path: '/',
          query: nil,
          headers: headers,
          body: nil
        )
      )
      expect(result[:headers]).to eq(headers)
    end

    it 'round-trips unicode in path and headers' do
      nonce = ("\x00" * 32).b
      unicode_path = "/caf\u00E9"
      unicode_val  = "\u4E2D\u6587"
      result = mod.deserialize_request(
        mod.serialize_request(
          request_nonce: nonce,
          method: 'GET',
          path: unicode_path,
          query: nil,
          headers: [['x-bsv-lang', unicode_val]],
          body: nil
        )
      )
      expect(result[:path]).to eq(unicode_path)
      expect(result[:headers].first[1]).to eq(unicode_val)
    end
  end

  describe '.serialize_request — static test vector' do
    # Expected hex from task spec:
    #   0101...01 (32 x 0x01)  — request_nonce
    #   03 474554               — varint(3) + "GET"
    #   09 2f6170692f74657374  — varint(9) + "/api/test"
    #   ff ffffffffffffffff    — ABSENT (query)
    #   01                     — varint(1) header count
    #   0c 636f6e74656e742d74797065  — varint(12) + "content-type"
    #   10 6170706c69636174696f6e2f6a736f6e  — varint(16) + "application/json"
    #   ff ffffffffffffffff    — ABSENT (body — GET has no default)
    it 'produces the expected byte sequence' do
      payload = mod.serialize_request(
        request_nonce: REQUEST_NONCE_BYTES,
        method: 'GET',
        path: '/api/test',
        query: nil,
        headers: [['content-type', 'application/json']],
        body: nil
      )
      hex = payload.unpack1('H*')

      nonce_hex        = '01' * 32
      method_hex       = '03474554'
      path_hex         = '092f6170692f74657374'
      absent_hex       = "ff#{'ff' * 8}"
      header_count_hex = '01'
      key_hex          = '0c636f6e74656e742d74797065'
      val_hex          = '106170706c69636174696f6e2f6a736f6e'

      expected = [nonce_hex, method_hex, path_hex, absent_hex,
                  header_count_hex, key_hex, val_hex, absent_hex].join

      expect(hex).to eq(expected)
    end
  end

  describe '.serialize_response / .deserialize_response round-trip' do
    it 'round-trips a simple 200 response' do
      result = mod.deserialize_response(
        mod.serialize_response(
          request_id: REQUEST_ID_BYTES,
          status: 200,
          headers: [],
          body: '{"ok":true}'
        )
      )
      expect(result[:request_id]).to eq(REQUEST_ID_BYTES)
      expect(result[:status]).to eq(200)
      expect(result[:headers]).to eq([])
      expect(result[:body]).to eq('{"ok":true}'.b)
    end

    it 'round-trips a 404 response with headers' do
      headers = [['authorization', 'Bearer token'], ['x-bsv-foo', 'bar']]
      result = mod.deserialize_response(
        mod.serialize_response(
          request_id: REQUEST_ID_BYTES,
          status: 404,
          headers: headers,
          body: 'not found'
        )
      )
      expect(result[:status]).to eq(404)
      expect(result[:headers]).to eq(headers)
    end

    it 'encodes nil body as ABSENT' do
      payload = mod.serialize_response(
        request_id: REQUEST_ID_BYTES,
        status: 204,
        headers: [],
        body: nil
      )
      result = mod.deserialize_response(payload)
      expect(result[:body]).to be_nil
    end
  end

  describe '.serialize_response — static test vector' do
    # Format:
    #   0202...02 (32 x 0x02)  — request_id
    #   c8                      — varint(200) — 200 < 0xFD so single byte 0xC8
    #   00                      — varint(0) headers
    #   0b 7b226f6b223a747275657d  — varint(11) + body
    #
    # Note: the task spec shows 'fdc800' for status 200 but that is the 3-byte VarInt
    # form; 200 < 253 (0xFD) so it encodes as a single byte 0xC8.
    it 'produces the expected byte sequence' do
      payload = mod.serialize_response(
        request_id: REQUEST_ID_BYTES,
        status: 200,
        headers: [],
        body: '{"ok":true}'
      )
      hex = payload.unpack1('H*')

      request_id_hex    = '02' * 32
      status_hex        = 'c8' # VarInt(200) = single byte 0xC8
      header_count_hex  = '00'
      body_hex          = '0b7b226f6b223a747275657d'

      expected = [request_id_hex, status_hex, header_count_hex, body_hex].join

      expect(hex).to eq(expected)
    end
  end

  describe 'body defaulting for body-carrying methods' do
    let(:nonce) { ("\x00" * 32).b }

    it 'defaults nil body to "{}" for POST with application/json content-type' do
      payload = mod.serialize_request(
        request_nonce: nonce,
        method: 'POST',
        path: '/api',
        query: nil,
        headers: [['content-type', 'application/json']],
        body: nil
      )
      result = mod.deserialize_request(payload)
      expect(result[:body]).to eq('{}'.b)
    end

    it 'defaults nil body to ABSENT for POST without JSON content-type' do
      payload = mod.serialize_request(
        request_nonce: nonce,
        method: 'POST',
        path: '/api',
        query: nil,
        headers: [['content-type', 'application/octet-stream']],
        body: nil
      )
      result = mod.deserialize_request(payload)
      # empty string defaults to ABSENT via encode_optional_bytes
      expect(result[:body]).to be_nil
    end

    it 'does not default nil body for GET' do
      payload = mod.serialize_request(
        request_nonce: nonce,
        method: 'GET',
        path: '/',
        query: nil,
        headers: [],
        body: nil
      )
      result = mod.deserialize_request(payload)
      expect(result[:body]).to be_nil
    end

    it 'preserves explicit body over default for POST' do
      payload = mod.serialize_request(
        request_nonce: nonce,
        method: 'POST',
        path: '/api',
        query: nil,
        headers: [['content-type', 'application/json']],
        body: '{"key":"value"}'
      )
      result = mod.deserialize_request(payload)
      expect(result[:body]).to eq('{"key":"value"}'.b)
    end

    it 'applies defaulting for PUT, PATCH, DELETE' do
      %w[PUT PATCH DELETE].each do |method|
        payload = mod.serialize_request(
          request_nonce: nonce,
          method: method,
          path: '/api',
          query: nil,
          headers: [['content-type', 'application/json']],
          body: nil
        )
        result = mod.deserialize_request(payload)
        expect(result[:body]).to eq('{}'.b), "expected '{}' for #{method}"
      end
    end
  end

  describe 'absent field encoding' do
    let(:nonce) { ("\x00" * 32).b }

    it 'encodes nil path as ABSENT (9 bytes of 0xFF)' do
      payload = mod.serialize_request(
        request_nonce: nonce,
        method: 'GET',
        path: nil,
        query: nil,
        headers: [],
        body: nil
      )
      # After 32 nonce + 1+3 method = 36 bytes, next 9 bytes should be ABSENT
      absent_bytes = payload.b.byteslice(36, 9).bytes
      expect(absent_bytes).to all(eq(0xFF))
    end

    it 'encodes empty path as varint(0) + zero bytes, distinct from absent' do
      payload_nil   = mod.serialize_request(request_nonce: nonce, method: 'GET',
                                            path: nil, query: nil, headers: [], body: nil)
      payload_empty = mod.serialize_request(request_nonce: nonce, method: 'GET',
                                            path: '', query: nil, headers: [], body: nil)
      # nil path → 9 bytes; empty path → 1 byte (varint 0)
      # The two payloads should differ
      expect(payload_nil).not_to eq(payload_empty)
    end
  end

  describe 'method defaulting' do
    let(:nonce) { ("\x00" * 32).b }

    it 'defaults nil method to GET' do
      payload = mod.serialize_request(
        request_nonce: nonce,
        method: nil,
        path: '/',
        query: nil,
        headers: [],
        body: nil
      )
      result = mod.deserialize_request(payload)
      expect(result[:method]).to eq('GET')
    end

    it 'defaults empty string method to GET' do
      payload = mod.serialize_request(
        request_nonce: nonce,
        method: '',
        path: '/',
        query: nil,
        headers: [],
        body: nil
      )
      result = mod.deserialize_request(payload)
      expect(result[:method]).to eq('GET')
    end
  end
end
