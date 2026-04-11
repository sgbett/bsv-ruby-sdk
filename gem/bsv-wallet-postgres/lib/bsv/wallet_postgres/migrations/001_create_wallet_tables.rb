# frozen_string_literal: true

# Initial wallet schema for BSV::Wallet::PostgresStore.
#
# Five tables, all indexed for the query patterns the StorageAdapter
# interface exposes. JSONB blobs hold the full hash the SDK stored so
# adding fields to bsv-wallet's output/action/certificate records does
# not require a schema change — only the fields we actively filter on
# get dedicated indexed columns.
Sequel.migration do
  change do
    create_table(:wallet_outputs) do
      primary_key :id
      String :outpoint, null: false, unique: true
      String :basket
      column :tags, 'text[]'
      TrueClass :spendable, null: false, default: true
      jsonb :data, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index %i[basket spendable]
      index :tags, type: :gin
    end

    create_table(:wallet_actions) do
      primary_key :id
      String :txid, null: false
      column :labels, 'text[]'
      jsonb :data, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :labels, type: :gin
    end

    create_table(:wallet_certificates) do
      primary_key :id
      String :type, null: false
      String :serial_number, null: false
      String :certifier, null: false
      String :subject
      jsonb :data, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      unique %i[type serial_number certifier], name: :wallet_certificates_natural_key
      index :certifier
      index :subject
    end

    create_table(:wallet_proofs) do
      String :txid, primary_key: true
      String :bump_hex, text: true, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:wallet_transactions) do
      String :txid, primary_key: true
      String :tx_hex, text: true, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end
