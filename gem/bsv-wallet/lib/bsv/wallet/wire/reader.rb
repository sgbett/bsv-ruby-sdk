# frozen_string_literal: true

module BSV
  module Wallet
    module Wire
      # Consumes a binary byte string using BRC-100 wire protocol decoding conventions.
      #
      # All multi-byte integers use little-endian order unless stated otherwise.
      # VarInts follow Bitcoin encoding; the 9-byte MaxUint64 sentinel decodes as -1.
      class Reader
        # The 64-bit sentinel value that encodes -1 in a signed VarInt.
        MAX_UINT64 = 0xFFFF_FFFF_FFFF_FFFF

        def initialize(data)
          @data = data.b
          @offset = 0
        end

        # Current read position (bytes consumed so far).
        attr_reader :offset

        # Reads a single unsigned byte (0–255).
        #
        # @return [Integer]
        def read_byte
          require_bytes(1)
          byte = @data.getbyte(@offset)
          @offset += 1
          byte
        end

        # Reads a signed 8-bit integer (-128–127).
        #
        # @return [Integer]
        def read_int8
          require_bytes(1)
          val = @data.byteslice(@offset, 1).unpack1('c')
          @offset += 1
          val
        end

        # Reads an unsigned Bitcoin VarInt.
        #
        # @return [Integer]
        def read_varint
          require_bytes(1)
          first = @data.getbyte(@offset)

          case first
          when 0..0xFC
            @offset += 1
            first
          when 0xFD
            require_bytes(3)
            val = @data.byteslice(@offset + 1, 2).unpack1('v')
            @offset += 3
            val
          when 0xFE
            require_bytes(5)
            val = @data.byteslice(@offset + 1, 4).unpack1('V')
            @offset += 5
            val
          else # 0xFF
            require_bytes(9)
            val = @data.byteslice(@offset + 1, 8).unpack1('Q<')
            @offset += 9
            val
          end
        end

        # Reads a signed VarInt, returning -1 for the MaxUint64 sentinel.
        #
        # @return [Integer] non-negative value or -1
        def read_signed_varint
          val = read_varint
          val == MAX_UINT64 ? -1 : val
        end

        # Reads exactly n raw bytes.
        #
        # @param n [Integer]
        # @return [String] binary string
        def read_bytes(n)
          require_bytes(n)
          slice = @data.byteslice(@offset, n)
          @offset += n
          slice
        end

        # Reads all remaining bytes from the current offset.
        #
        # @return [String] binary string
        def read_remaining
          slice = @data.byteslice(@offset, @data.bytesize - @offset) || ''.b
          @offset = @data.bytesize
          slice
        end

        # Reads a VarInt-prefixed byte array.
        #
        # @return [String] binary string
        def read_byte_array
          len = read_varint
          read_bytes(len)
        end

        # Reads an optional VarInt-prefixed byte array; returns nil for the -1 sentinel.
        #
        # @return [String, nil]
        def read_optional_byte_array
          len = read_signed_varint
          return nil if len == -1

          read_bytes(len)
        end

        # Reads a VarInt-prefixed UTF-8 string.
        #
        # @return [String]
        def read_utf8_string
          len = read_varint
          read_bytes(len).force_encoding('UTF-8')
        end

        # Reads an optional VarInt-prefixed UTF-8 string; returns nil for the -1 sentinel.
        #
        # @return [String, nil]
        def read_optional_utf8_string
          len = read_signed_varint
          return nil if len == -1

          read_bytes(len).force_encoding('UTF-8')
        end

        # Reads a signed Int8 optional boolean: 1=true, 0=false, -1=nil.
        #
        # @return [Boolean, nil]
        def read_optional_bool
          val = read_int8
          return nil if val == -1

          val == 1
        end

        # Reads an outpoint: 32 bytes (txid hex in display order) + VarInt index.
        #
        # @return [Array(String, Integer)] [txid_hex, index]
        def read_outpoint
          txid_bytes = read_bytes(32)
          txid_hex = txid_bytes.unpack1('H*')
          index = read_varint
          [txid_hex, index]
        end

        # Reads a counterparty value using the first-byte dispatch scheme.
        #
        # @return [String, nil] 'self', 'anyone', nil, or 66-char hex pubkey
        def read_counterparty
          flag = read_byte
          case flag
          when 11
            'self'
          when 12
            'anyone'
          when 0
            nil
          else
            # First byte is part of the 33-byte compressed pubkey; read 32 more
            remaining = read_bytes(32)
            ([flag].pack('C') + remaining).unpack1('H*')
          end
        end

        # Reads a protocol ID: UInt8 security level + VarInt-prefixed UTF-8 name.
        #
        # @return [Array(Integer, String)] [level, name]
        def read_protocol_id
          level = read_byte
          name = read_utf8_string
          [level, name]
        end

        # Reads an optional string array: VarInt count + strings, or nil for the -1 sentinel.
        #
        # @return [Array<String>, nil]
        def read_string_array
          count = read_signed_varint
          return nil if count == -1

          count.times.map { read_utf8_string }
        end

        # Reads an optional string→string map: VarInt count + key/value pairs, or nil.
        #
        # @return [Hash, nil]
        def read_map
          count = read_signed_varint
          return nil if count == -1

          count.times.each_with_object({}) do |_, hash|
            key = read_utf8_string
            val = read_utf8_string
            hash[key] = val
          end
        end

        # Reads privileged parameters: optional bool + Int8-length reason string.
        #
        # @return [Array(Boolean|nil, String|nil)] [privileged, privileged_reason]
        def read_privileged
          privileged = read_optional_bool
          reason_len = read_int8
          privileged_reason = if reason_len == -1
                                nil
                              elsif reason_len.negative?
                                raise ArgumentError, "invalid privileged_reason length: #{reason_len}"
                              else
                                read_bytes(reason_len).force_encoding('UTF-8')
                              end
          [privileged, privileged_reason]
        end

        private

        def require_bytes(n)
          raise ArgumentError, "negative byte count: #{n}" if n.negative?

          remaining = @data.bytesize - @offset
          return if remaining >= n

          raise ArgumentError,
                "truncated wire data: need #{n} bytes at offset #{@offset}, " \
                "got #{remaining}"
        end
      end
    end
  end
end
