# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Wallet::Wire::Frame do
  # --- Request frame round-trips ---

  describe '.write_request / .read_request' do
    it 'round-trips call=11, originator="app.example", params="abc"' do
      bytes = described_class.write_request(call: 11, originator: 'app.example', params: 'abc')
      result = described_class.read_request(bytes)

      expect(result[:call]).to eq(11)
      expect(result[:originator]).to eq('app.example')
      expect(result[:params]).to eq('abc'.b)
    end

    it 'round-trips with empty originator' do
      bytes = described_class.write_request(call: 1, originator: '', params: nil)
      result = described_class.read_request(bytes)

      expect(result[:originator]).to eq('')
      expect(result[:params]).to eq(''.b)
    end

    it 'round-trips with 250-byte originator (max one-byte length boundary)' do
      originator = 'a' * 250
      bytes = described_class.write_request(call: 1, originator: originator)
      result = described_class.read_request(bytes)
      expect(result[:originator]).to eq(originator)
    end

    it 'round-trips with 255-byte originator (absolute max)' do
      originator = 'x' * 255
      bytes = described_class.write_request(call: 1, originator: originator)
      result = described_class.read_request(bytes)
      expect(result[:originator]).to eq(originator)
    end

    it 'rejects originator longer than 255 bytes' do
      expect do
        described_class.write_request(call: 1, originator: 'x' * 256)
      end.to raise_error(ArgumentError, /255 bytes/)
    end

    it 'measures originator length in bytes, not characters (UTF-8 multi-byte)' do
      # 2-byte UTF-8 char × 127 = 254 bytes → allowed
      originator_254 = "\xC3\xA9" * 127 # 'é' repeated
      bytes = described_class.write_request(call: 1, originator: originator_254)
      result = described_class.read_request(bytes)
      expect(result[:originator].bytesize).to eq(254)
    end

    it 'produces correct wire layout for a known vector' do
      # call=2, originator="test" (4 bytes), params=0x01 0x02 0x03
      bytes = described_class.write_request(call: 2, originator: 'test', params: "\x01\x02\x03")
      hex = bytes.unpack1('H*')
      # 0x02 | 0x04 | 74 65 73 74 | 01 02 03
      expect(hex).to eq('0204746573740102 03'.delete(' '))
    end

    it 'raises ArgumentError on truncated frame' do
      expect { described_class.read_request("\x01") }.to raise_error(ArgumentError)
    end

    it 'raises ArgumentError when originator_len exceeds available bytes' do
      bad = "\x01\x10test".b # originator_len=16 but only 4 bytes follow
      expect { described_class.read_request(bad) }.to raise_error(ArgumentError)
    end
  end

  # --- Result frame — success path ---

  describe '.write_result / .read_result' do
    it 'round-trips a success frame with payload' do
      bytes = described_class.write_result(payload: "\x01\x02")
      result = described_class.read_result(bytes)
      expect(result).to eq("\x01\x02".b)
    end

    it 'round-trips a success frame with nil payload' do
      bytes = described_class.write_result(payload: nil)
      result = described_class.read_result(bytes)
      expect(result).to eq(''.b)
    end

    it 'encodes success as leading zero byte' do
      bytes = described_class.write_result(payload: "\xAA")
      expect(bytes.getbyte(0)).to eq(0)
    end
  end

  # --- Result frame — error path ---

  describe '.write_error / .read_result' do
    it 'encodes an InsufficientFundsError and read_result raises it' do
      error = BSV::Wallet::InsufficientFundsError.new('need 1000 sats')
      bytes = described_class.write_error(error: error)

      expect { described_class.read_result(bytes) }
        .to raise_error(BSV::Wallet::InsufficientFundsError, 'need 1000 sats')
    end

    it 'encodes code, varint-prefixed message, and varint-prefixed stack' do
      error = BSV::Wallet::InsufficientFundsError.new('need 1000 sats', stack: 'st')
      bytes = described_class.write_error(error: error)

      # byte 0 = code (5), then varint(14), then message, then varint(2), then "st"
      expect(bytes.getbyte(0)).to eq(5)
      msg = 'need 1000 sats'
      expect(bytes.getbyte(1)).to eq(msg.bytesize)
    end

    it 'raises the correct subclass for each error code' do
      {
        BSV::Wallet::UnsupportedActionError => BSV::Wallet::UnsupportedActionError,
        BSV::Wallet::InvalidHmacError => BSV::Wallet::InvalidHmacError,
        BSV::Wallet::InvalidSignatureError => BSV::Wallet::InvalidSignatureError,
        BSV::Wallet::InsufficientFundsError => BSV::Wallet::InsufficientFundsError,
        BSV::Wallet::InvalidParameterError => BSV::Wallet::InvalidParameterError,
        BSV::Wallet::ReviewActionsError => BSV::Wallet::ReviewActionsError
      }.each do |err_class, expected_class|
        error = err_class.new('msg')
        bytes = described_class.write_error(error: error)
        expect { described_class.read_result(bytes) }.to raise_error(expected_class)
      end
    end

    it 'preserves message and stack through round-trip' do
      error = BSV::Wallet::InvalidParameterError.new('raw message', nil, stack: 'trace here')
      bytes = described_class.write_error(error: error)

      begin
        described_class.read_result(bytes)
      rescue BSV::Wallet::InvalidParameterError => e
        expect(e.message).to eq('raw message')
        expect(e.wallet_stack).to eq('trace here')
      end
    end

    it 'raises ArgumentError on empty frame' do
      expect { described_class.read_result('') }.to raise_error(ArgumentError, /empty/)
    end
  end

  # --- Cross-SDK vector conformance ---
  # These hex values were derived from the Go SDK frame codec logic.

  describe 'Go SDK vector conformance' do
    it 'decodes request vector: call=1, originator="test-originator", no params' do
      # WriteRequestFrame({Call: 0x01, Originator: "test-originator"})
      # = 0x01 | 0x0F | "test-originator"
      hex = '010f746573742d6f726967696e61746f72'
      bytes = [hex].pack('H*')
      result = described_class.read_request(bytes)

      expect(result[:call]).to eq(1)
      expect(result[:originator]).to eq('test-originator')
      expect(result[:params]).to eq(''.b)
    end

    it 'decodes request vector: call=2, originator="another-originator", params=010203' do
      # WriteRequestFrame({Call: 0x02, Originator: "another-originator", Params: [0x01,0x02,0x03]})
      # = 0x02 | 0x12 | "another-originator" | 0x01 0x02 0x03
      hex = '021261 6e6f 7468 6572 2d6f 7269 6769 6e61 746f 7201 0203'.delete(' ')
      bytes = [hex].pack('H*')
      result = described_class.read_request(bytes)

      expect(result[:call]).to eq(2)
      expect(result[:originator]).to eq('another-originator')
      expect(result[:params]).to eq("\x01\x02\x03".b)
    end

    it 'encodes the request vector byte-for-byte: call=1, originator="test-originator"' do
      bytes = described_class.write_request(call: 1, originator: 'test-originator')
      expect(bytes.unpack1('H*')).to eq('010f746573742d6f726967696e61746f72')
    end

    it 'decodes error vector: code=1, message="test error", stack="stack trace"' do
      # WriteResultFrame(nil, &wallet.Error{Code:1, Message:"test error", Stack:"stack trace"})
      # = 0x01 | varint(10) | "test error" | varint(11) | "stack trace"
      msg = 'test error'
      stk = 'stack trace'
      bytes = described_class.write_error(
        error: BSV::Wallet::Error.new(msg, code: 1, stack: stk)
      )

      expect { described_class.read_result(bytes) }
        .to raise_error(BSV::Wallet::Error) do |e|
          expect(e.message).to eq(msg)
          expect(e.wallet_stack).to eq(stk)
        end
    end
  end
end
