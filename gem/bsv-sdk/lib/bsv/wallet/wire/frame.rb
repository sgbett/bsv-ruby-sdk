# frozen_string_literal: true

module BSV
  module Wallet
    module Wire
      # BRC-103 request and result frame codec.
      #
      # Port of go-sdk/wallet/serializer/frame.go. Two frame types:
      #
      # Request frame (client → wallet):
      #   [1 byte: call][1 byte: originator_len][originator_len bytes: UTF-8][remaining: params]
      #
      # Result frame (wallet → client):
      #   [1 byte: error_code]
      #   On success (0x00): [remaining bytes: payload]
      #   On error (non-zero):
      #     [VarInt: message_len][message bytes]
      #     [VarInt: stack_len][stack bytes]
      module Frame
        # Maximum originator byte length enforced at write time.
        # Matches the BRC-100 +OriginatorDomainNameStringUnder250Bytes+ branded
        # type used by +Wire::Validation.originator_domain!+.
        MAX_ORIGINATOR_BYTES = 250

        module_function

        # Encode a request frame.
        #
        # @param call [Integer] call byte (1..28)
        # @param originator [String] originator domain (0..250 bytes UTF-8)
        # @param params [String, nil] binary params payload
        # @return [String] binary frame (ASCII-8BIT encoding)
        # @raise [ArgumentError] if originator exceeds 250 bytes
        def write_request(call:, originator:, params: nil)
          originator_bytes = originator.to_s.b
          if originator_bytes.bytesize > MAX_ORIGINATOR_BYTES
            raise ArgumentError,
                  "originator must be at most #{MAX_ORIGINATOR_BYTES} bytes, " \
                  "got #{originator_bytes.bytesize}"
          end

          buf = String.new(encoding: 'BINARY')
          buf << [call, originator_bytes.bytesize].pack('CC')
          buf << originator_bytes
          buf << params.b if params && !params.empty?
          buf
        end

        # Decode a request frame.
        #
        # @param bytes [String] binary frame
        # @return [Hash] { call: Integer, originator: String, params: String }
        # @raise [ArgumentError] if the frame is truncated or malformed
        def read_request(bytes)
          data = bytes.b
          raise ArgumentError, 'frame too short: need at least 2 bytes' if data.bytesize < 2

          call = data.getbyte(0)
          originator_len = data.getbyte(1)

          if data.bytesize < 2 + originator_len
            raise ArgumentError,
                  "frame truncated: need #{2 + originator_len} bytes for originator, " \
                  "got #{data.bytesize}"
          end

          originator = data.byteslice(2, originator_len).force_encoding('UTF-8')
          raise ArgumentError, 'frame originator is not valid UTF-8' unless originator.valid_encoding?

          params = data.byteslice(2 + originator_len, data.bytesize - 2 - originator_len) || ''.b

          { call: call, originator: originator, params: params }
        end

        # Encode a success result frame.
        #
        # @param payload [String, nil] binary payload
        # @return [String] binary frame
        def write_result(payload: nil)
          buf = String.new(encoding: 'BINARY')
          buf << "\x00"
          buf << payload.b if payload && !payload.empty?
          buf
        end

        # Encode an error result frame.
        #
        # @param error [BSV::Wallet::Error] the error to encode
        # @return [String] binary frame
        def write_error(error:)
          wire = error.to_wire
          msg_bytes = wire[:message].to_s.b
          stack_bytes = wire[:stack].to_s.b

          buf = String.new(encoding: 'BINARY')
          buf << [wire[:code]].pack('C')
          buf << encode_varint(msg_bytes.bytesize)
          buf << msg_bytes
          buf << encode_varint(stack_bytes.bytesize)
          buf << stack_bytes
          buf
        end

        # Decode a result frame.
        #
        # @param bytes [String] binary frame
        # @return [String] binary payload on success
        # @raise [BSV::Wallet::Error] the appropriate subclass on error
        # @raise [ArgumentError] if the frame is truncated or malformed
        def read_result(bytes)
          data = bytes.b
          raise ArgumentError, 'result frame is empty' if data.empty?

          code = data.getbyte(0)

          return data.byteslice(1, data.bytesize - 1) || ''.b if code.zero?

          offset = 1
          msg_len, vi = decode_varint(data, offset)
          offset += vi

          raise ArgumentError, 'result frame truncated: message' if data.bytesize < offset + msg_len

          message = data.byteslice(offset, msg_len).force_encoding('UTF-8')
          raise ArgumentError, 'result frame error message is not valid UTF-8' unless message.valid_encoding?

          offset += msg_len

          stack_len, vi = decode_varint(data, offset)
          offset += vi

          raise ArgumentError, 'result frame truncated: stack' if data.bytesize < offset + stack_len

          stack = data.byteslice(offset, stack_len).force_encoding('UTF-8')
          raise ArgumentError, 'result frame stack is not valid UTF-8' unless stack.valid_encoding?

          raise BSV::Wallet.error_from_wire(code, message, stack)
        end

        # @param n [Integer] unsigned integer
        # @return [String] Bitcoin varint encoding
        def encode_varint(n)
          if n < 0xFD
            [n].pack('C')
          elsif n <= 0xFFFF
            [0xFD, n].pack('Cv')
          elsif n <= 0xFFFFFFFF
            [0xFE, n].pack('CV')
          else
            [0xFF, n].pack('CQ<')
          end
        end

        # @param data [String] binary data
        # @param offset [Integer] byte offset
        # @return [Array(Integer, Integer)] decoded value, bytes consumed
        def decode_varint(data, offset = 0)
          raise ArgumentError, "varint: need 1 byte at #{offset}" if offset >= data.bytesize

          first = data.getbyte(offset)
          case first
          when 0..0xFC
            [first, 1]
          when 0xFD
            raise ArgumentError, "varint: need 3 bytes at #{offset}" if data.bytesize < offset + 3

            [data.byteslice(offset + 1, 2).unpack1('v'), 3]
          when 0xFE
            raise ArgumentError, "varint: need 5 bytes at #{offset}" if data.bytesize < offset + 5

            [data.byteslice(offset + 1, 4).unpack1('V'), 5]
          when 0xFF
            raise ArgumentError, "varint: need 9 bytes at #{offset}" if data.bytesize < offset + 9

            [data.byteslice(offset + 1, 8).unpack1('Q<'), 9]
          end
        end
      end
    end
  end
end
