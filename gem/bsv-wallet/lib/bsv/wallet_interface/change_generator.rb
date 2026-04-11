# frozen_string_literal: true

require 'securerandom'

module BSV
  module Wallet
    # Generates BRC-29 change outputs for excess satoshis in a transaction.
    #
    # Handles the full lifecycle of change output creation:
    #   - Dust-floor enforcement (a change output is only worthwhile if its
    #     value covers at least 2× the cost to spend it later)
    #   - Optional distribution across multiple outputs with randomised splits
    #   - BRC-29 key derivation metadata attached to each output so the wallet
    #     can later identify and spend the change
    #
    # @example Single change output
    #   generator = BSV::Wallet::ChangeGenerator.new(key_deriver: deriver, fee_estimator: estimator)
    #   outputs = generator.generate(excess_satoshis: 5000)
    #   # => [{ satoshis: 5000, locking_script: ..., derivation_prefix: ..., ... }]
    #
    # @example Spread across multiple outputs
    #   generator = BSV::Wallet::ChangeGenerator.new(key_deriver: deriver, fee_estimator: estimator, max_outputs: 4)
    #   outputs = generator.generate(excess_satoshis: 10_000)
    #   # => up to 4 outputs summing to 10_000
    class ChangeGenerator
      # BRC-29 protocol identifier used for change key derivation.
      BRC29_PROTOCOL_ID = [2, '3241645161d8'].freeze

      # @return [Integer] maximum number of change outputs that may be created
      attr_reader :max_outputs

      # @param key_deriver [BSV::Wallet::KeyDeriver] derives child keys for each change output
      # @param fee_estimator [BSV::Wallet::FeeEstimator] used to compute the dust floor
      #   (also accepted as +fee_model:+ for backwards compatibility)
      # @param identity_key [String, nil] override identity key for change derivation;
      #   defaults to key_deriver.identity_key when nil
      # @param max_outputs [Integer] upper bound on change outputs (default: 8)
      # @raise [ArgumentError] if max_outputs is less than 1
      def initialize(key_deriver:, fee_estimator: nil, fee_model: nil, identity_key: nil, max_outputs: 8)
        raise ArgumentError, 'max_outputs must be at least 1' unless max_outputs >= 1
        raise ArgumentError, 'provide fee_estimator: or fee_model:, not both' if fee_estimator && fee_model

        @key_deriver = key_deriver
        @fee_model = fee_estimator || fee_model || raise(ArgumentError, 'fee_estimator: (or fee_model:) is required')
        @identity_key_override = identity_key
        @max_outputs = max_outputs
      end

      # Generates change outputs for the given excess satoshis.
      #
      # Returns an empty array when the excess is zero or below the dust floor.
      # Otherwise returns between 1 and {#max_outputs} output hashes, each with:
      #   - +:satoshis+ — value of the output
      #   - +:locking_script+ — P2PKH locking script for the derived key
      #   - +:derivation_prefix+ — random hex string for BRC-29 key derivation
      #   - +:derivation_suffix+ — random hex string for BRC-29 key derivation
      #   - +:sender_identity_key+ — wallet's own identity key (self-payment)
      #
      # When +pool_size:+ and +change_params:+ are both provided, the number of
      # change outputs is adjusted based on the pool's health:
      #   - Pool below target count: produce more outputs (up to +max_outputs+)
      #     to build up the UTXO pool.
      #   - Pool at or above target count: produce fewer outputs (1-2) to avoid
      #     unnecessary fragmentation.
      #
      # @param excess_satoshis [Integer] satoshis remaining after inputs minus outputs minus fee
      # @param num_existing_outputs [Integer] number of outputs already in the transaction
      #   (unused here but kept for interface symmetry with future callers)
      # @param pool_size [Integer, nil] current number of spendable UTXOs in the pool
      # @param change_params [Hash, nil] pool targets with +:count+ and +:satoshis+ keys
      # @return [Array<Hash>] change output descriptors (may be empty)
      def generate(excess_satoshis:, num_existing_outputs: 0, pool_size: nil, change_params: nil) # rubocop:disable Lint/UnusedMethodArgument
        return [] if excess_satoshis <= 0
        return [] if excess_satoshis < dust_floor

        effective_max = pool_aware_max_outputs(pool_size, change_params)
        amounts = split_amounts(excess_satoshis, effective_max)
        amounts.map { |amount| build_output(amount) }
      end

      private

      # The minimum value a change output must carry to be economically viable.
      # Set to 2× the estimated fee to spend a single P2PKH input, ensuring the
      # recipient never loses money by spending the output.
      #
      # @return [Integer] dust floor in satoshis (minimum 2)
      def dust_floor
        @dust_floor ||= [2, @fee_model.estimate(p2pkh_inputs: 1, p2pkh_outputs: 1) * 2].max
      end

      # Determines the effective maximum number of change outputs to produce,
      # taking pool health into account when +pool_size+ and +change_params+
      # are both present.
      #
      # - Pool below target: use full +max_outputs+ to build up the pool.
      # - Pool at/above target: cap at 2 to avoid unnecessary fragmentation.
      # - No params: return +max_outputs+ unchanged.
      #
      # @param pool_size [Integer, nil]
      # @param change_params [Hash, nil] hash with +:count+ key
      # @return [Integer]
      def pool_aware_max_outputs(pool_size, change_params)
        return @max_outputs unless pool_size && change_params

        target_count = change_params[:count] || change_params['count']
        return @max_outputs unless target_count

        pool_size < target_count ? @max_outputs : [2, @max_outputs].min
      end

      # Splits +excess+ across up to +cap+ amounts, each at least
      # {#dust_floor} satoshis. Any sub-dust remainder is folded into the largest
      # output.
      #
      # @param excess [Integer] total satoshis to split
      # @param cap [Integer] maximum number of outputs (defaults to +max_outputs+)
      # @return [Array<Integer>] per-output satoshi amounts
      def split_amounts(excess, cap = @max_outputs)
        return [excess] if cap == 1

        # Determine the maximum number of outputs we can afford given the dust floor.
        max_possible = [excess / dust_floor, cap].min
        num_outputs = [max_possible, 1].max

        return [excess] if num_outputs == 1

        distribute(excess, num_outputs)
      end

      # Randomly distributes +total+ satoshis across +count+ buckets, each
      # guaranteed to be at least {#dust_floor} satoshis. Any remainder below the
      # dust floor is consolidated into the largest bucket.
      #
      # @param total [Integer]
      # @param count [Integer] number of output buckets (>= 2)
      # @return [Array<Integer>]
      def distribute(total, count)
        # Reserve the dust floor for every bucket, then distribute the surplus.
        reserved = dust_floor * count
        surplus = total - reserved

        # Generate (count - 1) random cut-points within the surplus range,
        # then derive bucket sizes from the gaps between cut-points.
        cuts = Array.new(count - 1) { rand(surplus + 1) }.sort
        gaps = [cuts.first] + cuts.each_cons(2).map { |a, b| b - a } + [surplus - cuts.last]

        amounts = gaps.map { |g| g + dust_floor }

        consolidate_sub_dust(amounts)
      end

      # Folds any amounts that fell below the dust floor into the largest output.
      # This should be rare given the reservation logic, but guards against edge
      # cases from integer rounding.
      #
      # @param amounts [Array<Integer>]
      # @return [Array<Integer>]
      def consolidate_sub_dust(amounts)
        valid, sub_dust = amounts.partition { |a| a >= dust_floor }
        return amounts if sub_dust.empty?

        remainder = sub_dust.sum
        max_index = valid.each_with_index.max_by { |a, _| a }[1]
        valid[max_index] += remainder
        valid
      end

      # Builds a single change output hash with a freshly derived BRC-29 key.
      #
      # @param satoshis [Integer]
      # @return [Hash]
      def build_output(satoshis)
        prefix = SecureRandom.hex(16)
        suffix = SecureRandom.hex(16)
        identity_key = @identity_key_override || @key_deriver.identity_key
        key_id = "#{prefix} #{suffix}"

        pub_key = @key_deriver.derive_public_key(BRC29_PROTOCOL_ID, key_id, identity_key, for_self: true)
        locking_script = BSV::Script::Script.p2pkh_lock(pub_key.hash160)

        {
          satoshis: satoshis,
          locking_script: locking_script,
          derivation_prefix: prefix,
          derivation_suffix: suffix,
          sender_identity_key: identity_key
        }
      end
    end
  end
end
