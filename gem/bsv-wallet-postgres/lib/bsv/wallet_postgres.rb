# frozen_string_literal: true

module BSV
  # Top-level module for the bsv-wallet-postgres gem.
  module WalletPostgres
    autoload :VERSION, 'bsv/wallet_postgres/version'
  end

  module Wallet
    autoload :PostgresStore, 'bsv/wallet_postgres/postgres_store'
    autoload :SolidQueueAdapter, 'bsv/wallet_postgres/solid_queue_adapter'
  end
end
