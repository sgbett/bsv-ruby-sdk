# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe BSV::Wallet::Client do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:storage) { BSV::Wallet::Store::Memory.new }

  describe '#initialize' do
    context 'without chain_data_source' do
      it 'defaults chain_data_source to nil' do
        client = described_class.new(private_key, storage: storage, allow_memory_store: true)

        expect(client.chain_data_source).to be_nil
      end
    end

    context 'with chain_data_source' do
      let(:chain_data_source) { double('chain_data_source') } # rubocop:disable RSpec/VerifiedDoubles

      it 'stores the chain_data_source' do
        client = described_class.new(
          private_key,
          storage: storage,
          chain_data_source: chain_data_source,
          allow_memory_store: true
        )

        expect(client.chain_data_source).to be(chain_data_source)
      end
    end
  end
end
