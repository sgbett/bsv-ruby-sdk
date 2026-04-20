# frozen_string_literal: true

module BSV
  module Wallet
    # Selects UTXOs from an available pool to fund a transaction.
    #
    # Given a target amount and a fee model, the selector chooses the minimum
    # set of UTXOs needed to cover `target + fee`. It supports two strategies:
    #
    # - `:standard` — tries an exact match, then smallest-sufficient, then
    #   falls back to largest-first accumulation.
    # - `:largest_first` — skips exact/smallest checks and goes straight to
    #   largest-first accumulation.
    #
    # Fee estimation uses {BSV::Wallet::FeeEstimator} with P2PKH size constants.
    # During accumulation a potential change output is included in the fee
    # estimate, so the caller can always produce change if needed.
    #
    # @example
    #   estimator = BSV::Wallet::FeeEstimator.new(sats_per_kb: 1)
    #   selector  = BSV::Wallet::CoinSelector.new(fee_estimator: estimator)
    #   result    = selector.select(available: utxos, target_satoshis: 1000, num_outputs: 1)
    #   # => { inputs: [...], fee: 1, total_satoshis: 1001, excess: 0 }
    class CoinSelector
      VALID_STRATEGIES = %i[standard largest_first].freeze

      # @param fee_estimator [BSV::Wallet::FeeEstimator] fee estimation model
      #   (also accepted as +fee_model:+ for backwards compatibility)
      # @param strategy      [Symbol] selection strategy — `:standard` or `:largest_first`
      # @raise [ArgumentError] if strategy is not recognised
      def initialize(fee_estimator: nil, fee_model: nil, strategy: :standard)
        raise ArgumentError, "unknown strategy #{strategy.inspect}; use :standard or :largest_first" unless VALID_STRATEGIES.include?(strategy)
        raise ArgumentError, 'provide fee_estimator: or fee_model:, not both' if fee_estimator && fee_model

        @fee_model = fee_estimator || fee_model || raise(ArgumentError, 'fee_estimator: (or fee_model:) is required')
        @strategy  = strategy
      end

      # Selects UTXOs to cover +target_satoshis+ plus estimated fees.
      #
      # @param available       [Array<Hash>] pool of UTXOs; each hash must have a +:satoshis+ key
      # @param target_satoshis [Integer]     amount to fund (excluding fee)
      # @param num_outputs     [Integer]     number of recipient outputs in the transaction
      # @return [Hash] with keys +:inputs+, +:fee+, +:total_satoshis+, +:excess+
      # @raise [BSV::Wallet::InsufficientFundsError] when the pool cannot cover target + fees
      def select(available:, target_satoshis:, num_outputs:)
        raise InsufficientFundsError.new(available: 0, required: target_satoshis) if available.empty?

        result = case @strategy
                 when :standard then standard_select(available, target_satoshis, num_outputs)
                 when :largest_first then accumulate(available, target_satoshis, num_outputs)
                 end

        result || raise_insufficient(available, target_satoshis)
      end

      private

      # Tries exact match → smallest sufficient → accumulation.
      def standard_select(available, target_satoshis, num_outputs)
        exact_match(available, target_satoshis, num_outputs) ||
          smallest_sufficient(available, target_satoshis, num_outputs) ||
          accumulate(available, target_satoshis, num_outputs)
      end

      # Returns a result if a single UTXO covers exactly target + fee (no change).
      def exact_match(available, target_satoshis, num_outputs)
        fee = @fee_model.estimate(p2pkh_inputs: 1, p2pkh_outputs: num_outputs)
        needed = target_satoshis + fee

        utxo = available.find { |u| u[:satoshis] == needed }
        return unless utxo

        build_result([utxo], target_satoshis, fee)
      end

      # Returns the smallest single UTXO that is ≥ target + fee.
      def smallest_sufficient(available, target_satoshis, num_outputs)
        fee = @fee_model.estimate(p2pkh_inputs: 1, p2pkh_outputs: num_outputs)
        needed = target_satoshis + fee

        utxo = available
               .select { |u| u[:satoshis] >= needed }
               .min_by { |u| u[:satoshis] }
        return unless utxo

        build_result([utxo], target_satoshis, fee)
      end

      # Accumulates UTXOs largest-first until total ≥ target + fee.
      # Fee is recalculated with each additional input and includes one
      # potential change output (+1 to num_outputs).
      def accumulate(available, target_satoshis, num_outputs)
        sorted   = available.sort_by { |u| -u[:satoshis] }
        selected = []
        total    = 0

        sorted.each do |utxo|
          selected << utxo
          total += utxo[:satoshis]

          fee = @fee_model.estimate(
            p2pkh_inputs: selected.size,
            p2pkh_outputs: num_outputs + 1
          )

          return build_result(selected, target_satoshis, fee) if total >= target_satoshis + fee
        end

        nil
      end

      def build_result(inputs, target_satoshis, fee)
        total = inputs.sum { |u| u[:satoshis] }
        {
          inputs: inputs,
          fee: fee,
          total_satoshis: total,
          excess: total - target_satoshis - fee
        }
      end

      def raise_insufficient(available, target_satoshis)
        total_available = available.sum { |u| u[:satoshis] }
        raise InsufficientFundsError.new(
          available: total_available,
          required: target_satoshis
        )
      end
    end
  end
end
