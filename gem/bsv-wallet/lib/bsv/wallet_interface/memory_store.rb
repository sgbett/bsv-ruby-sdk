# frozen_string_literal: true

module BSV
  module Wallet
    # In-memory storage adapter intended for testing and development only.
    #
    # Stores actions, outputs, and certificates in plain Ruby arrays.
    # All data is lost when the process exits — do not use in production.
    # Use PostgresStore (or another persistent adapter) for production wallets.
    #
    # Thread safety: a +Mutex+ serialises all state-mutating operations so that
    # concurrent threads cannot select and mark the same UTXO as pending.
    # This makes MemoryStore safe within a single Ruby process.
    #
    # NOTE: FileStore is NOT process-safe — concurrent processes share no
    # in-memory lock and may read stale state from disk.
    #
    # == Production Warning
    #
    # When +RACK_ENV+, +RAILS_ENV+, or +APP_ENV+ is set to +production+ or
    # +staging+, a warning is emitted to stderr. Suppress it with either:
    #
    #   BSV_MEMORY_STORE_OK=1               # environment variable
    #   MemoryStore.warn_in_production = false  # Ruby flag (e.g. in test setup)
    class MemoryStore
      include StorageAdapter

      # Controls whether the production-environment warning is emitted.
      # Set to +false+ in test suites to silence the warning globally.
      #
      # @return [Boolean]
      def self.warn_in_production?
        @warn_in_production != false
      end

      class << self
        attr_writer :warn_in_production
      end

      def initialize
        @actions = []
        @outputs = []
        @certificates = []
        @proofs = {}
        @transactions = {}
        @settings = {}
        @mutex = Mutex.new

        return unless self.class.warn_in_production? && production_env?

        warn '[bsv-wallet] MemoryStore is intended for testing only. ' \
             'Use PostgresStore for production wallets. ' \
             'Set BSV_MEMORY_STORE_OK=1 to silence this warning.'
      end

      def store_action(action_data)
        @actions << action_data
        action_data
      end

      def update_action_status(txid, new_status)
        action = @actions.find { |a| a[:txid] == txid }
        raise WalletError, "Action not found: #{txid}" unless action

        action[:status] = new_status
        action
      end

      def delete_action(txid)
        idx = @actions.index { |a| a[:txid] == txid }
        return false unless idx

        @actions.delete_at(idx)
        true
      end

      def find_actions(query)
        apply_pagination(filter_actions(query), query)
      end

      def count_actions(query)
        filter_actions(query).length
      end

      def store_output(output_data)
        @outputs << output_data
        output_data
      end

      def find_outputs(query)
        apply_pagination(filter_outputs(query), query)
      end

      def count_outputs(query)
        filter_outputs(query).length
      end

      def delete_output(outpoint)
        idx = @outputs.index { |o| o[:outpoint] == outpoint }
        return false unless idx

        @outputs.delete_at(idx)
        true
      end

      # Transitions the state of an existing output.
      #
      # When +new_state+ is +:pending+, a +:pending_since+ (ISO 8601 UTC) and
      # +:pending_reference+ are attached to the output so stale locks can be
      # detected via {#release_stale_pending!}.
      #
      # Pass +no_send: true+ to mark the lock as belonging to a +no_send+
      # transaction; these locks are exempt from automatic stale recovery and
      # must be released explicitly via +abort_action+.
      #
      # When transitioning away from +:pending+, all pending metadata is cleared.
      #
      # This method is wrapped in a mutex to prevent concurrent transitions on
      # the same output from two threads.
      #
      # @param outpoint [String] the outpoint identifier
      # @param new_state [Symbol] +:spendable+, +:pending+, or +:spent+
      # @param pending_reference [String, nil] caller-supplied label for the lock
      # @param no_send [Boolean, nil] true if the lock is for a no_send transaction
      # @raise [BSV::Wallet::WalletError] if the outpoint is not found
      def update_output_state(outpoint, new_state, pending_reference: nil, no_send: nil)
        @mutex.synchronize do
          output = @outputs.find { |o| o[:outpoint] == outpoint }
          raise WalletError, "Output not found: #{outpoint}" unless output

          output[:state] = new_state

          if new_state == :pending
            output[:pending_since]     = Time.now.utc.iso8601
            output[:pending_reference] = pending_reference
            no_send ? output[:no_send] = true : output.delete(:no_send)
          else
            output.delete(:pending_since)
            output.delete(:pending_reference)
            output.delete(:no_send)
          end

          output
        end
      end

      # Atomically locks the specified outpoints as +:pending+.
      #
      # Holds the mutex for the entire operation so no other thread can
      # read or transition these outputs between the check and the lock.
      #
      # @param outpoints [Array<String>] outpoint identifiers to lock
      # @param reference [String] caller-supplied pending reference
      # @param no_send [Boolean] true if this is a no_send lock
      # @return [Array<String>] outpoints successfully locked
      def lock_utxos(outpoints, reference:, no_send: false)
        now = Time.now.utc.iso8601
        locked = []

        @mutex.synchronize do
          outpoints.each do |op|
            output = @outputs.find { |o| o[:outpoint] == op }
            next unless output && effective_state(output) == :spendable

            output[:state] = :pending
            output[:pending_since] = now
            output[:pending_reference] = reference
            no_send ? output[:no_send] = true : output.delete(:no_send)
            locked << op
          end
        end

        locked
      end

      # Returns only outputs whose effective state is +:spendable+.
      #
      # Legacy outputs that carry no +:state+ key are treated as spendable
      # when +spendable:+ is not explicitly +false+.
      #
      # This method is wrapped in the same mutex as {#update_output_state} so
      # that a thread cannot select a UTXO that another thread is simultaneously
      # marking as pending.
      #
      # @param basket [String, nil] restrict to this basket when provided
      # @param min_satoshis [Integer, nil] exclude outputs below this value
      # @param sort_order [Symbol] +:asc+ or +:desc+ (default +:desc+, largest first)
      # @return [Array<Hash>]
      def find_spendable_outputs(basket: nil, min_satoshis: nil, sort_order: :desc)
        @mutex.synchronize do
          results = @outputs.select { |o| effective_state(o) == :spendable }
          results = results.select { |o| o[:basket] == basket } if basket
          results = results.select { |o| (o[:satoshis] || 0) >= min_satoshis } if min_satoshis
          results.sort_by { |o| sort_order == :asc ? (o[:satoshis] || 0) : -(o[:satoshis] || 0) }
        end
      end

      # Releases pending locks that have been held longer than +timeout+ seconds.
      #
      # Each output in +:pending+ state whose +:pending_since+ timestamp is older
      # than +timeout+ seconds is reverted to +:spendable+ and its pending
      # metadata is cleared.
      #
      # @param timeout [Integer] lock age in seconds before it is considered stale (default 300)
      # @return [Integer] number of outputs released
      def release_stale_pending!(timeout: 300)
        cutoff = Time.now.utc - timeout
        released = 0

        @mutex.synchronize do
          @outputs.each do |output|
            next unless effective_state(output) == :pending
            next if output[:no_send]
            next unless output[:pending_since]

            locked_at = Time.parse(output[:pending_since])
            next unless locked_at < cutoff

            output[:state] = :spendable
            output.delete(:pending_since)
            output.delete(:pending_reference)
            released += 1
          end
        end

        released
      end

      def store_certificate(cert_data)
        @certificates << cert_data
        cert_data
      end

      def find_certificates(query)
        apply_pagination(filter_certificates(query), query)
      end

      def count_certificates(query)
        filter_certificates(query).length
      end

      def store_proof(txid, bump_hex)
        @proofs[txid] = bump_hex
      end

      def find_proof(txid)
        @proofs[txid]
      end

      def store_transaction(txid, tx_hex)
        @transactions[txid] = tx_hex
      end

      def find_transaction(txid)
        @transactions[txid]
      end

      def delete_certificate(type:, serial_number:, certifier:)
        idx = @certificates.index do |c|
          c[:type] == type && c[:serial_number] == serial_number && c[:certifier] == certifier
        end
        return false unless idx

        @certificates.delete_at(idx)
        true
      end

      # Persists a named wallet setting.
      #
      # @param key [String] the setting name
      # @param value [Object] the setting value (must be JSON-serialisable)
      def store_setting(key, value)
        @settings[key] = value
      end

      # Retrieves a named wallet setting.
      #
      # @param key [String] the setting name
      # @return [Object, nil] the stored value, or nil if not found
      def find_setting(key)
        @settings[key]
      end

      private

      # Returns true when the process is running in a production or staging
      # environment and the operator has not explicitly acknowledged MemoryStore
      # usage via the +BSV_MEMORY_STORE_OK+ environment variable.
      def production_env?
        env = ENV['RACK_ENV'] || ENV['RAILS_ENV'] || ENV.fetch('APP_ENV', nil)
        env && %w[production staging].include?(env) && !ENV['BSV_MEMORY_STORE_OK']
      end

      def filter_actions(query)
        results = @actions
        return results unless query[:labels]

        mode = query[:label_query_mode] || 'any'
        results.select do |a|
          action_labels = a[:labels] || []
          if mode == 'all'
            (query[:labels] - action_labels).empty?
          else
            (query[:labels] & action_labels).any?
          end
        end
      end

      def filter_outputs(query)
        results = @outputs
        results = results.select { |o| o[:outpoint] == query[:outpoint] } if query[:outpoint]
        results = results.select { |o| o[:basket] == query[:basket] } if query[:basket]
        if query[:tags]
          mode = query[:tag_query_mode] || 'any'
          results = results.select do |o|
            output_tags = o[:tags] || []
            if mode == 'all'
              (query[:tags] - output_tags).empty?
            else
              (query[:tags] & output_tags).any?
            end
          end
        end
        query[:include_spent] ? results : results.select { |o| effective_state(o) == :spendable }
      end

      # Resolves the effective state of an output from either the new +:state+
      # field or the legacy +:spendable+ boolean, giving +:state+ precedence.
      #
      # The +:state+ value may be a Symbol or a String (the latter arises after
      # a JSON round-trip in FileStore); both are normalised to a Symbol here.
      #
      # Legacy mapping:
      #   - +spendable: false+           → +:spent+
      #   - +spendable: true+ (or absent) → +:spendable+
      def effective_state(output)
        state = output[:state]
        return state.to_sym if state

        output[:spendable] == false ? :spent : :spendable
      end

      def filter_certificates(query)
        results = @certificates
        results = results.select { |c| query[:certifiers].include?(c[:certifier]) } if query[:certifiers]
        results = results.select { |c| query[:types].include?(c[:type]) } if query[:types]
        results = results.select { |c| c[:subject] == query[:subject] } if query[:subject]
        if query[:attributes]
          results = results.select do |c|
            fields = c[:fields] || {}
            query[:attributes].all? { |k, v| fields[k] == v || fields[k.to_sym] == v }
          end
        end
        results
      end

      def apply_pagination(results, query)
        offset = query[:offset] || 0
        limit = query[:limit] || 10
        results[offset, limit] || []
      end
    end
  end
end
