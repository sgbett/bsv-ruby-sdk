# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Wallet::Error do
  describe '#code' do
    it 'defaults to 1' do
      expect(described_class.new('oops').code).to eq(1)
    end

    it 'accepts an explicit code' do
      expect(described_class.new('oops', code: 5).code).to eq(5)
    end
  end

  describe '#wallet_stack' do
    it 'defaults to empty string' do
      expect(described_class.new('oops').wallet_stack).to eq('')
    end

    it 'stores the provided stack' do
      expect(described_class.new('oops', stack: 'at line 1').wallet_stack).to eq('at line 1')
    end
  end

  describe '#to_wire' do
    it 'returns a hash with code, message, and stack' do
      err = described_class.new('something failed', code: 3, stack: 'trace')
      expect(err.to_wire).to eq({ code: 3, message: 'something failed', stack: 'trace' })
    end

    it 'coerces nil message to empty string' do
      err = described_class.new(nil, code: 1)
      expect(err.to_wire[:message]).to eq('')
    end

    it 'includes wallet_stack not Ruby backtrace' do
      err = described_class.new('oops', code: 1, stack: 'wire_trace')
      expect(err.to_wire[:stack]).to eq('wire_trace')
    end
  end

  describe BSV::Wallet::UnsupportedActionError do
    it 'has code 2' do
      expect(described_class.new.code).to eq(2)
    end

    it 'accepts a custom message' do
      err = described_class.new('do_something is not supported')
      expect(err.message).to eq('do_something is not supported')
    end

    it 'round-trips via to_wire' do
      err = described_class.new('my_method not supported', stack: 'trace')
      expect(err.to_wire[:code]).to eq(2)
      expect(err.to_wire[:stack]).to eq('trace')
    end
  end

  describe BSV::Wallet::InvalidHmacError do
    it 'has code 3' do
      expect(described_class.new.code).to eq(3)
    end

    it 'accepts a custom message' do
      expect(described_class.new('bad hmac').message).to eq('bad hmac')
    end
  end

  describe BSV::Wallet::InvalidSignatureError do
    it 'has code 4' do
      expect(described_class.new.code).to eq(4)
    end
  end

  describe BSV::Wallet::InsufficientFundsError do
    it 'has code 5' do
      expect(described_class.new.code).to eq(5)
    end

    it 'accepts a custom message' do
      err = described_class.new('need 1000 sats')
      expect(err.message).to eq('need 1000 sats')
      expect(err.code).to eq(5)
    end
  end

  describe BSV::Wallet::InvalidParameterError do
    it 'has code 6' do
      expect(described_class.new('pubkey', 'a hex string').code).to eq(6)
    end

    it 'stores the parameter name' do
      err = described_class.new('pubkey', 'a hex string')
      expect(err.parameter).to eq('pubkey')
    end

    it 'builds a descriptive message from parameter + must_be' do
      err = described_class.new('pubkey', 'a hex string')
      expect(err.message).to eq('the pubkey parameter must be a hex string')
    end

    it 'uses first arg as raw message when must_be is nil (wire rehydration path)' do
      err = described_class.new('bad pubkey', nil)
      expect(err.message).to eq('bad pubkey')
    end
  end

  describe BSV::Wallet::ReviewActionsError do
    it 'has code 7' do
      expect(described_class.new.code).to eq(7)
    end

    it 'accepts a custom message' do
      err = described_class.new('please review')
      expect(err.message).to eq('please review')
    end
  end

  describe 'BSV::Wallet.error_from_wire' do
    {
      2 => BSV::Wallet::UnsupportedActionError,
      3 => BSV::Wallet::InvalidHmacError,
      4 => BSV::Wallet::InvalidSignatureError,
      5 => BSV::Wallet::InsufficientFundsError,
      6 => BSV::Wallet::InvalidParameterError,
      7 => BSV::Wallet::ReviewActionsError
    }.each do |code, klass|
      it "rehydrates code #{code} as #{klass}" do
        err = BSV::Wallet.error_from_wire(code, 'test message', 'trace')
        expect(err).to be_a(klass)
        expect(err.message).to eq('test message')
        expect(err.wallet_stack).to eq('trace')
        expect(err.code).to eq(code)
      end
    end

    it 'falls back to Error for unknown codes' do
      err = BSV::Wallet.error_from_wire(99, 'unknown', '')
      expect(err).to be_a(described_class)
      expect(err.code).to eq(99)
    end

    it 'defaults stack to empty string when omitted' do
      err = BSV::Wallet.error_from_wire(5, 'need funds')
      expect(err.wallet_stack).to eq('')
    end

    it 'code 6 rehydrates as InvalidParameterError with the wire message' do
      err = BSV::Wallet.error_from_wire(6, 'bad pubkey')
      expect(err).to be_a(BSV::Wallet::InvalidParameterError)
      expect(err.message).to eq('bad pubkey')
    end
  end
end
