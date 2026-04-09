# frozen_string_literal: true

# Shared test harness for specs that need a live PostgreSQL database.
#
# Specs tagged +:postgres+ are skipped gracefully if +DATABASE_URL+ is
# not set or the database is unreachable. CI provides a Postgres 16
# service container (see .github/workflows/ci.yml) so the tag runs by
# default there.
#
# Local developers running +bundle exec rake+ without Postgres still
# get a green suite — the postgres specs just skip.

require 'sequel'

POSTGRES_TEST_DB =
  if ENV['DATABASE_URL']
    begin
      db = Sequel.connect(ENV['DATABASE_URL'])
      db.test_connection
      db
    rescue Sequel::DatabaseConnectionError, Sequel::DatabaseError
      nil
    end
  end

POSTGRES_WALLET_TABLES = %i[
  wallet_outputs
  wallet_actions
  wallet_certificates
  wallet_proofs
  wallet_transactions
].freeze

# Apply the shipped wallet schema once per suite load. Idempotent — no
# harm if the tables already exist from a previous run. Lives in the
# helper so individual spec files do not need `before(:all)` blocks
# (which leak state between examples).
if POSTGRES_TEST_DB
  require 'bsv-wallet-postgres'
  BSV::Wallet::PostgresStore.migrate!(POSTGRES_TEST_DB)
end

RSpec.configure do |config|
  config.before(:each, :postgres) do
    skip 'postgres unavailable (set DATABASE_URL to a Postgres database)' unless POSTGRES_TEST_DB
  end
end
