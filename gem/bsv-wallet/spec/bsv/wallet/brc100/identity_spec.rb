# frozen_string_literal: true

RSpec.describe 'BSV::Wallet::BRC100::Identity' do
  let(:klass) do
    Class.new do
      include BSV::Wallet::BRC100::Identity
    end
  end
  let(:obj) { klass.new }

  %w[acquire_certificate list_certificates prove_certificate
     relinquish_certificate discover_by_identity_key discover_by_attributes].each do |method|
    describe "##{method}" do
      it 'raises UnsupportedActionError' do
        expect { obj.public_send(method, {}) }.to raise_error(BSV::Wallet::UnsupportedActionError)
      end
    end
  end
end
