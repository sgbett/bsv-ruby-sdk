# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BSV do
  it 'has a version number' do
    expect(BSV::VERSION).not_to be_nil
  end

  describe 'TXID_FORMAT_WIRE' do
    it 'equals "wire"' do
      expect(BSV::TXID_FORMAT_WIRE).to eq('wire')
    end

    it 'is frozen' do
      expect(BSV::TXID_FORMAT_WIRE).to be_frozen
    end
  end

  describe 'TXID_FORMAT_DISPLAY' do
    it 'equals "display"' do
      expect(BSV::TXID_FORMAT_DISPLAY).to eq('display')
    end

    it 'is frozen' do
      expect(BSV::TXID_FORMAT_DISPLAY).to be_frozen
    end
  end
end
