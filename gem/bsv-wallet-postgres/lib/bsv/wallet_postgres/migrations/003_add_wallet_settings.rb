# frozen_string_literal: true

# Add wallet settings table to BSV::Wallet::PostgresStore.
#
# Provides key-value persistence for wallet configuration (e.g. change
# output parameters). Keys are short strings (e.g. 'change_params');
# values are JSON-serialised strings so the schema never needs to change
# when setting shapes evolve.
#
# The table uses +key+ as its primary key so +store_setting+ is a simple
# upsert (insert-or-replace on conflict).
Sequel.migration do
  change do
    create_table(:wallet_settings) do
      String :key, primary_key: true
      String :value, text: true, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end
