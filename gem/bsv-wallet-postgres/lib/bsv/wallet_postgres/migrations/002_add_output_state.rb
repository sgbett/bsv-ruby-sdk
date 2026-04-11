# frozen_string_literal: true

# Add output lifecycle state column to wallet_outputs.
#
# Introduces a nullable +state+ text column alongside the existing boolean
# +spendable+ column. The two fields are kept in sync by the application
# layer (+PostgresStore#update_output_state+).
#
# === State values
#
# * +spendable+ — the output is available for coin selection
# * +pending+   — the output has been selected but the spending transaction
#                 has not yet been broadcast or confirmed
# * +spent+     — the output has been consumed by a confirmed transaction
#
# === Backward compatibility
#
# Rows written before this migration have +state = NULL+. The application
# treats +state IS NULL AND spendable = TRUE+ as equivalent to
# +state = 'spendable'+ so that existing data continues to behave
# correctly without a backfill.
#
# The migration is intentionally non-destructive: +state+ is nullable
# so the migration itself applies instantly on large tables (no rewrite,
# no default scan). A backfill can be run offline if required.
Sequel.migration do
  change do
    alter_table(:wallet_outputs) do
      add_column :state, String, null: true
      add_index :state
    end
  end
end
