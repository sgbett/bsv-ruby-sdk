# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe 'BSV::Wallet::VERSION' do
  it 'is a semver string' do
    expect(BSV::Wallet::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
