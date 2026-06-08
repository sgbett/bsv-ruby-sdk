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
    let(:digest) { BSV::Primitives::Digest.sha256('test data') }

    let(:mock_wallet) do
      Class.new do
        def create_action(_args, _originator: nil)
          { txid: 'bb' * 32 }
        end
      end.new
    end

    let(:spy_wallet) do
      Class.new do
        attr_reader :last_args

        def create_action(args, _originator: nil)
          @last_args = args
          { txid: 'bb' * 32 }
        end
      end.new
    end

    it 'delegates to create_action and returns Response' do
      response = described_class.publish('test data', wallet: mock_wallet)

      expect(response).to be_a(BSV::Attest::Response)
      expect(response.hash).to eq(BSV::Primitives::Digest.sha256('test data'))
      expect(response.txid).to eq('bb' * 32)
    end

    it 'passes correct OP_RETURN output spec to create_action' do
      described_class.publish('test data', wallet: spy_wallet)

      output = spy_wallet.last_args[:outputs].first
      expect(output[:locking_script]).to eq(BSV::Script::Script.op_return(digest).to_hex)
      expect(output[:satoshis]).to eq(0)
      expect(output[:output_description]).to eq('Attestation hash')
      expect(spy_wallet.last_args[:options]).to eq({ randomize_outputs: false })
    end

    it 'uses default description' do
      described_class.publish('test data', wallet: spy_wallet)

      expect(spy_wallet.last_args[:description]).to eq('Attest data hash to chain')
    end

    it 'accepts custom description' do
      described_class.publish('test data', wallet: spy_wallet, description: 'Custom attestation description')

      expect(spy_wallet.last_args[:description]).to eq('Custom attestation description')
    end

    it 'raises ArgumentError without wallet' do
      expect do
        described_class.publish('test data')
      end.to raise_error(ArgumentError, /wallet/)
    end

    it 'raises BroadcastError on broadcast failure' do
      failing_wallet = Class.new do
        def create_action(_args, _originator: nil)
          { txid: 'bb' * 32, broadcast_error: 'transaction rejected' }
        end
      end.new

      expect do
        described_class.publish('test data', wallet: failing_wallet)
      end.to raise_error(BSV::Attest::BroadcastError, /transaction rejected/)
    end

    it 'accepts per-call wallet override' do
      described_class.configure { |c| c.wallet = mock_wallet }

      described_class.publish('test data', wallet: spy_wallet)
      expect(spy_wallet.last_args).not_to be_nil
    end

    it 'falls back to global configuration' do
      described_class.configure { |c| c.wallet = mock_wallet }

      response = described_class.publish('test data')
      expect(response).to be_a(BSV::Attest::Response)
    end
  end

  describe '.verify' do
    def build_mock_provider(data_to_attest)
      digest = BSV::Primitives::Digest.sha256(data_to_attest)
      script = BSV::Script::Script.op_return(digest)
      output = BSV::Transaction::TransactionOutput.new(satoshis: 0, locking_script: script)
      tx = BSV::Transaction::Tx.new
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
      tx = BSV::Transaction::Tx.new
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
