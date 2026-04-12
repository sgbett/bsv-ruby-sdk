# frozen_string_literal: true

# Add a unique index on wallet_actions.txid.
#
# Within a single wallet there should be at most one action per transaction.
# Without this constraint, concurrent inserts or retries could create duplicate
# rows sharing the same txid, causing +update_action_status+ to update multiple
# rows unintentionally.
#
# The index also accelerates the +where(txid:)+ lookups performed by
# +update_action_status+ and +delete_action+.
#
# === Backward compatibility
#
# The migration will fail if duplicate txids already exist in the table. Clean
# up any duplicates before running this migration:
#
#   DELETE FROM wallet_actions a
#   USING wallet_actions b
#   WHERE a.id > b.id AND a.txid = b.txid;
Sequel.migration do
  change do
    alter_table(:wallet_actions) do
      add_index :txid, unique: true, name: :wallet_actions_txid_unique
    end
  end
end
