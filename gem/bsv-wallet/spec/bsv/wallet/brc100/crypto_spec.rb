# frozen_string_literal: true

RSpec.describe 'BSV::Wallet::BRC100::Crypto' do
  let(:klass) do
    Class.new do
      include BSV::Wallet::BRC100::Crypto
    end
  end
  let(:obj) { klass.new }

  %w[encrypt decrypt create_hmac verify_hmac create_signature verify_signature].each do |method|
    describe "##{method}" do
      it 'raises UnsupportedActionError' do
        expect { obj.public_send(method, {}) }.to raise_error(BSV::Wallet::UnsupportedActionError)
      end
    end
  end
end
