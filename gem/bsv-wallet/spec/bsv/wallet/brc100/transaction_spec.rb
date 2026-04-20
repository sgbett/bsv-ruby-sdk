# frozen_string_literal: true

RSpec.describe 'BSV::Wallet::BRC100::Transaction' do
  let(:klass) do
    Class.new do
      include BSV::Wallet::BRC100::Transaction
    end
  end
  let(:obj) { klass.new }

  %w[create_action sign_action abort_action list_actions
     internalize_action list_outputs relinquish_output].each do |method|
    describe "##{method}" do
      it 'raises UnsupportedActionError' do
        expect { obj.public_send(method, {}) }.to raise_error(BSV::Wallet::UnsupportedActionError)
      end
    end
  end
end
