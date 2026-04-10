# frozen_string_literal: true

module BSV
  module Wallet
    # Duck-typed storage interface for wallet persistence.
    #
    # Include this module in storage adapters and override all methods.
    # The default implementations raise NotImplementedError.
    module StorageAdapter
      def store_action(_action_data)
        raise NotImplementedError, "#{self.class}#store_action not implemented"
      end

      def find_actions(_query)
        raise NotImplementedError, "#{self.class}#find_actions not implemented"
      end

      def store_output(_output_data)
        raise NotImplementedError, "#{self.class}#store_output not implemented"
      end

      def find_outputs(_query)
        raise NotImplementedError, "#{self.class}#find_outputs not implemented"
      end

      def delete_output(_outpoint)
        raise NotImplementedError, "#{self.class}#delete_output not implemented"
      end

      def store_certificate(_cert_data)
        raise NotImplementedError, "#{self.class}#store_certificate not implemented"
      end

      def find_certificates(_query)
        raise NotImplementedError, "#{self.class}#find_certificates not implemented"
      end

      def delete_certificate(type:, serial_number:, certifier:)
        raise NotImplementedError, "#{self.class}#delete_certificate not implemented"
      end

      def count_actions(_query)
        raise NotImplementedError, "#{self.class}#count_actions not implemented"
      end

      def count_outputs(_query)
        raise NotImplementedError, "#{self.class}#count_outputs not implemented"
      end

      def count_certificates(_query)
        raise NotImplementedError, "#{self.class}#count_certificates not implemented"
      end

      def store_proof(_txid, _bump_hex)
        raise NotImplementedError, "#{self.class}#store_proof not implemented"
      end

      def find_proof(_txid)
        raise NotImplementedError, "#{self.class}#find_proof not implemented"
      end

      def store_transaction(_txid, _tx_hex)
        raise NotImplementedError, "#{self.class}#store_transaction not implemented"
      end

      def find_transaction(_txid)
        raise NotImplementedError, "#{self.class}#find_transaction not implemented"
      end

      # Transitions the state of an existing output.
      #
      # When +new_state+ is +:pending+, pass a +pending_reference:+ string to
      # associate the lock with a specific action. The adapter should record a
      # timestamp (ISO 8601 UTC) alongside the reference so stale locks can be
      # detected and released by {#release_stale_pending!}.
      #
      # When transitioning away from +:pending+, the adapter must clear any
      # stored +:pending_since+ and +:pending_reference+ metadata.
      #
      # @param _outpoint [String] the outpoint identifier (e.g. "txid.vout")
      # @param _new_state [Symbol] one of +:spendable+, +:pending+, +:spent+
      # @param _pending_reference [String, nil] caller-supplied label for a pending lock
      # @param _no_send [Boolean, nil] true if the lock belongs to a no_send transaction;
      #   these locks are exempt from automatic stale recovery via {#release_stale_pending!}
      # @raise [NotImplementedError]
      def update_output_state(_outpoint, _new_state, pending_reference: nil, no_send: nil)
        raise NotImplementedError, "#{self.class}#update_output_state not implemented"
      end

      # Atomically finds outputs by outpoint and marks them as +:pending+.
      #
      # This prevents TOCTOU races where two threads select the same UTXO
      # between +find_spendable_outputs+ and +update_output_state+.
      # Only outputs still in +:spendable+ state are locked; any that have
      # already transitioned are skipped.
      #
      # @param outpoints [Array<String>] outpoint identifiers to lock
      # @param reference [String] caller-supplied pending reference
      # @param no_send [Boolean] true if this is a no_send lock
      # @return [Array<String>] outpoints that were successfully locked
      def lock_utxos(outpoints, reference:, no_send: false)
        raise NotImplementedError, "#{self.class}#lock_utxos not implemented"
      end

      # Returns only outputs whose effective state is +:spendable+.
      #
      # @param basket [String, nil] restrict to this basket when provided
      # @param min_satoshis [Integer, nil] exclude outputs below this value
      # @param sort_order [Symbol] +:asc+ or +:desc+ (default +:desc+, largest first)
      # @return [Array<Hash>]
      # @raise [NotImplementedError]
      def find_spendable_outputs(basket: nil, min_satoshis: nil, sort_order: :desc)
        raise NotImplementedError, "#{self.class}#find_spendable_outputs not implemented"
      end

      # Releases pending locks that have been held longer than +timeout+ seconds.
      #
      # Each output in +:pending+ state whose +:pending_since+ timestamp is older
      # than +timeout+ seconds is reverted to +:spendable+ and its pending
      # metadata is cleared.
      #
      # This is a no-op for adapters that do not support pending metadata.
      #
      # @param timeout [Integer] lock age in seconds before it is considered stale
      # @return [Integer] number of outputs released
      # @raise [NotImplementedError]
      def release_stale_pending!(timeout: 300)
        raise NotImplementedError, "#{self.class}#release_stale_pending! not implemented"
      end

      # Persists a named wallet setting.
      #
      # @param _key [String] the setting name
      # @param _value [Object] the setting value (must be JSON-serialisable)
      # @raise [NotImplementedError]
      def store_setting(_key, _value)
        raise NotImplementedError, "#{self.class}#store_setting not implemented"
      end

      # Retrieves a named wallet setting.
      #
      # @param _key [String] the setting name
      # @return [Object, nil] the stored value, or nil if not found
      # @raise [NotImplementedError]
      def find_setting(_key)
        raise NotImplementedError, "#{self.class}#find_setting not implemented"
      end
    end
  end
end
