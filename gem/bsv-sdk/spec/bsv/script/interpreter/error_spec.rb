# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV::Script::ScriptError do
  it 'is a StandardError' do
    expect(described_class.ancestors).to include(StandardError)
  end

  it 'carries the error code' do
    error = described_class.new(:eval_false, 'script evaluated to false')
    expect(error.code).to eq(:eval_false)
    expect(error.message).to eq('script evaluated to false')
  end

  it 'generates a default message from the code' do
    error = described_class.new(:invalid_stack_operation)
    expect(error.message).to eq('invalid stack operation')
  end

  describe BSV::Script::ScriptErrorCode do
    it 'defines all expected error codes' do
      codes = %i[
        eval_false empty_stack verify_failed equalverify_failed
        numequalverify_failed checksigverify_failed checkmultisigverify_failed
        unbalanced_conditional disabled_opcode reserved_opcode
        invalid_stack_operation malformed_push number_too_big divide_by_zero
        invalid_input_length invalid_pubkey_count invalid_sig_count
        sig_nullfail sig_nulldummy invalid_sighash_type early_return
        invalid_opcode minimal_data
      ]

      codes.each do |code|
        const_name = code.to_s.upcase.to_sym
        expect(described_class.const_get(const_name)).to eq(code)
      end
    end
  end
end
