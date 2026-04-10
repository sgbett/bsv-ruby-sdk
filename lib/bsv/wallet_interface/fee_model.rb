# frozen_string_literal: true

module BSV
  module Wallet
    # Lightweight fee estimation model for the wallet layer.
    #
    # Provides two distinct methods:
    # - {#estimate} — estimates a fee from component counts, before a Transaction
    #   object exists. Useful during coin selection and change calculation.
    # - {#compute} — delegates to the SDK's {BSV::Transaction::FeeModels::SatoshisPerKilobyte}
    #   for an already-built Transaction object, using its measured/estimated size.
    #
    # Size constants are based on standard P2PKH inputs and outputs:
    #
    #   Overhead:         10 bytes  (version 4 + locktime 4 + vin count ~1 + vout count ~1)
    #   P2PKH input:     148 bytes  (outpoint 36 + sequence 4 + script_len 1 + sig ~72 + pubkey 33 + push ops 2)
    #   P2PKH output:     34 bytes  (value 8 + script_len 1 + script 25)
    #
    # @example
    #   model = BSV::Wallet::FeeModel.new(sats_per_kb: 50)
    #   model.estimate(p2pkh_inputs: 2, p2pkh_outputs: 3)  # => 21
    #   model.compute(transaction)                          # => actual fee for built tx
    class FeeModel
      # Transaction overhead in bytes: version (4) + locktime (4) + vin count (~1) + vout count (~1).
      OVERHEAD = 10

      # Estimated size of a P2PKH input in bytes.
      # Breakdown: outpoint (36) + sequence (4) + script_len (1) + DER sig (~72) + pubkey (33) + push ops (2).
      P2PKH_INPUT_SIZE = 148

      # Estimated size of a P2PKH output in bytes.
      # Breakdown: value (8) + script_len (1) + locking script (25).
      P2PKH_OUTPUT_SIZE = 34

      # @return [Integer] the configured fee rate in satoshis per kilobyte
      attr_reader :sats_per_kb

      # @param sats_per_kb [Integer] fee rate in satoshis per kilobyte (default: 1)
      # @raise [ArgumentError] if sats_per_kb is zero or negative
      def initialize(sats_per_kb: 1)
        raise ArgumentError, 'sats_per_kb must be greater than zero' unless sats_per_kb.positive?

        @sats_per_kb = sats_per_kb
      end

      # Estimates the fee in satoshis from component counts, before a Transaction exists.
      #
      # Uses fixed P2PKH size constants to approximate the serialised transaction size,
      # then applies the configured rate. Returns a minimum of 1 satoshi.
      #
      # @param p2pkh_inputs [Integer] number of P2PKH inputs
      # @param p2pkh_outputs [Integer] number of P2PKH outputs
      # @return [Integer] estimated fee in satoshis (minimum 1)
      def estimate(p2pkh_inputs:, p2pkh_outputs:)
        size = OVERHEAD + (p2pkh_inputs * P2PKH_INPUT_SIZE) + (p2pkh_outputs * P2PKH_OUTPUT_SIZE)
        fee = (size / 1000.0 * @sats_per_kb).ceil
        [1, fee].max
      end

      # Computes the fee for an already-built Transaction object.
      #
      # Delegates to {BSV::Transaction::FeeModels::SatoshisPerKilobyte}, which uses
      # the transaction's measured or template-estimated size.
      #
      # @param transaction [BSV::Transaction::Transaction] a built transaction
      # @return [Integer] computed fee in satoshis
      def compute(transaction)
        sdk_model.compute_fee(transaction)
      end

      private

      def sdk_model
        @sdk_model ||= BSV::Transaction::FeeModels::SatoshisPerKilobyte.new(value: @sats_per_kb)
      end
    end
  end
end
