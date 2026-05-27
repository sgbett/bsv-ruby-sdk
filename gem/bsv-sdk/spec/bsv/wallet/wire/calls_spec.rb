# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::Wallet::Wire::Calls' do
  subject(:calls) { BSV::Wallet::Wire::Calls }

  let(:interface_methods) do
    BSV::Wallet::Interface::BRC100.instance_methods(false)
  end

  describe 'constants 1..28' do
    it 'defines all 28 call byte constants' do
      expect(calls::CALL_TO_METHOD.keys).to match_array((1..28).to_a)
    end

    it 'has no gaps in the range 1..28' do
      expect(calls::CALL_TO_METHOD.keys.sort).to eq((1..28).to_a)
    end
  end

  describe 'CALL_TO_METHOD' do
    it 'maps every byte to a method that exists on Interface::BRC100' do
      calls::CALL_TO_METHOD.each do |byte, method_name|
        expect(interface_methods).to include(method_name),
                                     "call byte #{byte} maps to :#{method_name} which does not exist on Interface::BRC100"
      end
    end

    it 'maps call byte 23 to :authenticated? (predicate suffix preserved)' do
      expect(calls::CALL_TO_METHOD[23]).to eq(:authenticated?)
    end

    it 'does NOT map call byte 23 to :is_authenticated' do
      expect(calls::CALL_TO_METHOD.values).not_to include(:is_authenticated)
    end

    it 'maps call byte 1 to :create_action' do
      expect(calls::CALL_TO_METHOD[1]).to eq(:create_action)
    end

    it 'maps call byte 24 to :wait_for_authentication' do
      expect(calls::CALL_TO_METHOD[24]).to eq(:wait_for_authentication)
    end

    it 'maps call byte 28 to :get_version' do
      expect(calls::CALL_TO_METHOD[28]).to eq(:get_version)
    end
  end

  describe 'METHOD_TO_CALL' do
    it 'is the inverse of CALL_TO_METHOD' do
      calls::CALL_TO_METHOD.each do |byte, method_name|
        expect(calls::METHOD_TO_CALL[method_name]).to eq(byte)
      end
    end

    it 'maps :authenticated? back to 23' do
      expect(calls::METHOD_TO_CALL[:authenticated?]).to eq(23)
    end
  end

  describe 'constant values match Go SDK' do
    {
      'CREATE_ACTION' => 1,
      'SIGN_ACTION' => 2,
      'ABORT_ACTION' => 3,
      'LIST_ACTIONS' => 4,
      'INTERNALIZE_ACTION' => 5,
      'LIST_OUTPUTS' => 6,
      'RELINQUISH_OUTPUT' => 7,
      'GET_PUBLIC_KEY' => 8,
      'REVEAL_COUNTERPARTY_KEY_LINKAGE' => 9,
      'REVEAL_SPECIFIC_KEY_LINKAGE' => 10,
      'ENCRYPT' => 11,
      'DECRYPT' => 12,
      'CREATE_HMAC' => 13,
      'VERIFY_HMAC' => 14,
      'CREATE_SIGNATURE' => 15,
      'VERIFY_SIGNATURE' => 16,
      'ACQUIRE_CERTIFICATE' => 17,
      'LIST_CERTIFICATES' => 18,
      'PROVE_CERTIFICATE' => 19,
      'RELINQUISH_CERTIFICATE' => 20,
      'DISCOVER_BY_IDENTITY_KEY' => 21,
      'DISCOVER_BY_ATTRIBUTES' => 22,
      'IS_AUTHENTICATED' => 23,
      'WAIT_FOR_AUTHENTICATION' => 24,
      'GET_HEIGHT' => 25,
      'GET_HEADER_FOR_HEIGHT' => 26,
      'GET_NETWORK' => 27,
      'GET_VERSION' => 28
    }.each do |const_name, expected_value|
      it "#{const_name} == #{expected_value}" do
        expect(calls.const_get(const_name)).to eq(expected_value)
      end
    end
  end
end
