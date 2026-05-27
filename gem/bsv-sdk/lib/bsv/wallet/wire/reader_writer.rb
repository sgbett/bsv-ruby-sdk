# frozen_string_literal: true

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
      end
    end
  end
end
