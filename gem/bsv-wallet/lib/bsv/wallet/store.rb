# frozen_string_literal: true

module BSV
  module Wallet
    # Storage implementations. See {Interface::Store} for the contract.
    #
    # The public API is {Store::File} — a JSON file-backed adapter that
    # persists across process restarts. For production use, see also
    # +bsv-wallet-postgres+ for a PostgreSQL-backed adapter.
    #
    # {Store::Memory} is an internal base class used by FileStore. It is
    # not autoloaded and should not be used directly — data is lost when
    # the process exits, including derived key material needed to spend
    # change outputs.
    module Store
      autoload :File, 'bsv/wallet/store/file'
    end
  end
end
