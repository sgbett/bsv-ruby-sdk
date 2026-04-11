# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'BSV::Registry::Constants' do
  describe 'topic names' do
    it 'defines TOPIC_BASKET' do
      expect(BSV::Registry::Constants::TOPIC_BASKET).to eq('tm_basketmap')
    end

    it 'defines TOPIC_PROTOCOL' do
      expect(BSV::Registry::Constants::TOPIC_PROTOCOL).to eq('tm_protomap')
    end

    it 'defines TOPIC_CERTIFICATE' do
      expect(BSV::Registry::Constants::TOPIC_CERTIFICATE).to eq('tm_certmap')
    end
  end

  describe 'service names' do
    it 'defines SERVICE_BASKET' do
      expect(BSV::Registry::Constants::SERVICE_BASKET).to eq('ls_basketmap')
    end

    it 'defines SERVICE_PROTOCOL' do
      expect(BSV::Registry::Constants::SERVICE_PROTOCOL).to eq('ls_protomap')
    end

    it 'defines SERVICE_CERTIFICATE' do
      expect(BSV::Registry::Constants::SERVICE_CERTIFICATE).to eq('ls_certmap')
    end
  end

  describe 'protocol IDs' do
    it 'defines PROTOCOL_BASKET as [1, basketmap]' do
      expect(BSV::Registry::Constants::PROTOCOL_BASKET).to eq([1, 'basketmap'])
    end

    it 'defines PROTOCOL_PROTOCOL as [1, protomap]' do
      expect(BSV::Registry::Constants::PROTOCOL_PROTOCOL).to eq([1, 'protomap'])
    end

    it 'defines PROTOCOL_CERTIFICATE as [1, certmap]' do
      expect(BSV::Registry::Constants::PROTOCOL_CERTIFICATE).to eq([1, 'certmap'])
    end
  end

  describe 'basket names' do
    it 'defines BASKET_NAME_BASKET as basketmap' do
      expect(BSV::Registry::Constants::BASKET_NAME_BASKET).to eq('basketmap')
    end

    it 'defines BASKET_NAME_PROTOCOL as protomap' do
      expect(BSV::Registry::Constants::BASKET_NAME_PROTOCOL).to eq('protomap')
    end

    it 'defines BASKET_NAME_CERTIFICATE as certmap' do
      expect(BSV::Registry::Constants::BASKET_NAME_CERTIFICATE).to eq('certmap')
    end
  end

  describe 'token constants' do
    it 'defines KEY_ID as "1"' do
      expect(BSV::Registry::Constants::KEY_ID).to eq('1')
    end

    it 'defines TOKEN_AMOUNT as 1' do
      expect(BSV::Registry::Constants::TOKEN_AMOUNT).to eq(1)
    end
  end
end
