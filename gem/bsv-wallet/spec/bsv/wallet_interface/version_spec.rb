# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe 'BSV::WalletInterface::VERSION' do
  it 'is a semver string' do
    expect(BSV::WalletInterface::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
