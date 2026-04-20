# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::Store do
  let(:adapter_class) { Class.new { include BSV::Wallet::Store } }
  let(:adapter) { adapter_class.new }

  %i[store_action find_actions store_output find_outputs store_certificate find_certificates].each do |method_name|
    it "raises NotImplementedError for ##{method_name}" do
      expect { adapter.send(method_name, {}) }.to raise_error(NotImplementedError)
    end
  end

  it 'raises NotImplementedError for #delete_output' do
    expect { adapter.delete_output('abc.0') }.to raise_error(NotImplementedError)
  end

  it 'raises NotImplementedError for #delete_certificate' do
    expect { adapter.delete_certificate(type: 'x', serial_number: 'y', certifier: 'z') }.to raise_error(NotImplementedError)
  end

  it 'raises NotImplementedError for #store_proof' do
    expect { adapter.store_proof('txid', 'bump_hex') }.to raise_error(NotImplementedError)
  end

  it 'raises NotImplementedError for #find_proof' do
    expect { adapter.find_proof('txid') }.to raise_error(NotImplementedError)
  end

  it 'raises NotImplementedError for #store_transaction' do
    expect { adapter.store_transaction('txid', 'tx_hex') }.to raise_error(NotImplementedError)
  end

  it 'raises NotImplementedError for #find_transaction' do
    expect { adapter.find_transaction('txid') }.to raise_error(NotImplementedError)
  end

  it 'raises NotImplementedError for #update_output_state' do
    expect { adapter.update_output_state('abc.0', :pending) }.to raise_error(NotImplementedError)
  end

  it 'raises NotImplementedError for #find_spendable_outputs' do
    expect { adapter.find_spendable_outputs }.to raise_error(NotImplementedError)
  end

  it 'includes the class name in NotImplementedError messages' do
    expect { adapter.store_action({}) }.to raise_error(NotImplementedError, /store_action/)
  end

  it 'can be included in a class that overrides all methods' do
    custom_class = Class.new do
      include BSV::Wallet::Store

      def store_action(_data)
        :stored
      end

      def find_actions(_query)
        []
      end

      def store_output(_data)
        :stored
      end

      def find_outputs(_query)
        []
      end

      def delete_output(_outpoint)
        true
      end

      def store_certificate(_data)
        :stored
      end

      def find_certificates(_query)
        []
      end

      def delete_certificate(type:, serial_number:, certifier:) # rubocop:disable Lint/UnusedMethodArgument
        true
      end
    end

    custom = custom_class.new
    expect(custom.store_action({})).to eq(:stored)
    expect(custom.find_actions({})).to eq([])
    expect(custom.delete_output('abc.0')).to be true
    expect(custom.delete_certificate(type: 'x', serial_number: 'y', certifier: 'z')).to be true
  end
end
