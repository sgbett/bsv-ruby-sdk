# frozen_string_literal: true

# Add pending lock metadata columns and satoshis to wallet_outputs.
#
# Introduces dedicated columns to support the auto-fund UTXO management
# methods (+find_spendable_outputs+, +lock_utxos+, +update_output_state+,
# +release_stale_pending!+) without requiring expensive JSONB extraction
# on every query.
#
# === Columns added
#
# * +satoshis+          — bigint, nullable. Mirrors the value stored inside
#                         the JSONB +data+ blob so that +find_spendable_outputs+
#                         can +ORDER BY satoshis+ without casting. New writes
#                         populate this column; existing rows leave it NULL
#                         and queries fall back to +COALESCE(satoshis, (data->>'satoshis')::bigint, 0)+.
#
# * +pending_since+     — timestamp (UTC), nullable. Set to +NOW()+ when a
#                         UTXO is locked via +lock_utxos+. Used by
#                         +release_stale_pending!+ to identify stale locks.
#
# * +pending_reference+ — text, nullable. Caller-supplied label passed to
#                         +lock_utxos+. Carried through for observability.
#
# * +no_send+           — boolean, default +false+. When +true+ the lock is
#                         exempt from automatic stale recovery by
#                         +release_stale_pending!+.
#
# === Index added
#
# A partial index on +(state, basket)+ filtered to rows where
# +state IS NULL OR state = 'spendable'+ accelerates the hot path of
# +find_spendable_outputs+: the vast majority of rows in a live wallet
# are spendable, not pending or spent.
#
# === Backward compatibility
#
# All new columns are nullable (or carry a safe default). No existing rows
# are modified. The application layer handles NULL values via +COALESCE+ or
# explicit IS NULL checks.
Sequel.migration do
  up do
    alter_table(:wallet_outputs) do
      add_column :satoshis,          :bigint, null: true
      add_column :pending_since,     :timestamptz, null: true
      add_column :pending_reference, String,   null: true
      add_column :no_send,           :boolean, null: false, default: false
    end

    # Partial index on spendable rows only — keeps the index small and
    # fast for the typical coin-selection scan.
    run <<~SQL
      CREATE INDEX wallet_outputs_spendable_basket_idx
        ON wallet_outputs (state, basket)
        WHERE (state IS NULL OR state = 'spendable');
    SQL
  end

  down do
    run 'DROP INDEX IF EXISTS wallet_outputs_spendable_basket_idx;'

    alter_table(:wallet_outputs) do
      drop_column :no_send
      drop_column :pending_reference
      drop_column :pending_since
      drop_column :satoshis
    end
  end
end
