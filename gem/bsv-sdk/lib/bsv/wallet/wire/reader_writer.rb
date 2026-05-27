# frozen_string_literal: true

require 'base64'

module BSV
  module Wallet
    module Wire
      # Binary read/write helpers with BRC-103 idioms.
      #
      # Thin wrappers over StringIO providing the specific encodings used across
      # BRC-103 wire frames: varint strings, optional bools, satoshi LE uint64,
      # and outpoints. Reuses BSV::Transaction::VarInt for the varint codec.

      # Writer accumulates bytes into a binary string buffer.
      class Writer
        attr_reader :buf

        def initialize
          @buf = String.new(encoding: 'BINARY')
        end

        # Write a raw byte.
        def write_byte(byte)
          @buf << [byte].pack('C')
        end

        # Write raw bytes (binary string).
        def write_bytes(bytes)
          @buf << bytes.b
        end

        # Write a Bitcoin varint.
        def write_varint(n)
          @buf << BSV::Transaction::VarInt.encode(n)
        end

        # Write a UTF-8 string prefixed by its byte length as a varint.
        def write_str_with_varint_len(str)
          bytes = str.to_s.b
          write_varint(bytes.bytesize)
          write_bytes(bytes)
        end

        # Write an optional boolean as a single byte.
        # nil → 0x00, false → 0x01, true → 0x02
        def write_optional_bool(value)
          byte = case value
                 when nil   then 0
                 when false then 1
                 else            2
                 end
          write_byte(byte)
        end

        # Write a satoshi amount as 8-byte little-endian uint64.
        def write_satoshis(n)
          @buf << [n].pack('Q<')
        end

        # Write an outpoint: 32-byte wire-order txid (reversed from display hex)
        # followed by 4-byte little-endian vout.
        #
        # @param txid_hex [String] 64-char display-order hex txid
        # @param vout [Integer] output index
        def write_outpoint(txid_hex, vout)
          BSV::Primitives::Hex.validate_dtxid_hex!(txid_hex)
          wtxid = [txid_hex].pack('H*').reverse
          @buf << wtxid
          @buf << [vout].pack('V')
        end

        # Write the NegativeOne sentinel (MaxUint64 as a 9-byte varint: 9 × 0xFF).
        # Used as a nil sentinel for optional fields in Go-compatible encoding.
        def write_negative_one
          write_varint(0xFFFF_FFFF_FFFF_FFFF)
        end

        # Write a varint length-prefixed byte array (WriteIntBytes in Go).
        # @param bytes [String, nil] binary string; nil or empty → write varint 0
        def write_int_bytes(bytes)
          raw = bytes ? bytes.b : ''.b
          write_varint(raw.bytesize)
          write_bytes(raw)
        end

        # Write an optional uint32: nil → NegativeOne; else varint.
        # @param n [Integer, nil]
        def write_optional_uint32(n)
          if n.nil?
            write_negative_one
          else
            write_varint(n)
          end
        end

        # Write an optional string: nil or empty → NegativeOne; else varint len + bytes.
        # Matches Go WriteOptionalString.
        # @param str [String, nil]
        def write_optional_string(str)
          if str.nil? || str.empty?
            write_negative_one
          else
            write_str_with_varint_len(str)
          end
        end

        # Write an array of strings: nil → NegativeOne; else varint count + each as optional string.
        # Matches Go WriteStringSlice.
        # @param arr [Array<String>, nil]
        def write_string_slice(arr)
          if arr.nil?
            write_negative_one
          else
            write_varint(arr.length)
            arr.each { |s| write_optional_string(s) }
          end
        end

        # Write a string map (Hash<String,String>) sorted by key.
        # Matches Go WriteStringMap.
        # @param map [Hash, nil]
        def write_string_map(map)
          m = map || {}
          write_varint(m.length)
          m.keys.sort.each do |k|
            write_str_with_varint_len(k)
            write_str_with_varint_len(m[k])
          end
        end

        # Write a binary value encoded as a Base64 string on the wire.
        # Decodes the Base64 string and writes the raw bytes prefixed by varint length.
        # @param base64_str [String] standard Base64-encoded string
        def write_int_from_base64(base64_str)
          raw = Base64.strict_decode64(base64_str)
          write_int_bytes(raw)
        end

        # Write the privileged flag and reason (Go encodePrivilegedParams).
        # privileged: nil → NegativeOneByte (0xFF), false → 0x00, true → 0x01.
        # reason: nil or empty → NegativeOneByte; else varint len + bytes.
        def write_privileged_params(privileged, reason)
          # Go OptionalBool: nil=0xFF, false=0x00, true=0x01
          byte = case privileged
                 when nil   then 0xFF
                 when false then 0x00
                 else            0x01
                 end
          write_byte(byte)
          if reason.nil? || reason.empty?
            write_byte(0xFF)
          else
            write_str_with_varint_len(reason)
          end
        end

        # Write Go-compatible optional bool (for struct option fields).
        # nil → 0xFF (NegativeOneByte), false → 0x00, true → 0x01.
        # @param value [Boolean, nil]
        def write_go_optional_bool(value)
          byte = case value
                 when nil   then 0xFF
                 when false then 0x00
                 else            0x01
                 end
          write_byte(byte)
        end

        # Write a txid slice (array of 32-byte wire-order txids).
        # nil → NegativeOne; else varint count + 32 raw bytes per txid.
        # Txids are passed as 64-char display-order hex; reversed to wire order here.
        # @param txids [Array<String>, nil] 64-char display-order hex strings
        def write_txid_slice(txids)
          if txids.nil?
            write_negative_one
          else
            write_varint(txids.length)
            txids.each { |hex| write_bytes([hex].pack('H*').reverse) }
          end
        end

        # Write optional bytes with a 1-byte flag prefix (Go BytesOptionWithFlag).
        # nil/empty → 0x00; else → 0x01 + varint_len + bytes (or fixed_size bytes).
        # @param bytes [String, nil] binary data
        # @param fixed_size [Integer, nil] if set, omit the varint length prefix
        def write_optional_bytes_with_flag(bytes, fixed_size: nil)
          raw = bytes ? bytes.b : ''.b
          if raw.empty?
            write_byte(0)
          else
            write_byte(1)
            if fixed_size
              write_bytes(raw)
            else
              write_int_bytes(raw)
            end
          end
        end

        # Write a varint-len string (always present, 0-length for nil/empty).
        # Matches Go WriteString which always writes the length prefix.
        # @param str [String, nil]
        def write_string(str)
          write_str_with_varint_len(str.to_s)
        end
      end

      # Reader reads sequentially from a binary string.
      class Reader
        # @param data [String] binary data
        def initialize(data)
          @data = data.b
          @pos = 0
        end

        # Read a single byte.
        # @return [Integer]
        def read_byte
          raise ArgumentError, 'unexpected end of data reading byte' if @pos >= @data.bytesize

          byte = @data.getbyte(@pos)
          @pos += 1
          byte
        end

        # Read +n+ raw bytes.
        # @return [String] binary string
        def read_bytes(n)
          raise ArgumentError, "need #{n} bytes at offset #{@pos}, got #{remaining}" if remaining < n

          slice = @data.byteslice(@pos, n)
          @pos += n
          slice
        end

        # Read a Bitcoin varint.
        # @return [Integer]
        def read_varint
          value, consumed = BSV::Transaction::VarInt.decode(@data, @pos)
          @pos += consumed
          value
        end

        # Read a varint-prefixed UTF-8 string.
        # @return [String]
        def read_str_with_varint_len
          len = read_varint
          read_bytes(len).force_encoding('UTF-8')
        end

        # Read an optional boolean byte.
        # 0x00 → nil, 0x01 → false, 0x02 → true
        # @return [Boolean, nil]
        def read_optional_bool
          byte = read_byte
          case byte
          when 0 then nil
          when 1 then false
          else        true
          end
        end

        # Read 8-byte little-endian uint64 satoshi amount.
        # @return [Integer]
        def read_satoshis
          read_bytes(8).unpack1('Q<')
        end

        # Read a 36-byte outpoint (32-byte wire-order txid + 4-byte LE vout).
        # @return [Hash] { txid_hex: String, vout: Integer }
        def read_outpoint
          wtxid = read_bytes(32)
          vout = read_bytes(4).unpack1('V')
          txid_hex = wtxid.reverse.unpack1('H*')
          { txid_hex: txid_hex, vout: vout }
        end

        # Remaining bytes.
        def remaining
          @data.bytesize - @pos
        end

        # Read all remaining bytes.
        # @return [String] binary string
        def read_remaining
          slice = @data.byteslice(@pos, @data.bytesize - @pos) || ''.b
          @pos = @data.bytesize
          slice
        end

        # Whether the next varint is the NegativeOne sentinel (0xFFFF…).
        # Peeks at the next byte without consuming it.
        def next_negative_one?
          @pos < @data.bytesize && @data.getbyte(@pos) == 0xFF
        end

        # Read a varint-length-prefixed byte array (ReadIntBytes in Go).
        # @return [String] binary string
        def read_int_bytes
          len = read_varint
          return ''.b if len == 0xFFFF_FFFF_FFFF_FFFF || len.zero?

          read_bytes(len)
        end

        # Read an optional uint32: NegativeOne sentinel → nil; else varint → Integer.
        # @return [Integer, nil]
        def read_optional_uint32
          val = read_varint
          val == 0xFFFF_FFFF_FFFF_FFFF ? nil : val
        end

        # Read an optional string: NegativeOne sentinel → nil; else varint len + bytes.
        # @return [String, nil]
        def read_optional_string
          val = read_varint
          return nil if val == 0xFFFF_FFFF_FFFF_FFFF

          read_bytes(val).force_encoding('UTF-8')
        end

        # Read an array of strings encoded as varint count + each optional string.
        # NegativeOne sentinel count → nil.
        # @return [Array<String>, nil]
        def read_string_slice
          count = read_varint
          return nil if count == 0xFFFF_FFFF_FFFF_FFFF

          count.times.map { read_optional_string || '' }
        end

        # Read a string map: varint count + key/value pairs (each varint-len-prefixed).
        # @return [Hash<String,String>]
        def read_string_map
          count = read_varint
          count.times.each_with_object({}) do |_, h|
            k = read_str_with_varint_len
            v = read_str_with_varint_len
            h[k] = v
          end
        end

        # Read a binary value and return it Base64-encoded.
        # @return [String] Base64-encoded string
        def read_base64_int
          raw = read_int_bytes
          Base64.strict_encode64(raw)
        end

        # Read an optional bool using Go wire encoding:
        # 0xFF → nil, 0x00 → false, 0x01 → true.
        # @return [Boolean, nil]
        def read_go_optional_bool
          byte = read_byte
          return nil if byte == 0xFF

          byte == 0x01
        end

        # Read privileged params (Go decodePrivilegedParams).
        # @return [Array(Boolean|nil, String|nil)]
        def read_privileged_params
          privileged = read_go_optional_bool
          first_byte = read_byte
          if first_byte == 0xFF
            [privileged, nil]
          else
            # Back up one byte and read as varint-prefixed string
            @pos -= 1
            reason = read_str_with_varint_len
            [privileged, reason]
          end
        end

        # Read a txid slice: NegativeOne → nil; else varint count + 32-byte wire-order txids.
        # Returns display-order hex strings.
        # @return [Array<String>, nil]
        def read_txid_slice
          count = read_varint
          return nil if count == 0xFFFF_FFFF_FFFF_FFFF

          count.times.map { read_bytes(32).reverse.unpack1('H*') }
        end

        # Read optional bytes with a 1-byte flag prefix (Go BytesOptionWithFlag).
        # 0x00 → nil; 0x01 → read varint_len + bytes (or fixed_size bytes).
        # @param fixed_size [Integer, nil] if set, read exactly this many bytes (no varint)
        # @return [String, nil] binary string or nil
        def read_optional_bytes_with_flag(fixed_size: nil)
          flag = read_byte
          return nil if flag.zero?

          if fixed_size
            read_bytes(fixed_size)
          else
            read_int_bytes
          end
        end

        # Read a varint-len string (always present, 0-length = empty string).
        # Matches Go ReadString which returns "" for length 0 or NegativeOne.
        # @return [String]
        def read_string
          len = read_varint
          return '' if len.zero? || len == 0xFFFF_FFFF_FFFF_FFFF

          read_bytes(len).force_encoding('UTF-8')
        end
      end
    end
  end
end
