# frozen_string_literal: true

ALL_28_METHODS = %w[
  create_action sign_action abort_action list_actions internalize_action
  list_outputs relinquish_output
  get_public_key reveal_counterparty_key_linkage reveal_specific_key_linkage
  encrypt decrypt create_hmac verify_hmac create_signature verify_signature
  acquire_certificate list_certificates prove_certificate relinquish_certificate
  discover_by_identity_key discover_by_attributes
  is_authenticated wait_for_authentication
  get_height get_header_for_height get_network get_version
].freeze

NO_ARG_METHODS = %w[
  get_height get_network get_version is_authenticated wait_for_authentication
].freeze

RSpec.describe 'BSV::Wallet::BRC100::Interface' do
  let(:klass) do
    Class.new do
      include BSV::Wallet::BRC100::Interface
    end
  end
  let(:obj) { klass.new }

  it 'responds to all 28 BRC-100 methods' do
    ALL_28_METHODS.each do |method|
      expect(obj).to respond_to(method)
    end
  end

  it 'includes all 6 sub-modules' do
    expect(klass.ancestors).to include(BSV::Wallet::BRC100::Transaction)
    expect(klass.ancestors).to include(BSV::Wallet::BRC100::KeyManagement)
    expect(klass.ancestors).to include(BSV::Wallet::BRC100::Crypto)
    expect(klass.ancestors).to include(BSV::Wallet::BRC100::Identity)
    expect(klass.ancestors).to include(BSV::Wallet::BRC100::Authentication)
    expect(klass.ancestors).to include(BSV::Wallet::BRC100::Network)
  end

  ALL_28_METHODS.each do |method|
    describe "##{method}" do
      it 'raises UnsupportedActionError by default' do
        args = NO_ARG_METHODS.include?(method) ? [] : [{}]
        expect { obj.public_send(method, *args) }.to raise_error(BSV::Wallet::UnsupportedActionError)
      end
    end
  end
end
