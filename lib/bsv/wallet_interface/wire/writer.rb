# frozen_string_literal: true

module BSV
  module Wallet
    module Wire
      # Builds a binary byte string using BRC-100 wire protocol encoding conventions.
      #
      # All multi-byte integers use little-endian order unless stated otherwise.
      # VarInts follow Bitcoin encoding; -1 is encoded as the 9-byte MaxUint64 sentinel.
      class Writer
        # Maximum byte length for a PrivilegedReason string (Int8 length field).
        MAX_PRIVILEGED_REASON = 127

        def initialize
          @buf = ''.b
        end

        # Returns the accumulated binary data.
        #
        # @return [String] binary string (encoding: ASCII-8BIT)
        def to_binary
          @buf
        end

        # Appends a single unsigned byte (0–255).
        #
        # @param val [Integer]
        def write_byte(val)
          @buf << [val & 0xFF].pack('C')
        end

        # Appends a signed 8-bit integer (-128–127).
        # Negative values are encoded as their two's-complement byte.
        #
        # @param val [Integer]
        def write_int8(val)
          @buf << [val].pack('c')
        end

        # Appends an unsigned Bitcoin VarInt.
        #
        # @param val [Integer] non-negative integer
        def write_varint(val)
          @buf << if val < 0xFD
                    [val].pack('C')
                  elsif val <= 0xFFFF
                    [0xFD, val].pack('Cv')
                  elsif val <= 0xFFFF_FFFF
                    [0xFE, val].pack('CV')
                  else
                    [0xFF, val].pack('CQ<')
                  end
        end

        # Appends a signed VarInt where -1 is encoded as MaxUint64 (9 bytes: FF * 9).
        #
        # @param val [Integer] non-negative integer, or -1 to signal absence
        def write_signed_varint(val)
          if val == -1
            @buf << "\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF".b
          else
            write_varint(val)
          end
        end

        # Appends raw bytes with no length prefix.
        #
        # @param data [String] binary string
        def write_bytes(data)
          @buf << data.b
        end

        # Appends a VarInt-prefixed byte array.
        #
        # @param data [String] binary string
        def write_byte_array(data)
          write_varint(data.bytesize)
          write_bytes(data)
        end

        # Appends a VarInt-prefixed byte array, or the -1 sentinel if nil.
        #
        # @param data_or_nil [String, nil]
        def write_optional_byte_array(data_or_nil)
          if data_or_nil.nil?
            write_signed_varint(-1)
          else
            write_byte_array(data_or_nil)
          end
        end

        # Appends a VarInt-prefixed UTF-8 string.
        #
        # @param str [String]
        def write_utf8_string(str)
          bytes = str.encode('UTF-8').b
          write_varint(bytes.bytesize)
          write_bytes(bytes)
        end

        # Appends a VarInt-prefixed UTF-8 string, or the -1 sentinel if nil.
        #
        # @param str_or_nil [String, nil]
        def write_optional_utf8_string(str_or_nil)
          if str_or_nil.nil?
            write_signed_varint(-1)
          else
            write_utf8_string(str_or_nil)
          end
        end

        # Appends an optional boolean as a signed Int8: 1=true, 0=false, -1=nil.
        #
        # @param val_or_nil [Boolean, nil]
        def write_optional_bool(val_or_nil)
          if val_or_nil.nil?
            write_int8(-1)
          elsif val_or_nil
            write_int8(1)
          else
            write_int8(0)
          end
        end

        # Appends an outpoint: 32 bytes (txid in display order) + VarInt index.
        #
        # @param txid_hex [String] 64-character hex txid
        # @param index [Integer] output index
        def write_outpoint(txid_hex, index)
          write_bytes([txid_hex].pack('H*'))
          write_varint(index)
        end

        # Appends a counterparty value using the first-byte dispatch scheme.
        #
        # Encoding:
        #   'self'   → 0x0B (11)
        #   'anyone' → 0x0C (12)
        #   nil      → 0x00 (0)
        #   hex pubkey (33 bytes compressed) → 33 raw bytes
        #
        # @param val [String, nil] 'self', 'anyone', nil, or 66-char hex pubkey
        def write_counterparty(val)
          case val
          when 'self'
            write_byte(11)
          when 'anyone'
            write_byte(12)
          when nil
            write_byte(0)
          else
            write_bytes([val].pack('H*'))
          end
        end

        # Appends a protocol ID: UInt8 security level + VarInt-prefixed UTF-8 name.
        #
        # @param protocol_id [Array] [Integer level, String name]
        def write_protocol_id(protocol_id)
          level, name = protocol_id
          write_byte(level)
          write_utf8_string(name)
        end

        # Appends an optional string array: VarInt count + strings, or -1 if nil.
        #
        # @param arr_or_nil [Array<String>, nil]
        def write_string_array(arr_or_nil)
          if arr_or_nil.nil?
            write_signed_varint(-1)
          else
            write_varint(arr_or_nil.length)
            arr_or_nil.each { |s| write_utf8_string(s) }
          end
        end

        # Appends an optional string→string map: VarInt count + key/value pairs, or -1 if nil.
        #
        # @param hash_or_nil [Hash, nil]
        def write_map(hash_or_nil)
          if hash_or_nil.nil?
            write_signed_varint(-1)
          else
            write_varint(hash_or_nil.length)
            hash_or_nil.each do |key, value|
              write_utf8_string(key.to_s)
              write_utf8_string(value.to_s)
            end
          end
        end

        # Appends privileged parameters: optional bool + Int8-length reason string.
        #
        # PrivilegedReason uses Int8 for its length field (max 127 bytes), not VarInt.
        # -1 (0xFF) means absent.
        #
        # @param privileged [Boolean, nil]
        # @param privileged_reason [String, nil]
        def write_privileged(privileged, privileged_reason)
          write_optional_bool(privileged)
          if privileged_reason.nil?
            write_int8(-1)
          else
            reason_bytes = privileged_reason.encode('UTF-8').b
            raise ArgumentError, 'privileged_reason exceeds 127 bytes' if reason_bytes.bytesize > MAX_PRIVILEGED_REASON

            write_int8(reason_bytes.bytesize)
            write_bytes(reason_bytes)
          end
        end
      end
    end
  end
end
