# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::MemoryStore do
  let(:store) { described_class.new }

  it_behaves_like 'a storage adapter'
end
