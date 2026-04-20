# frozen_string_literal: true

RSpec.describe 'BSV::Wallet::BRC100::Authentication' do
  let(:klass) do
    Class.new do
      include BSV::Wallet::BRC100::Authentication
    end
  end
  let(:obj) { klass.new }

  %w[is_authenticated wait_for_authentication].each do |method|
    describe "##{method}" do
      it 'raises UnsupportedActionError with no args' do
        expect { obj.public_send(method) }.to raise_error(BSV::Wallet::UnsupportedActionError)
      end

      it 'raises UnsupportedActionError with empty hash' do
        expect { obj.public_send(method, {}) }.to raise_error(BSV::Wallet::UnsupportedActionError)
      end
    end
  end
end
