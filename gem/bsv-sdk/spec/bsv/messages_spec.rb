# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'BSV::Messages namespace' do
  let(:sender) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(15)) }
  let(:recipient) { BSV::Primitives::PrivateKey.new(OpenSSL::BN.new(21)) }
  let(:message) { 'hello world' }

  describe 'BSV::Messages::SignedMessage' do
    it 'is the same constant as BSV::Primitives::SignedMessage' do
      expect(BSV::Messages::SignedMessage).to equal(BSV::Primitives::SignedMessage)
    end

    it 'can sign and verify a message' do
      sig = BSV::Messages::SignedMessage.sign(message, sender, recipient.public_key)
      expect(BSV::Messages::SignedMessage.verify(message, sig, recipient)).to be true
    end
  end

  describe 'BSV::Messages::EncryptedMessage' do
    it 'is the same constant as BSV::Primitives::EncryptedMessage' do
      expect(BSV::Messages::EncryptedMessage).to equal(BSV::Primitives::EncryptedMessage)
    end

    it 'can encrypt and decrypt a message' do
      ct = BSV::Messages::EncryptedMessage.encrypt(message, sender, recipient.public_key)
      expect(BSV::Messages::EncryptedMessage.decrypt(ct, recipient)).to eq(message)
    end
  end

  describe 'BSV::Primitives namespace unaffected' do
    it 'BSV::Primitives::SignedMessage still works directly' do
      sig = BSV::Primitives::SignedMessage.sign(message, sender, recipient.public_key)
      expect(BSV::Primitives::SignedMessage.verify(message, sig, recipient)).to be true
    end

    it 'BSV::Primitives::EncryptedMessage still works directly' do
      ct = BSV::Primitives::EncryptedMessage.encrypt(message, sender, recipient.public_key)
      expect(BSV::Primitives::EncryptedMessage.decrypt(ct, recipient)).to eq(message)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
