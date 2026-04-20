# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::Interface::BRC100 do
  let(:wallet_class) { Class.new { include BSV::Wallet::Interface::BRC100 } }
  let(:wallet) { wallet_class.new }

  # All 28 BRC-100 method names
  let(:all_methods) do
    %i[
      create_action sign_action abort_action list_actions
      internalize_action list_outputs relinquish_output
      get_public_key reveal_counterparty_key_linkage reveal_specific_key_linkage
      encrypt decrypt create_hmac verify_hmac create_signature verify_signature
      acquire_certificate list_certificates prove_certificate relinquish_certificate
      discover_by_identity_key discover_by_attributes
      get_height get_header_for_height get_network get_version
      is_authenticated wait_for_authentication
    ]
  end

  # Methods that have default args and can be called with no arguments
  let(:no_arg_methods) do
    %i[get_height get_network get_version is_authenticated wait_for_authentication]
  end

  it 'defines all 28 BRC-100 methods' do
    all_methods.each do |method_name|
      expect(wallet).to respond_to(method_name)
    end
  end

  it 'raises UnsupportedActionError for every method that requires args' do
    (all_methods - no_arg_methods).each do |method_name|
      expect { wallet.send(method_name, {}) }.to raise_error(BSV::Wallet::UnsupportedActionError)
    end
  end

  it 'raises UnsupportedActionError for every no-arg method' do
    no_arg_methods.each do |method_name|
      expect { wallet.send(method_name) }.to raise_error(BSV::Wallet::UnsupportedActionError)
    end
  end

  it 'includes the method name in the UnsupportedActionError message' do
    expect { wallet.create_action({}) }.to raise_error(BSV::Wallet::UnsupportedActionError, /create_action/)
  end
end
