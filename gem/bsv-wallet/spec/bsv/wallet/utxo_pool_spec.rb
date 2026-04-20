# frozen_string_literal: true

require 'spec_helper'
require 'bsv-wallet'

RSpec.describe 'BSV::Wallet::Interface::UTXOPool interface' do
  # Use a fresh includer for each interface test
  let(:includer_class) do
    Class.new { include BSV::Wallet::Interface::UTXOPool }
  end

  let(:instance) { includer_class.new }

  describe 'MAX_RETRIES constant' do
    it 'equals 3' do
      expect(BSV::Wallet::Interface::UTXOPool::MAX_RETRIES).to eq(3)
    end
  end

  describe 'default #acquire' do
    it 'raises NotImplementedError' do
      expect { instance.acquire }.to raise_error(NotImplementedError)
    end
  end

  describe 'default #release' do
    it 'raises NotImplementedError' do
      expect { instance.release('txid.0') }.to raise_error(NotImplementedError)
    end
  end

  describe 'default #status' do
    it 'raises NotImplementedError' do
      expect { instance.status }.to raise_error(NotImplementedError)
    end
  end

  describe 'default #shutdown' do
    it 'raises NotImplementedError' do
      expect { instance.shutdown }.to raise_error(NotImplementedError)
    end
  end

  describe 'BSV::Wallet::PoolDepletedError' do
    it 'is a subclass of WalletError' do
      expect(BSV::Wallet::PoolDepletedError.ancestors).to include(BSV::Wallet::WalletError)
    end

    it 'includes the pool name in the message' do
      error = BSV::Wallet::PoolDepletedError.new('my-pool')
      expect(error.message).to include('my-pool')
    end

    it 'can be rescued as a WalletError' do
      expect do
        raise BSV::Wallet::PoolDepletedError, 'test-pool'
      end.to raise_error(BSV::Wallet::WalletError)
    end
  end
end
