# frozen_string_literal: true

module BSV
  module Wallet
    # Synchronous broadcast queue adapter — the default for +WalletClient+.
    #
    # +InlineQueue+ replicates the current wallet broadcast behaviour exactly:
    #
    # * With a broadcaster: calls +broadcaster.broadcast+, promotes UTXO state on
    #   success, rolls back on failure.
    # * Without a broadcaster: promotes immediately and returns BEEF for the
    #   caller to broadcast manually (backwards-compatible fallback).
    #
    # Because this adapter executes synchronously, +async?+ returns +false+ and
    # the caller can rely on the returned hash containing the final result.
    class InlineQueue
      include BSV::Wallet::BroadcastQueue

      # @param broadcaster [#broadcast, nil] broadcaster object; +nil+ disables broadcasting
      # @param storage [StorageAdapter] wallet storage adapter
      def initialize(storage:, broadcaster: nil)
        @broadcaster = broadcaster
        @storage = storage
      end

      # Returns +false+ — this adapter executes synchronously.
      #
      # @return [Boolean]
      def async?
        false
      end

      # Returns +true+ when a broadcaster has been configured.
      #
      # +WalletClient+ delegates its own +broadcast_enabled?+ to this method
      # so the check works correctly when the broadcaster is embedded in the
      # queue rather than passed directly to the wallet.
      #
      # @return [Boolean]
      def broadcast_enabled?
        !@broadcaster.nil?
      end

      # Returns the broadcast status for a previously enqueued transaction.
      #
      # Delegates to storage and returns the action status field, or +nil+ if
      # the action is not found.
      #
      # @param txid [String] hex transaction identifier
      # @return [String, nil]
      def status(txid)
        actions = @storage.find_actions({ txid: txid, limit: 1, offset: 0 })
        actions.first&.dig(:status)
      end

      # Broadcasts and promotes (or just promotes) a transaction synchronously.
      #
      # Dispatches to +broadcast_and_promote+ when a broadcaster is configured,
      # or +promote_without_broadcast+ when none is present.
      #
      # @param payload [Hash] broadcast payload (see +BroadcastQueue+ module docs)
      # @return [Hash] result hash containing at minimum +:txid+ and +:tx+
      def enqueue(payload)
        if @broadcaster
          broadcast_and_promote(payload)
        else
          promote_without_broadcast(payload)
        end
      end

      private

      # Broadcasts the transaction and promotes storage state on success.
      #
      # On broadcast failure with outpoints present, rolls back all pending
      # state (releases locked inputs, deletes change outputs, marks action
      # failed). On failure without outpoints (finalize path), only updates
      # the action status.
      #
      # INVARIANT: Only broadcast failure triggers rollback. If broadcast
      # succeeds but promotion raises, the error propagates — confirmed
      # on-chain outputs must never be deleted.
      #
      # @param payload [Hash] broadcast payload
      # @return [Hash] result hash
      def broadcast_and_promote(payload)
        tx               = payload[:tx]
        txid             = payload[:txid]
        beef_binary      = payload[:beef_binary]
        input_outpoints  = payload[:input_outpoints]
        change_outpoints = payload[:change_outpoints]
        fund_ref         = payload[:fund_ref]

        begin
          broadcast_result = @broadcaster.broadcast(tx)
        rescue StandardError => e
          if input_outpoints
            rollback(input_outpoints, change_outpoints, txid, fund_ref)
          elsif txid
            @storage.update_action_status(txid, 'failed')
          end
          return {
            txid: txid,
            tx: beef_binary.unpack('C*'),
            broadcast_error: e.message,
            broadcast_status: BroadcastQueue.status_for_error(e)
          }
        end

        # Broadcast succeeded — promote all pending state; set status to
        # 'unproven' (transaction is on-chain but lacks a merkle proof).
        # 'completed' is reserved for transactions confirmed by a proof-watcher.
        promote(input_outpoints, change_outpoints, txid, status: 'unproven')

        result = {
          txid: txid,
          tx: beef_binary.unpack('C*'),
          broadcast_result: broadcast_result,
          broadcast_status: 'success'
        }
        result[:competing_txs] = broadcast_result.competing_txs if broadcast_result.respond_to?(:competing_txs) && broadcast_result.competing_txs
        result
      end

      # Promotes UTXO state without broadcasting.
      #
      # This path is reached when no broadcaster is configured. It is only
      # valid when +accept_delayed_broadcast+ is set on the create_action
      # call — the caller explicitly accepts that the transaction will be
      # broadcast out-of-band. Action status is set to +unproven+.
      #
      # +completed+ is reserved for transactions that have received a merkle
      # proof (set by +internalize_action+ or a future proof-watcher).
      #
      # Defensive guard: raises +WalletError+ if reached without
      # +accept_delayed_broadcast+. The normal entry point for this guard is
      # the +create_action+ validation added in Task 1 (#456), but this guard
      # protects against other code paths that bypass it.
      #
      # @param payload [Hash] broadcast payload
      # @return [Hash] result hash containing +:txid+ and +:tx+
      # @raise [BSV::Wallet::WalletError] if +accept_delayed_broadcast+ is not set
      def promote_without_broadcast(payload)
        txid             = payload[:txid]
        beef_binary      = payload[:beef_binary]
        input_outpoints  = payload[:input_outpoints]
        change_outpoints = payload[:change_outpoints]
        delayed          = payload[:accept_delayed_broadcast]

        unless delayed
          raise BSV::Wallet::WalletError,
                'InlineQueue cannot promote without a broadcaster unless ' \
                'accept_delayed_broadcast is set. This indicates a bypass of ' \
                'the create_action guard — report as a bug.'
        end

        promote(input_outpoints, change_outpoints, txid, status: 'unproven')

        { txid: txid, tx: beef_binary.unpack('C*') }
      end

      # Promotes UTXO state: marks inputs as +:spent+, change as +:spendable+,
      # and updates the action status.
      #
      # When +outpoints+ arguments are +nil+ (finalize path), UTXO transitions
      # are skipped and only the action status is updated.
      #
      # @param input_outpoints [Array<String>, nil]
      # @param change_outpoints [Array<String>, nil]
      # @param txid [String, nil]
      # @param status [String]
      def promote(input_outpoints, change_outpoints, txid, status: 'completed')
        Array(input_outpoints).each { |op| @storage.update_output_state(op, :spent) }
        Array(change_outpoints).each { |op| @storage.update_output_state(op, :spendable) }
        @storage.update_action_status(txid, status) if txid
      end

      # Rolls back a pending auto-funded action.
      #
      # Releases locked inputs (only those matching +fund_ref+), deletes phantom
      # change outputs, and marks the action as +failed+.
      #
      # @param input_outpoints [Array<String>] outpoints locked as inputs
      # @param change_outpoints [Array<String>] change outputs to delete
      # @param txid [String, nil] action txid
      # @param fund_ref [String] fund reference used when locking inputs
      def rollback(input_outpoints, change_outpoints, txid, fund_ref)
        Array(input_outpoints).each do |op|
          outputs = @storage.find_outputs({ outpoint: op, include_spent: true, limit: 1, offset: 0 })
          next if outputs.empty?
          next unless outputs.first[:pending_reference] == fund_ref

          @storage.update_output_state(op, :spendable)
        end
        Array(change_outpoints).each { |op| @storage.delete_output(op) }
        @storage.update_action_status(txid, 'failed') if txid
      end
    end
  end
end
