# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'BSV::Overlay types' do
  describe BSV::Overlay::TaggedBEEF do
    subject(:tagged_beef) { described_class.new(beef: "\x01\x02\x03", topics: ['tm_example']) }

    it 'exposes beef' do
      expect(tagged_beef.beef).to eq("\x01\x02\x03")
    end

    it 'exposes topics' do
      expect(tagged_beef.topics).to eq(['tm_example'])
    end

    it 'accepts multiple topics' do
      instance = described_class.new(beef: '', topics: %w[tm_a tm_b])
      expect(instance.topics).to eq(%w[tm_a tm_b])
    end
  end

  describe BSV::Overlay::AdmittanceInstructions do
    it 'exposes outputs_to_admit' do
      instance = described_class.new(outputs_to_admit: [0, 1], coins_to_retain: [2])
      expect(instance.outputs_to_admit).to eq([0, 1])
    end

    it 'exposes coins_to_retain' do
      instance = described_class.new(outputs_to_admit: [0, 1], coins_to_retain: [2])
      expect(instance.coins_to_retain).to eq([2])
    end

    it 'defaults coins_removed to nil' do
      instance = described_class.new(outputs_to_admit: [], coins_to_retain: [])
      expect(instance.coins_removed).to be_nil
    end

    it 'accepts coins_removed when provided' do
      instance = described_class.new(outputs_to_admit: [0], coins_to_retain: [], coins_removed: [3])
      expect(instance.coins_removed).to eq([3])
    end
  end

  describe BSV::Overlay::LookupQuestion do
    subject(:question) { described_class.new(service: 'ls_ship', query: { topics: ['tm_example'] }) }

    it 'exposes service' do
      expect(question.service).to eq('ls_ship')
    end

    it 'exposes query' do
      expect(question.query).to eq({ topics: ['tm_example'] })
    end
  end

  describe BSV::Overlay::LookupAnswer do
    subject(:answer) do
      described_class.new(type: 'output-list', outputs: [{ beef: [], output_index: 0 }])
    end

    it 'exposes type' do
      expect(answer.type).to eq('output-list')
    end

    it 'exposes outputs' do
      expect(answer.outputs).to eq([{ beef: [], output_index: 0 }])
    end
  end

  describe BSV::Overlay::OverlayBroadcastResult do
    context 'when successful' do
      subject(:result) do
        described_class.new(
          status: 'success',
          txid: 'abc123',
          message: 'Sent to 1 host.'
        )
      end

      it 'exposes status' do
        expect(result.status).to eq('success')
      end

      it 'exposes txid' do
        expect(result.txid).to eq('abc123')
      end

      it 'exposes message' do
        expect(result.message).to eq('Sent to 1 host.')
      end

      it 'has nil code' do
        expect(result.code).to be_nil
      end

      it 'has nil description' do
        expect(result.description).to be_nil
      end
    end

    context 'when an error occurs' do
      subject(:result) do
        described_class.new(
          status: 'error',
          code: 'ERR_NO_HOSTS_INTERESTED',
          description: 'No mainnet hosts are interested.'
        )
      end

      it 'exposes status' do
        expect(result.status).to eq('error')
      end

      it 'exposes code' do
        expect(result.code).to eq('ERR_NO_HOSTS_INTERESTED')
      end

      it 'exposes description' do
        expect(result.description).to eq('No mainnet hosts are interested.')
      end

      it 'has nil txid' do
        expect(result.txid).to be_nil
      end

      it 'has nil message' do
        expect(result.message).to be_nil
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
