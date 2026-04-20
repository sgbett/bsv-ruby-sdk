# frozen_string_literal: true

RSpec.describe 'BSV::Wallet::BRC100::Network' do
  let(:klass) do
    Class.new do
      include BSV::Wallet::BRC100::Network
    end
  end
  let(:obj) { klass.new }

  %w[get_height get_network get_version].each do |method|
    describe "##{method}" do
      it 'raises UnsupportedActionError with no args' do
        expect { obj.public_send(method) }.to raise_error(BSV::Wallet::UnsupportedActionError)
      end

      it 'raises UnsupportedActionError with empty hash' do
        expect { obj.public_send(method, {}) }.to raise_error(BSV::Wallet::UnsupportedActionError)
      end
    end
  end

  describe '#get_header_for_height' do
    it 'raises UnsupportedActionError' do
      expect { obj.get_header_for_height({}) }.to raise_error(BSV::Wallet::UnsupportedActionError)
    end
  end
end
