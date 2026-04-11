# frozen_string_literal: true

RSpec.describe BSV::Wallet::Wallet do
  let(:private_key) { BSV::Primitives::PrivateKey.generate }
  let(:public_key) { private_key.public_key }
  let(:address) { public_key.address(network: :mainnet) }
  let(:locking_script) { BSV::Script::Script.p2pkh_lock(public_key.hash160) }

  # A mock provider returning configurable UTXOs
  let(:provider_class) do
    Class.new do
      attr_accessor :utxos

      def initialize(utxos = [])
        @utxos = utxos
      end

      def fetch_utxos(_address)
        @utxos
      end

      def fetch_transaction(_txid)
        nil
      end
    end
  end

  def make_utxo(satoshis, tx_hash: SecureRandom.hex(32), tx_pos: 0)
    BSV::Network::UTXO.new(tx_hash: tx_hash, tx_pos: tx_pos, satoshis: satoshis)
  end

  def make_op_return_output(data = 'hello')
    BSV::Transaction::TransactionOutput.new(
      satoshis: 0,
      locking_script: BSV::Script::Script.op_return(data)
    )
  end

  def make_p2pkh_output(satoshis)
    BSV::Transaction::TransactionOutput.new(
      satoshis: satoshis,
      locking_script: locking_script
    )
  end

  describe '#address' do
    it 'returns the address derived from the private key' do
      provider = provider_class.new
      wallet = described_class.new(private_key: private_key, provider: provider)

      expect(wallet.address).to eq(address)
    end

    it 'supports testnet network' do
      provider = provider_class.new
      wallet = described_class.new(private_key: private_key, provider: provider)
      testnet_address = public_key.address(network: :testnet)

      expect(wallet.address(network: :testnet)).to eq(testnet_address)
    end
  end

  describe '#balance' do
    it 'returns the sum of UTXO satoshis' do
      utxos = [make_utxo(50_000), make_utxo(30_000)]
      provider = provider_class.new(utxos)
      wallet = described_class.new(private_key: private_key, provider: provider)

      expect(wallet.balance).to eq(80_000)
    end

    it 'returns 0 when there are no UTXOs' do
      provider = provider_class.new([])
      wallet = described_class.new(private_key: private_key, provider: provider)

      expect(wallet.balance).to eq(0)
    end
  end

  describe '#fund' do
    it 'adds inputs from UTXOs to cover outputs plus fee' do
      utxos = [make_utxo(100_000)]
      provider = provider_class.new(utxos)
      wallet = described_class.new(private_key: private_key, provider: provider)

      tx = BSV::Transaction::Transaction.new
      tx.add_output(make_p2pkh_output(10_000))

      wallet.fund(tx)

      expect(tx.inputs.length).to eq(1)
      expect(tx.inputs.first.source_satoshis).to eq(100_000)
    end

    it 'sets source_locking_script on inputs' do
      utxos = [make_utxo(100_000)]
      provider = provider_class.new(utxos)
      wallet = described_class.new(private_key: private_key, provider: provider)

      tx = BSV::Transaction::Transaction.new
      tx.add_output(make_p2pkh_output(10_000))

      wallet.fund(tx)

      expect(tx.inputs.first.source_locking_script).to eq(locking_script)
    end

    it 'adds a change output when remainder is above dust threshold' do
      utxos = [make_utxo(100_000)]
      provider = provider_class.new(utxos)
      wallet = described_class.new(private_key: private_key, provider: provider)

      tx = BSV::Transaction::Transaction.new
      tx.add_output(make_p2pkh_output(10_000))

      wallet.fund(tx)

      # Should have original output + change output
      expect(tx.outputs.length).to eq(2)
      change = tx.outputs.last
      expect(change.satoshis).to be > 0
      expect(change.locking_script.to_hex).to eq(locking_script.to_hex)
    end

    it 'omits change output when remainder is below dust threshold' do
      # Build a dummy tx with 1 input + 2 outputs (including dummy change)
      # to estimate the fee the fund algorithm will see during UTXO selection.
      dummy_tx = BSV::Transaction::Transaction.new
      dummy_tx.add_output(make_p2pkh_output(10_000))
      dummy_tx.add_output(make_p2pkh_output(0)) # dummy change
      dummy_input = BSV::Transaction::TransactionInput.new(
        prev_tx_id: "\x00" * 32,
        prev_tx_out_index: 0
      )
      dummy_input.unlocking_script_template = BSV::Transaction::P2PKH.new(private_key)
      dummy_tx.add_input(dummy_input)
      fee_with_change = dummy_tx.estimated_fee(satoshis_per_byte: 0.1)

      # UTXO covers output + fee (with change) exactly — no room for actual change
      utxos = [make_utxo(10_000 + fee_with_change)]
      provider = provider_class.new(utxos)
      wallet = described_class.new(private_key: private_key, provider: provider)

      tx = BSV::Transaction::Transaction.new
      tx.add_output(make_p2pkh_output(10_000))

      wallet.fund(tx)

      expect(tx.outputs.length).to eq(1) # no change output
    end

    it 'preserves existing outputs' do
      utxos = [make_utxo(100_000)]
      provider = provider_class.new(utxos)
      wallet = described_class.new(private_key: private_key, provider: provider)

      tx = BSV::Transaction::Transaction.new
      tx.add_output(make_op_return_output)
      tx.add_output(make_p2pkh_output(5_000))

      wallet.fund(tx)

      expect(tx.outputs[0].satoshis).to eq(0)
      expect(tx.outputs[1].satoshis).to eq(5_000)
    end

    it 'raises InsufficientFundsError when UTXOs cannot cover outputs' do
      utxos = [make_utxo(100)]
      provider = provider_class.new(utxos)
      wallet = described_class.new(private_key: private_key, provider: provider)

      tx = BSV::Transaction::Transaction.new
      tx.add_output(make_p2pkh_output(100_000))

      expect { wallet.fund(tx) }.to raise_error(BSV::Wallet::InsufficientFundsError) do |error|
        expect(error.available).to eq(100)
        expect(error.required).to be > 100_000
      end
    end

    it 'raises InsufficientFundsError when there are no UTXOs' do
      provider = provider_class.new([])
      wallet = described_class.new(private_key: private_key, provider: provider)

      tx = BSV::Transaction::Transaction.new
      tx.add_output(make_p2pkh_output(1_000))

      expect { wallet.fund(tx) }.to raise_error(BSV::Wallet::InsufficientFundsError) do |error|
        expect(error.available).to eq(0)
      end
    end

    it 'uses multiple UTXOs when one is not enough' do
      utxos = [make_utxo(3_000, tx_hash: 'aa' * 32), make_utxo(3_000, tx_hash: 'bb' * 32)]
      provider = provider_class.new(utxos)
      wallet = described_class.new(private_key: private_key, provider: provider)

      tx = BSV::Transaction::Transaction.new
      tx.add_output(make_p2pkh_output(5_000))

      wallet.fund(tx)

      expect(tx.inputs.length).to eq(2)
    end

    it 'returns the transaction for chaining' do
      utxos = [make_utxo(100_000)]
      provider = provider_class.new(utxos)
      wallet = described_class.new(private_key: private_key, provider: provider)

      tx = BSV::Transaction::Transaction.new
      tx.add_output(make_p2pkh_output(10_000))

      result = wallet.fund(tx)

      expect(result).to be(tx)
    end
  end

  describe '#sign' do
    it 'delegates to tx.sign_all and adds unlocking scripts' do
      utxos = [make_utxo(100_000)]
      provider = provider_class.new(utxos)
      wallet = described_class.new(private_key: private_key, provider: provider)

      tx = BSV::Transaction::Transaction.new
      tx.add_output(make_p2pkh_output(10_000))
      wallet.fund(tx)

      wallet.sign(tx)

      tx.inputs.each do |input|
        expect(input.unlocking_script).not_to be_nil
      end
    end
  end

  describe '#fund_and_sign' do
    it 'produces a funded and signed transaction' do
      utxos = [make_utxo(100_000)]
      provider = provider_class.new(utxos)
      wallet = described_class.new(private_key: private_key, provider: provider)

      tx = BSV::Transaction::Transaction.new
      tx.add_output(make_p2pkh_output(10_000))

      wallet.fund_and_sign(tx)

      expect(tx.inputs.length).to be >= 1
      expect(tx.inputs.first.unlocking_script).not_to be_nil
      expect(tx.total_input_satoshis).to be >= tx.total_output_satoshis
    end

    it 'produces a serialisable transaction' do
      utxos = [make_utxo(100_000)]
      provider = provider_class.new(utxos)
      wallet = described_class.new(private_key: private_key, provider: provider)

      tx = BSV::Transaction::Transaction.new
      tx.add_output(make_p2pkh_output(10_000))

      wallet.fund_and_sign(tx)

      hex = tx.to_hex
      expect(hex).to be_a(String)
      expect(hex.length).to be > 0

      # Round-trip: parse the serialised hex back
      parsed = BSV::Transaction::Transaction.from_hex(hex)
      expect(parsed.inputs.length).to eq(tx.inputs.length)
      expect(parsed.outputs.length).to eq(tx.outputs.length)
    end
  end
end
