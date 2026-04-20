# frozen_string_literal: true

RSpec.describe 'BSV::Wallet::BRC100::KeyManagement' do
  let(:klass) do
    Class.new do
      include BSV::Wallet::BRC100::KeyManagement
    end
  end
  let(:obj) { klass.new }

  %w[get_public_key reveal_counterparty_key_linkage reveal_specific_key_linkage].each do |method|
    describe "##{method}" do
      it 'raises UnsupportedActionError' do
        expect { obj.public_send(method, {}) }.to raise_error(BSV::Wallet::UnsupportedActionError)
      end
    end
  end
end
