# frozen_string_literal: true

module BSV
  module Wallet
    # Estimates transaction fees before a {BSV::Transaction::Transaction} object exists.
    #
    # Wraps {BSV::Transaction::FeeModels::SatoshisPerKilobyte} to provide pre-construction
    # fee estimation given only input and output counts. Once a real {Transaction} is
    # available, delegates directly to the underlying SDK fee model via {#estimate_for_tx}.
    #
    # The default rate is 100 sat/kB, matching the ARC mining policy endpoint
    # and the SDK's own {SatoshisPerKilobyte} default.
    #
    # @example Pre-construction estimate
    #   estimator = BSV::Wallet::FeeEstimator.new
    #   fee = estimator.estimate(p2pkh_inputs: 2, p2pkh_outputs: 3)
    #   # => 41 (at 100 sat/kB, ceil(408/1000 * 100) = 41)
    #
    # @example Custom rate
    #   estimator = BSV::Wallet::FeeEstimator.new(sats_per_kb: 50)
    #   fee = estimator.estimate(p2pkh_inputs: 1, p2pkh_outputs: 1)
    #   # => 10 (ceil(192/1000 * 50) = 10)
    class FeeEstimator
      # Estimated size in bytes of an unsigned P2PKH input.
      # Matches {BSV::Transaction::Transaction::UNSIGNED_P2PKH_INPUT_SIZE}.
      P2PKH_INPUT_SIZE = BSV::Transaction::Transaction::UNSIGNED_P2PKH_INPUT_SIZE

      # Estimated size in bytes of a P2PKH output (8 satoshis + varint(25) + 25-byte script).
      P2PKH_OUTPUT_SIZE = 34

      # Fixed overhead in bytes for version (4) and lock_time (4).
      FIXED_OVERHEAD = 8

      # Approximate overhead including typical 1-byte varints for input/output
      # counts. Retained for backward compatibility with code that referenced
      # +FeeModel::OVERHEAD+.
      OVERHEAD = 10

      # Default fee rate in satoshis per kilobyte, matching ARC's mining
      # policy endpoint (/v1/policy → miningFee 100/1000).
      DEFAULT_SATS_PER_KB = 100

      # @return [Integer] the satoshis-per-kilobyte rate used for estimation
      attr_reader :sats_per_kb

      # @param sats_per_kb [Integer] fee rate in satoshis per kilobyte
      # @raise [ArgumentError] if sats_per_kb is zero or negative
      def initialize(sats_per_kb: DEFAULT_SATS_PER_KB)
        raise ArgumentError, 'sats_per_kb must be greater than zero' unless sats_per_kb.positive?

        @sats_per_kb = sats_per_kb
        @sdk_model = BSV::Transaction::FeeModels::SatoshisPerKilobyte.new(value: sats_per_kb)
      end

      # Estimate the fee for a transaction described by input and output counts.
      #
      # Computes the serialised byte size using standard P2PKH sizes and correct
      # Bitcoin varint encoding for the input/output count fields, then applies
      # the configured sat/kB rate. Returns at least 1 satoshi.
      #
      # @param p2pkh_inputs [Integer] number of P2PKH inputs
      # @param p2pkh_outputs [Integer] number of P2PKH outputs
      # @param extra_bytes [Integer] additional bytes to include (e.g. OP_RETURN data)
      # @return [Integer] estimated fee in satoshis (minimum 1)
      def estimate(p2pkh_inputs:, p2pkh_outputs:, extra_bytes: 0)
        total_bytes = byte_size(p2pkh_inputs, p2pkh_outputs) + extra_bytes
        fee = (total_bytes / 1000.0 * @sats_per_kb).ceil
        [1, fee].max
      end

      # Compute the fee for a fully-constructed transaction.
      #
      # Delegates to the underlying {BSV::Transaction::FeeModels::SatoshisPerKilobyte}
      # model, which uses {BSV::Transaction::Transaction#estimated_size} internally.
      #
      # @param tx [BSV::Transaction::Transaction] the transaction to compute the fee for
      # @return [Integer] fee in satoshis
      def estimate_for_tx(tx)
        @sdk_model.compute_fee(tx)
      end

      # Alias for {#estimate_for_tx} — matches the SDK's +compute_fee+ naming.
      alias compute estimate_for_tx

      # Minimum viable change output value at the configured rate.
      #
      # An output is economically viable only if its value exceeds twice the cost of
      # spending it. The cost to spend a single P2PKH input is estimated as the fee
      # for a minimal 1-input / 1-output transaction.
      #
      # @return [Integer] minimum satoshis for a change output to be worth creating
      def dust_floor
        cost = (spend_one_p2pkh_bytes / 1000.0 * @sats_per_kb).ceil
        [1, cost * 2].max
      end

      private

      # Total byte size for a transaction with the given input/output counts.
      def byte_size(input_count, output_count)
        FIXED_OVERHEAD +
          varint_size(input_count) +
          (input_count * P2PKH_INPUT_SIZE) +
          varint_size(output_count) +
          (output_count * P2PKH_OUTPUT_SIZE)
      end

      # Byte size of a minimal single-input, single-output transaction.
      # Used to compute the cost of spending one P2PKH UTXO.
      def spend_one_p2pkh_bytes
        byte_size(1, 1)
      end

      # Number of bytes required to encode +n+ as a Bitcoin varint.
      def varint_size(n)
        if n < 0xFD
          1
        elsif n <= 0xFFFF
          3
        elsif n <= 0xFFFF_FFFF
          5
        else
          9
        end
      end
    end
  end
end
