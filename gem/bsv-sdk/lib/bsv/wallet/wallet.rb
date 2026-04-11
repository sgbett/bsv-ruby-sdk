# frozen_string_literal: true

module BSV
  module Wallet
    # Holds a private key, sources UTXOs via a chain data provider, and
    # funds and signs P2PKH transactions.
    #
    # The provider is duck-typed — any object responding to
    # #fetch_utxos(address) and #fetch_transaction(txid) qualifies.
    class Wallet
      DUST_THRESHOLD = 1

      attr_reader :private_key, :provider

      def initialize(private_key:, provider:)
        @private_key = private_key
        @provider = provider
      end

      def address(network: :mainnet)
        @private_key.public_key.address(network: network)
      end

      def balance(network: :mainnet)
        @provider.fetch_utxos(address(network: network)).sum(&:satoshis)
      end

      def fund(tx, network: :mainnet, satoshis_per_byte: 0.1)
        utxos = @provider.fetch_utxos(address(network: network))
        output_total = tx.total_output_satoshis

        # Add a dummy change output so fee estimation accounts for its size
        dummy_change = BSV::Transaction::TransactionOutput.new(
          satoshis: 0, locking_script: locking_script
        )
        tx.add_output(dummy_change)

        input_total = tx.total_input_satoshis
        funded = false

        utxos.each do |utxo|
          tx.add_input(build_input(utxo))
          input_total += utxo.satoshis

          fee = tx.estimated_fee(satoshis_per_byte: satoshis_per_byte)
          if input_total >= output_total + fee
            funded = true
            break
          end
        end

        # Remove the dummy change output
        tx.outputs.delete(dummy_change)

        unless funded
          fee = tx.estimated_fee(satoshis_per_byte: satoshis_per_byte)
          raise InsufficientFundsError.new(required: output_total + fee, available: input_total)
        end

        add_change_if_needed(tx, input_total, output_total, satoshis_per_byte)

        tx
      end

      def sign(tx)
        tx.sign_all(@private_key)
      end

      def fund_and_sign(tx, network: :mainnet, satoshis_per_byte: 0.1)
        fund(tx, network: network, satoshis_per_byte: satoshis_per_byte)
        sign(tx)
      end

      private

      def locking_script
        @locking_script ||= BSV::Script::Script.p2pkh_lock(@private_key.public_key.hash160)
      end

      def build_input(utxo)
        input = BSV::Transaction::TransactionInput.new(
          prev_tx_id: BSV::Transaction::TransactionInput.txid_from_hex(utxo.tx_hash),
          prev_tx_out_index: utxo.tx_pos
        )
        input.source_satoshis = utxo.satoshis
        input.source_locking_script = locking_script
        input.unlocking_script_template = BSV::Transaction::P2PKH.new(@private_key)
        input
      end

      def add_change_if_needed(tx, input_total, output_total, satoshis_per_byte)
        fee_without_change = tx.estimated_fee(satoshis_per_byte: satoshis_per_byte)
        remainder = input_total - output_total - fee_without_change

        return if remainder < DUST_THRESHOLD

        change_output = BSV::Transaction::TransactionOutput.new(
          satoshis: remainder, locking_script: locking_script
        )
        tx.add_output(change_output)

        # Recalculate: adding the change output increases fee slightly
        new_fee = tx.estimated_fee(satoshis_per_byte: satoshis_per_byte)
        fee_increase = new_fee - fee_without_change
        final_change = remainder - fee_increase

        if final_change >= DUST_THRESHOLD
          tx.outputs.delete(change_output)
          tx.add_output(
            BSV::Transaction::TransactionOutput.new(
              satoshis: final_change, locking_script: locking_script
            )
          )
        else
          tx.outputs.delete(change_output) # change absorbed by fee
        end
      end
    end
  end
end
