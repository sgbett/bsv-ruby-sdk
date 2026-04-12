# frozen_string_literal: true

# Broadcast job queue table for the SolidQueueAdapter.
#
# Tracks outbound transactions that need to be broadcast to the network,
# with state machine, retry counters, and advisory locking support so that
# multiple worker processes can poll the queue without double-processing.
#
# === Columns
#
# * +txid+              — TEXT NOT NULL UNIQUE. Prevents duplicate queue entries
#                         for the same transaction.
#
# * +status+            — TEXT NOT NULL DEFAULT 'unsent'. State machine values:
#                         'unsent', 'sending', 'completed', 'failed'.
#
# * +beef_hex+          — TEXT NOT NULL. Serialised BEEF payload to broadcast.
#
# * +input_outpoints+   — text[], nullable. Outpoints consumed by the tx, used
#                         to release UTXOs on success or rollback on failure.
#
# * +change_outpoints+  — text[], nullable. Change outpoints created by the tx,
#                         used to mark outputs spendable after confirmation.
#
# * +fund_ref+          — TEXT, nullable. Caller-supplied funding reference for
#                         observability and reconciliation.
#
# * +attempts+          — INTEGER NOT NULL DEFAULT 0. Incremented on each
#                         broadcast attempt; gates retry logic.
#
# * +last_error+        — TEXT, nullable. Message from the last failed attempt.
#
# * +locked_at+         — TIMESTAMPTZ, nullable. Set when a worker claims the
#                         job; cleared on completion or stale-lock recovery.
#
# * +created_at+        — TIMESTAMPTZ NOT NULL DEFAULT NOW().
#
# * +updated_at+        — TIMESTAMPTZ NOT NULL DEFAULT NOW().
#
# === Index
#
# A composite index on +(status, locked_at)+ (named +broadcast_jobs_poll_idx+)
# supports the hot-path poll query:
#
#   WHERE status = 'unsent'
#      OR (status = 'sending' AND locked_at < NOW() - interval '300 seconds'
#          AND attempts < 5)
#   ORDER BY created_at
#   FOR UPDATE SKIP LOCKED
Sequel.migration do
  change do
    create_table(:wallet_broadcast_jobs) do
      primary_key :id, type: :Bignum
      String   :txid,             null: false, unique: true
      String   :status,           null: false, default: 'unsent'
      String   :beef_hex,         text: true, null: false
      column   :input_outpoints,  'text[]'
      column   :change_outpoints, 'text[]'
      String   :fund_ref
      Integer  :attempts,         null: false, default: 0
      String   :last_error,       text: true
      column :locked_at,   :timestamptz
      column :created_at,  :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :updated_at,  :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      index %i[status locked_at], name: :broadcast_jobs_poll_idx
    end
  end
end
