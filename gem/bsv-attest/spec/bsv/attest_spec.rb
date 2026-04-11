# frozen_string_literal: true

require 'spec_helper'

require 'bsv-attest'
require 'securerandom'

RSpec.describe BSV::Attest do
  after { described_class.reset_configuration! }

  describe '.hash' do
    it 'returns a 32-byte binary SHA-256 digest' do
      result = described_class.hash('hello world')
      expect(result.bytesize).to eq(32)
      expect(result.encoding).to eq(Encoding::BINARY)
    end

    it 'matches BSV::Primitives::Digest.sha256' do
      data = 'test data'
      expect(described_class.hash(data)).to eq(BSV::Primitives::Digest.sha256(data))
    end
  end

  describe '.configure' do
    it 'yields the configuration' do
      wallet = Object.new
      described_class.configure do |config|
        config.wallet = wallet
      end

      expect(described_class.configuration.wallet).to eq(wallet)
    end
  end

  describe '.reset_configuration!' do
    it 'resets configuration to defaults' do
      described_class.configure { |c| c.wallet = Object.new }
      described_class.reset_configuration!

      expect(described_class.configuration.wallet).to be_nil
    end
  end

  describe '.publish' do
    let(:mock_wallet) do
      Class.new do
        def fund_and_sign(tx)
          tx
        end
      end.new
    end

    let(:mock_broadcaster) do
      Class.new do
        def broadcast(_tx)
          BSV::Network::BroadcastResponse.new(txid: 'bb' * 32)
        end
      end.new
    end

    it 'builds an OP_RETURN transaction, funds, signs, and broadcasts' do
      response = described_class.publish('test data', wallet: mock_wallet, broadcaster: mock_broadcaster)

      expect(response).to be_a(BSV::Attest::Response)
      expect(response.hash).to eq(BSV::Primitives::Digest.sha256('test data'))
      expect(response.txid).to eq('bb' * 32)
      expect(response.transaction).to be_a(BSV::Transaction::Transaction)
    end

    it 'includes the hash in an OP_RETURN output' do
      response = described_class.publish('test data', wallet: mock_wallet, broadcaster: mock_broadcaster)
      tx = response.transaction

      op_return_output = tx.outputs.first
      script = op_return_output.locking_script

      # After F3.1 fix: the parser absorbs all bytes after OP_RETURN into the
      # OP_RETURN chunk's data. Use op_return_data to extract individual payloads.
      expect(script.op_return?).to be true
      items = script.op_return_data
      expect(items).to include(BSV::Primitives::Digest.sha256('test data'))
    end

    it 'raises ArgumentError without wallet' do
      expect do
        described_class.publish('test data', broadcaster: mock_broadcaster)
      end.to raise_error(ArgumentError, /wallet/)
    end

    it 'raises ArgumentError without broadcaster' do
      expect do
        described_class.publish('test data', wallet: mock_wallet)
      end.to raise_error(ArgumentError, /broadcaster/)
    end

    it 'accepts per-call overrides over global configuration' do
      other_wallet = Class.new do
        attr_reader :called

        def fund_and_sign(tx)
          @called = true
          tx
        end
      end.new

      described_class.configure { |c| c.wallet = mock_wallet }

      described_class.publish('test data', wallet: other_wallet, broadcaster: mock_broadcaster)
      expect(other_wallet.called).to be true
    end

    it 'falls back to global configuration' do
      described_class.configure do |c|
        c.wallet = mock_wallet
        c.broadcaster = mock_broadcaster
      end

      response = described_class.publish('test data')
      expect(response).to be_a(BSV::Attest::Response)
    end
  end

  describe '.verify' do
    def build_mock_provider(data_to_attest)
      digest = BSV::Primitives::Digest.sha256(data_to_attest)
      script = BSV::Script::Script.op_return(digest)
      output = BSV::Transaction::TransactionOutput.new(satoshis: 0, locking_script: script)
      tx = BSV::Transaction::Transaction.new
      tx.add_output(output)

      Class.new do
        define_method(:fetch_transaction) { |_txid| tx }
      end.new
    end

    it 'returns true when hash is found in OP_RETURN output' do
      provider = build_mock_provider('test data')
      result = described_class.verify('test data', 'aa' * 32, provider: provider)
      expect(result).to be true
    end

    it 'raises VerificationError when hash is not found' do
      provider = build_mock_provider('test data')
      expect do
        described_class.verify('different data', 'aa' * 32, provider: provider)
      end.to raise_error(BSV::Attest::VerificationError, /hash not found/)
    end

    it 'raises ArgumentError without provider' do
      expect do
        described_class.verify('test data', 'aa' * 32)
      end.to raise_error(ArgumentError, /provider/)
    end

    it 'works with multi-push OP_RETURN outputs' do
      digest = BSV::Primitives::Digest.sha256('test data')
      prefix = 'ATTEST'.b
      script = BSV::Script::Script.op_return(prefix, digest)
      output = BSV::Transaction::TransactionOutput.new(satoshis: 0, locking_script: script)
      tx = BSV::Transaction::Transaction.new
      tx.add_output(output)

      provider = Class.new do
        define_method(:fetch_transaction) { |_txid| tx }
      end.new

      result = described_class.verify('test data', 'aa' * 32, provider: provider)
      expect(result).to be true
    end

    it 'falls back to global configuration' do
      provider = build_mock_provider('test data')
      described_class.configure { |c| c.provider = provider }

      result = described_class.verify('test data', 'aa' * 32)
      expect(result).to be true
    end
  end
end
